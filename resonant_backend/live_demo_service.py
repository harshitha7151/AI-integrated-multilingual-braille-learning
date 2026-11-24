"""Ephemeral, paired live-demo sessions and privacy-filtered event stream."""

from __future__ import annotations

from collections import deque
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
import asyncio
import re
import secrets
from typing import Any
from uuid import UUID


_FORBIDDEN_KEY = re.compile(
    r"(?:password|secret|token|credential|learner[_-]?id|username|email|phone|audio|recording)",
    re.IGNORECASE,
)
_EVENT_TYPE = re.compile(r"^[a-z][a-z0-9_]{1,63}$")
_MAX_EVENTS = 500
_MAX_QUEUED = 256
_TRANSCRIPT_KEYS = {"transcript", "question_text", "input_text", "response_text"}


def _clean_event_value(value: Any, include_transcripts: bool, depth: int = 0) -> Any:
    if depth > 3:
        raise DemoSessionError("Event payload nesting is too deep.")
    if value is None or isinstance(value, (int, float, bool)):
        return value
    if isinstance(value, str):
        if len(value) > 500:
            raise DemoSessionError("Event text is too long.")
        return value
    if isinstance(value, dict):
        if len(value) > 32:
            raise DemoSessionError("Nested event object is too large.")
        cleaned: dict[str, Any] = {}
        for key, item in value.items():
            if not isinstance(key, str) or len(key) > 64 or _FORBIDDEN_KEY.search(key):
                raise DemoSessionError("Event payload contains a private field.")
            if key.lower() in _TRANSCRIPT_KEYS and not include_transcripts:
                continue
            cleaned[key] = _clean_event_value(item, include_transcripts, depth + 1)
        return cleaned
    if isinstance(value, list):
        if len(value) > 32:
            raise DemoSessionError("Nested event list is too large.")
        return [_clean_event_value(item, include_transcripts, depth + 1) for item in value]
    raise DemoSessionError("Event value type is unsupported.")


def _event_component(event_type: str) -> tuple[str, str]:
    """Map known emitted events to actual project components and stages."""
    if event_type.startswith("speech_recognition"):
        return "android_speech_recognition", "speech_input"
    if event_type == "tutor_input_received":
        return "flutter_voice_tutor_controller", "tutor_input"
    if event_type.startswith("tutor_backend_request") or event_type.startswith("tutor_response"):
        return "tutor_gateway_and_backend", "tutor_processing"
    if "command_parsed" in event_type:
        return "deterministic_voice_command_parser", "command_resolution"
    if event_type.startswith("tutor_intent_"):
        return "ollama_structured_intent_interpreter", "intent_interpretation"
    if "action_validated" in event_type or "action_execution" in event_type:
        return "validated_tutor_action_controller", "action_validation"
    if "navigation" in event_type:
        return "flutter_navigation_state", "navigation"
    if "braille" in event_type:
        return "deterministic_braille_engine", "braille_mapping_or_validation"
    if event_type.startswith("tts_"):
        return "flutter_tts", "spoken_output"
    if any(token in event_type for token in ("lesson", "assessment", "language", "exercise", "hint", "mastery", "recommendation")):
        return "flutter_learning_state", "learning_activity"
    return "resonant_mobile_app", "application_event"


class DemoSessionError(ValueError):
    """A session is missing, expired, unauthorized, or malformed."""


@dataclass
class DemoSession:
    session_id: str
    pairing_code: str
    dashboard_token: str
    mobile_token: str
    expires_at: datetime
    include_transcripts: bool
    events: deque[dict[str, Any]] = field(default_factory=lambda: deque(maxlen=_MAX_EVENTS))
    seen_ids: set[str] = field(default_factory=set)
    queues: set[tuple[asyncio.Queue, asyncio.AbstractEventLoop]] = field(
        default_factory=set
    )
    sequence: int = 0
    mobile_connected: bool = False
    ended: bool = False


