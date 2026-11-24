import asyncio
import os
from pathlib import Path
import sys
import unittest
from datetime import datetime, timedelta, timezone
from uuid import uuid4
from fastapi.testclient import TestClient

os.environ.setdefault("RESONANT_JWT_SECRET", "resonant-test-only-jwt-secret-never-use-in-production")
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import main

from live_demo_service import DemoSessionError, LiveDemoRegistry
from aiml_dashboard_service import compare_intent, dashboard_catalog


class LiveDemoRegistryTests(unittest.TestCase):
    def setUp(self):
        self.registry = LiveDemoRegistry()
        self.session = self.registry.create()
        self.session_id = self.session["session_id"]
        self.dashboard_token = self.session["dashboard_token"]
        paired = self.registry.connect_mobile(
            self.session_id, self.session["pairing_code"]
        )
        self.mobile_token = paired["mobile_token"]

    def event(self, **updates):
        event = {
            "event_id": str(uuid4()),
            "event_type": "language_changed",
            "payload": {"language": "Kannada"},
        }
        event.update(updates)
        return event

    def test_session_authorizes_only_paired_roles_and_can_end(self):
        with self.assertRaises(DemoSessionError):
            self.registry.authorize_mobile(self.session_id, self.dashboard_token)
        with self.assertRaises(DemoSessionError):
            self.registry.authorize_dashboard(self.session_id, self.mobile_token)
        self.registry.end(self.session_id, self.dashboard_token)
        with self.assertRaises(DemoSessionError):
            self.registry.authorize_dashboard(self.session_id, self.dashboard_token)

    def test_wrong_pairing_code_is_rejected(self):
        new_session = self.registry.create()
        with self.assertRaises(DemoSessionError):
            self.registry.connect_mobile(new_session["session_id"], "wrong-code-123")

    def test_events_are_ordered_and_duplicate_ids_are_idempotent(self):
        session = self.registry.authorize_mobile(self.session_id, self.mobile_token)
        event = self.event()
        first = self.registry.publish(session, event)
        duplicate = self.registry.publish(session, event)
        self.assertEqual(first["sequence"], 1)
        self.assertFalse(first["duplicate"])
        self.assertTrue(duplicate["duplicate"])
        self.assertEqual(duplicate["sequence"], 1)

    def test_private_payload_is_rejected_and_transcripts_default_off(self):
        session = self.registry.authorize_mobile(self.session_id, self.mobile_token)
        with self.assertRaises(DemoSessionError):
            self.registry.publish(session, self.event(payload={"email": "x@y.test"}))
        event = self.event(payload={"transcript": "teach me", "language": "English"})
        self.registry.publish(session, event)
        self.assertEqual(session.events[-1]["payload"], {"language": "English"})

    def test_structured_tutor_context_is_retained_but_nested_transcript_is_consent_gated(self):
        session = self.registry.authorize_mobile(self.session_id, self.mobile_token)
        event = self.event(payload={
            "context": {
                "screen": "assessment",
                "options": ["choice one", "choice two"],
                "input_text": "private utterance",
            },
            "proposed_action": {"name": "select_answer", "option_index": 1},
        })
        self.registry.publish(session, event)
        payload = session.events[-1]["payload"]
        self.assertEqual(payload["context"]["screen"], "assessment")
        self.assertEqual(payload["context"]["options"], ["choice one", "choice two"])
        self.assertNotIn("input_text", payload["context"])
        self.assertEqual(payload["proposed_action"]["name"], "select_answer")

    def test_invalid_event_and_expired_session_are_rejected(self):
        session = self.registry.authorize_mobile(self.session_id, self.mobile_token)
        with self.assertRaises(DemoSessionError):
            self.registry.publish(session, self.event(event_type="Bad Event"))
        session.expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
        with self.assertRaises(DemoSessionError):
            self.registry.authorize_dashboard(self.session_id, self.dashboard_token)

    def test_publish_dispatches_to_subscriber_loop_thread_safely(self):
        class RecordingLoop:
            def is_closed(self):
                return False

            def call_soon_threadsafe(self, callback, *args):
                callback(*args)

        class RecordingQueue:
            def __init__(self):
                self.items = []

            def full(self):
                return len(self.items) >= 2

            def get_nowait(self):
                return self.items.pop(0)

            def put_nowait(self, value):
                if self.full():
                    raise asyncio.QueueFull
                self.items.append(value)

        queue = RecordingQueue()
        session = self.registry.authorize_mobile(self.session_id, self.mobile_token)
        session.queues.add((queue, RecordingLoop()))
        self.registry.publish(
            session,
            self.event(event_type="language_changed", payload={"language": "Kannada"}),
        )
        self.assertEqual(queue.items[0]["event_type"], "language_changed")
        self.assertEqual(queue.items[0]["payload"], {"language": "Kannada"})