class LiveDemoRegistry:
    """In-memory sessions; events and credentials are never written to PostgreSQL."""

    def __init__(self, session_minutes: int = 60) -> None:
        self._session_minutes = session_minutes
        self._sessions: dict[str, DemoSession] = {}

    def _get_active(self, session_id: str) -> DemoSession:
        session = self._sessions.get(session_id)
        if (
            session is None
            or session.ended
            or session.expires_at <= datetime.now(timezone.utc)
        ):
            if session is not None:
                session.ended = True
                self._sessions.pop(session_id, None)
            raise DemoSessionError("Demo session is unavailable or expired.")
        return session

    def create(self, include_transcripts: bool = False) -> dict[str, Any]:
        self._purge_expired()
        session_id = secrets.token_urlsafe(18)
        session = DemoSession(
            session_id=session_id,
            pairing_code=secrets.token_urlsafe(12),
            dashboard_token=secrets.token_urlsafe(32),
            mobile_token=secrets.token_urlsafe(32),
            expires_at=datetime.now(timezone.utc)
            + timedelta(minutes=self._session_minutes),
            include_transcripts=include_transcripts,
        )
        self._sessions[session_id] = session
        return {
            "session_id": session_id,
            "pairing_code": session.pairing_code,
            "dashboard_token": session.dashboard_token,
            "expires_at": session.expires_at.isoformat(),
            "include_transcripts": session.include_transcripts,
        }

    def connect_mobile(self, session_id: str, pairing_code: str) -> dict[str, Any]:
        session = self._get_active(session_id)
        if not secrets.compare_digest(session.pairing_code, pairing_code.strip()):
            raise DemoSessionError("Pairing code is invalid.")
        session.mobile_connected = True
        return {"session_id": session.session_id, "mobile_token": session.mobile_token}

    def authorize_dashboard(self, session_id: str, token: str) -> DemoSession:
        session = self._get_active(session_id)
        if not secrets.compare_digest(session.dashboard_token, token):
            raise DemoSessionError("Dashboard authorization failed.")
        return session

    def authorize_mobile(self, session_id: str, token: str) -> DemoSession:
        session = self._get_active(session_id)
        if not session.mobile_connected or not secrets.compare_digest(
            session.mobile_token, token
        ):
            raise DemoSessionError("Mobile session authorization failed.")
        return session

    def status(self, session_id: str, token: str) -> dict[str, Any]:
        session = self.authorize_dashboard(session_id, token)
        return {
            "session_id": session.session_id,
            "status": "active",
            "mobile_connected": session.mobile_connected,
            "event_count": session.sequence,
            "expires_at": session.expires_at.isoformat(),
        }

    def publish(self, session: DemoSession, event: dict[str, Any]) -> dict[str, Any]:
        try:
            event_id = str(UUID(str(event.get("event_id", ""))))
        except (ValueError, TypeError, AttributeError) as error:
            raise DemoSessionError("Event ID must be a UUID.") from error
        event_type = event.get("event_type")
        if not isinstance(event_type, str) or not _EVENT_TYPE.fullmatch(event_type):
            raise DemoSessionError("Event type is invalid.")
        payload = event.get("payload", {})
        if not isinstance(payload, dict) or len(payload) > 24:
            raise DemoSessionError("Event payload is invalid or too large.")
        cleaned: dict[str, Any] = {}
        for key, value in payload.items():
            if not isinstance(key, str) or len(key) > 64 or _FORBIDDEN_KEY.search(key):
                raise DemoSessionError("Event payload contains a private field.")
            if key.lower() in _TRANSCRIPT_KEYS and not session.include_transcripts:
                continue
            cleaned[key] = _clean_event_value(value, session.include_transcripts)
        if event_id in session.seen_ids:
            existing = next((item for item in session.events if item["event_id"] == event_id), None)
            return {"accepted": True, "duplicate": True, "sequence": existing["sequence"] if existing else None}
        session.seen_ids.add(event_id)
        if len(session.seen_ids) > _MAX_EVENTS * 2:
            keep = {item["event_id"] for item in session.events}
            session.seen_ids.intersection_update(keep)
        session.sequence += 1
        record = {
            "event_id": event_id,
            "session_id": session.session_id,
            "sequence": session.sequence,
            "event_type": event_type,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "source": "flutter_mobile",
            "component": _event_component(event_type)[0],
            "stage": _event_component(event_type)[1],
            "correlation_id": str(event.get("correlation_id", ""))[:64] or None,
            "parent_event_id": str(event["parent_event_id"]) if event.get("parent_event_id") else None,
            "payload": cleaned,
        }
        session.events.append(record)
        for queue, loop in tuple(session.queues):
            if loop.is_closed():
                continue
            try:
                loop.call_soon_threadsafe(self._enqueue, queue, record)
            except RuntimeError:
                continue
        return {"accepted": True, "duplicate": False, "sequence": record["sequence"]}

    def end(self, session_id: str, token: str) -> None:
        session = self.authorize_dashboard(session_id, token)
        session.ended = True
        for queue, loop in tuple(session.queues):
            if loop.is_closed():
                continue
            try:
                loop.call_soon_threadsafe(self._enqueue_terminal, queue)
            except RuntimeError:
                continue
        self._sessions.pop(session_id, None)

    @staticmethod
    def _enqueue(queue: asyncio.Queue, event: dict[str, Any]) -> None:
        if queue.full():
            try:
                queue.get_nowait()
            except asyncio.QueueEmpty:
                pass
        try:
            queue.put_nowait(event)
        except asyncio.QueueFull:
            pass

    @staticmethod
    def _enqueue_terminal(queue: asyncio.Queue) -> None:
        if queue.full():
            try:
                queue.get_nowait()
            except asyncio.QueueEmpty:
                pass
        try:
            queue.put_nowait(None)
        except asyncio.QueueFull:
            pass

    def _purge_expired(self) -> None:
        now = datetime.now(timezone.utc)
        for session_id, session in tuple(self._sessions.items()):
            if session.expires_at <= now or session.ended:
                self._sessions.pop(session_id, None)


demo_sessions = LiveDemoRegistry()