class LiveDemoApiTests(unittest.TestCase):
    def test_mobile_event_reaches_authorized_dashboard_websocket(self):
        client = TestClient(main.app)
        created = client.post("/demo/sessions", json={"include_transcripts": False})
        self.assertEqual(created.status_code, 201)
        session = created.json()
        paired = client.post(
            f"/demo/sessions/{session['session_id']}/mobile",
            json={"pairing_code": session["pairing_code"]},
        )
        self.assertEqual(paired.status_code, 200)
        with client.websocket_connect(
            f"/ws/demo/sessions/{session['session_id']}?token={session['dashboard_token']}"
        ) as socket:
            connected = socket.receive_json()
            self.assertEqual(connected["kind"], "connected")
            published = client.post(
                f"/demo/sessions/{session['session_id']}/events",
                headers={"Authorization": f"Bearer {paired.json()['mobile_token']}"},
                json={
                    "event_id": str(uuid4()),
                    "event_type": "language_changed",
                    "payload": {"language": "Kannada"},
                },
            )
            self.assertEqual(published.status_code, 200)
            event = socket.receive_json()
            self.assertEqual(event["event_type"], "language_changed")
            self.assertEqual(event["payload"], {"language": "Kannada"})
        unauthorized = client.post(
            f"/demo/sessions/{session['session_id']}/events",
            json={"event_id": str(uuid4()), "event_type": "language_changed"},
        )
        self.assertEqual(unauthorized.status_code, 401)


class DashboardCatalogTests(unittest.TestCase):
    def test_saved_logistic_pipeline_returns_real_experimental_features_and_scores(self):
        result = compare_intent("change to Kannada", ["tfidf_logistic_regression"])
        model = result["results"][0]
        self.assertTrue(model["experimental"])
        self.assertFalse(model["controls_live_application"])
        self.assertEqual(model["scores"]["kind"], "class_probability")
        self.assertGreater(model["vocabulary_size"], 0)
        self.assertTrue(model["features"])

    def test_dashboard_routes_serve_dashboard_and_experiment_metadata(self):
        client = TestClient(main.app)
        page = client.get("/aiml/dashboard")
        self.assertEqual(page.status_code, 200)
        self.assertIn("Live mobile session", page.text)
        catalog = client.get("/aiml/dashboard/catalog")
        self.assertEqual(catalog.status_code, 200)
        self.assertIn("experiments", catalog.json())

    def test_dashboard_serves_three_js_explorer_module(self):
        client = TestClient(main.app)
        script = client.get("/aiml/dashboard/three-lab.js")
        self.assertEqual(script.status_code, 200)
        self.assertIn("resonant-live-event", script.text)
        self.assertIn("3D view unavailable", script.text)
        self.assertIn("lib/tutor/voice_command_parser.dart", script.text)

    def test_braille_explorer_uses_verified_engine_mappings(self):
        client = TestClient(main.app)
        english = client.post(
            "/aiml/braille/encode", json={"text": "A", "language": "English"}
        )
        self.assertEqual(english.status_code, 200)
        # Uppercase A is dot 6 capital indicator followed by dot 1.
        self.assertEqual(
            [(cell["dots"], cell["encoding"]) for cell in english.json()["cells"]],
            [([6], 32), ([1], 1)],
        )
        hindi = client.post(
            "/aiml/braille/encode", json={"text": "अ", "language": "Hindi"}
        )
        kannada = client.post(
            "/aiml/braille/encode", json={"text": "ಅ", "language": "Kannada"}
        )
        self.assertEqual(hindi.status_code, 200)
        self.assertEqual(kannada.status_code, 200)
        self.assertTrue(hindi.json()["verified"])
        self.assertTrue(kannada.json()["verified"])
        self.assertEqual(hindi.json()["cells"][0]["dots"], [1])
        self.assertEqual(kannada.json()["cells"][0]["dots"], [1])
        unsupported = client.post(
            "/aiml/braille/encode", json={"text": "😀", "language": "Hindi"}
        )
        self.assertEqual(unsupported.status_code, 422)

    def test_live_event_contains_server_timestamp_component_stage_and_parent(self):
        registry = LiveDemoRegistry()
        created = registry.create()
        paired = registry.connect_mobile(created["session_id"], created["pairing_code"])
        session = registry.authorize_mobile(created["session_id"], paired["mobile_token"])
        parent = uuid4()
        record = registry.publish(session, {
            "event_id": str(uuid4()),
            "event_type": "tutor_command_parsed",
            "parent_event_id": str(parent),
            "payload": {"command": "nextLesson"},
        })
        event = session.events[-1]
        self.assertEqual(record["sequence"], event["sequence"])
        self.assertEqual(event["component"], "deterministic_voice_command_parser")
        self.assertEqual(event["stage"], "command_resolution")
        self.assertEqual(event["parent_event_id"], str(parent))
        self.assertTrue(event["timestamp"])

    def test_structured_intent_event_is_attributed_to_the_interpreter(self):
        registry = LiveDemoRegistry()
        created = registry.create()
        paired = registry.connect_mobile(created["session_id"], created["pairing_code"])
        session = registry.authorize_mobile(created["session_id"], paired["mobile_token"])
        registry.publish(session, {
            "event_id": str(uuid4()),
            "event_type": "tutor_intent_interpreted",
            "payload": {"method": "ollama_structured_intent", "intent": "start_word_test"},
        })
        event = session.events[-1]
        self.assertEqual(event["component"], "ollama_structured_intent_interpreter")
        self.assertEqual(event["stage"], "intent_interpretation")
    def test_catalog_separates_live_deterministic_from_experimental_models(self):
        catalog = dashboard_catalog()
        live = catalog["live_application"]
        self.assertIn("Deterministic", live["intent_resolution"])
        self.assertIn("information gain", live["recommendations"])
        self.assertIn("five observations", live["recommendations"])
        self.assertIn("not the live recommender", live["recommendations"])
        self.assertTrue(all(not model["live_application"] for model in catalog["experiments"]["models"]))


if __name__ == "__main__":
    unittest.main()
