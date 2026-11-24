"""Teacher authentication: sign-up, login, token issuance, and verification.

Passwords are hashed with bcrypt (via passlib).
Tokens are signed JWTs (via python-jose) with a 30-day expiry.
Emails and passwords are never written to logs.
Login attempts are rate-limited per email (in-memory sliding window).
"""

import os
import time
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from uuid import uuid4

from database import get_connection

# ── optional deps: passlib + python-jose ──────────────────────────────────
try:
    from passlib.context import CryptContext
    _pwd_ctx = CryptContext(schemes=["bcrypt"], deprecated="auto")
    _BCRYPT_OK = True
except ImportError:          # pragma: no cover
    _BCRYPT_OK = False
    _pwd_ctx = None          # type: ignore[assignment]

try:
    from jose import JWTError, jwt as _jwt
    _JWT_OK = True
except ImportError:          # pragma: no cover
    _JWT_OK = False
    _jwt = None              # type: ignore[assignment]

def _get_jwt_secret() -> str:
    secret = os.getenv("RESONANT_JWT_SECRET")
    if not secret or not secret.strip():
        raise RuntimeError(
            "RESONANT_JWT_SECRET environment variable is missing or empty. "
            "Server cannot sign or verify tokens without a configured secret."
        )
    return secret.strip()

_ALGORITHM = "HS256"
_EXPIRY_DAYS = 30
_RESET_TOKEN_EXPIRY_MINUTES = 15

# ── rate limiting: max 10 attempts per email per 10 minutes ───────────────
_rate: dict[str, list[float]] = defaultdict(list)
_RATE_WINDOW = 600   # seconds
_RATE_MAX    = 10


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _hash_password(plain: str) -> str:
    if not _BCRYPT_OK:
        raise RuntimeError("passlib[bcrypt] is not installed.")
    return _pwd_ctx.hash(plain)


def _verify_password(plain: str, hashed: str) -> bool:
    if not _BCRYPT_OK:
        raise RuntimeError("passlib[bcrypt] is not installed.")
    return _pwd_ctx.verify(plain, hashed)


def _create_token(teacher_id: str) -> str:
    if not _JWT_OK:
        raise RuntimeError("python-jose is not installed.")
    exp = datetime.now(timezone.utc) + timedelta(days=_EXPIRY_DAYS)
    return _jwt.encode(
        {"sub": teacher_id, "exp": exp},
        _get_jwt_secret(),
        algorithm=_ALGORITHM,
    )


def _ensure_signup_auth_ready() -> None:
    """Reject signup before INSERT if the resulting account cannot be logged in."""
    if not _JWT_OK:
        raise RuntimeError("python-jose is not installed.")
    _get_jwt_secret()


def _decode_token(token: str) -> str:
    """Return teacher_id or raise JWTError."""
    if not _JWT_OK:
        raise RuntimeError("python-jose is not installed.")
    payload = _jwt.decode(token, _get_jwt_secret(), algorithms=[_ALGORITHM])
    return payload["sub"]


def _check_rate(email_key: str) -> bool:
    """Return True if the request is allowed; False if rate-limited."""
    now = time.monotonic()
    attempts = _rate[email_key]
    # Drop attempts outside the window.
    _rate[email_key] = [t for t in attempts if now - t < _RATE_WINDOW]
    if len(_rate[email_key]) >= _RATE_MAX:
        return False
    _rate[email_key].append(now)
    return True


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def signup_teacher(name: str, email: str, password: str,
                   organization: str | None) -> dict:
    """Create a new teacher account; raise ValueError on duplicate email."""
    teacher_id = str(uuid4())
    password_hash = _hash_password(password)
    # Flutter logs in immediately after signup. Verify that token issuance is
    # available before writing a row, or a failed login would leave an account
    # that the learner believes was never created.
    _ensure_signup_auth_ready()
    with get_connection() as conn:
        try:
            row = conn.execute(
                """
                INSERT INTO resonant.teachers
                    (teacher_id, name, email, password_hash, organization)
                VALUES (%s, %s, lower(%s), %s, %s)
                RETURNING teacher_id, name, email, organization, created_at
                """,
                (teacher_id, name, email, password_hash, organization or None),
            ).fetchone()
        except Exception as exc:
            if "unique" in str(exc).lower():
                raise ValueError("email_taken") from exc
            raise
    return dict(row)


def login_teacher(email: str, password: str) -> dict:
    """Verify credentials; return {teacher_id, name, email, token} or raise.

    Raises ValueError('rate_limited'), ValueError('invalid_credentials').
    """
    email_key = email.lower().strip()
    if not _check_rate(email_key):
        raise ValueError("rate_limited")
    with get_connection() as conn:
        row = conn.execute(
            """
            SELECT teacher_id, name, email, password_hash, organization
            FROM resonant.teachers WHERE email = lower(%s)
            """,
            (email,),
        ).fetchone()
    if row is None or not _verify_password(password, row["password_hash"]):
        raise ValueError("invalid_credentials")
    token = _create_token(str(row["teacher_id"]))
    return {
        "teacher_id": str(row["teacher_id"]),
        "name": row["name"],
        "email": row["email"],
        "organization": row.get("organization"),
        "token": token,
    }


def verify_token(token: str) -> str:
    """Return teacher_id or raise ValueError('invalid_token')."""
    try:
        return _decode_token(token)
    except Exception as exc:
        raise ValueError("invalid_token") from exc


def get_teacher_learners(teacher_id: str) -> list[dict]:
    """Return lightweight learner list for a teacher's dashboard."""
    with get_connection() as conn:
        rows = conn.execute(
            """
            SELECT learner_id, name, batch, preferred_language, created_at
            FROM resonant.learners
            WHERE teacher_id = %s
            ORDER BY created_at DESC
            """,
            (teacher_id,),
        ).fetchall()
    return [dict(r) for r in rows]


def _format_skill_to_letter(skill_id: str) -> str:
    """Extract human-readable letter or skill representation."""
    if not skill_id:
        return ""
    # Skills are often like 'english-letter-a' or 'letter-a' or 'english-a'
    parts = skill_id.split("-")
    if len(parts) > 1 and len(parts[-1]) == 1:
        return parts[-1].upper()
    return skill_id


def get_teacher_dashboard_data(teacher_id: str) -> dict:
    """Compute aggregate and per-learner metrics for all learners of this teacher."""
    with get_connection() as conn:
        learners_rows = conn.execute(
            """
            SELECT learner_id, name, batch, preferred_language, created_at
            FROM resonant.learners
            WHERE teacher_id = %s
            ORDER BY created_at DESC
            """,
            (teacher_id,),
        ).fetchall()

    now = datetime.now(timezone.utc)
    learners = []

    for l_row in learners_rows:
        lid = str(l_row["learner_id"])
        with get_connection() as conn:
            # 1. Total attempts and accuracy
            stats = conn.execute(
                """
                SELECT
                    COUNT(*) as total_attempts,
                    COUNT(*) FILTER (WHERE outcome = 'correct') as correct_attempts,
                    COUNT(*) FILTER (WHERE created_at >= %s - interval '7 days') as attempts_7d,
                    MAX(created_at) as last_active_at
                FROM resonant.practice_attempts
                WHERE learner_id = %s
                """,
                (now, lid),
            ).fetchone()

            # 2. Latest attempt to determine current stage/letter
            latest_attempt = conn.execute(
                """
                SELECT skill_id, exercise_id
                FROM resonant.practice_attempts
                WHERE learner_id = %s
                ORDER BY created_at DESC
                LIMIT 1
                """,
                (lid,),
            ).fetchone()

            # 3. Top 3 weak skills/letters (from skill_progress with lowest mastery or most incorrect)
            weak_skills = conn.execute(
                """
                SELECT skill_id, mastery, attempts, correct_count
                FROM resonant.skill_progress
                WHERE learner_id = %s AND attempts > 0
                ORDER BY mastery ASC, attempts DESC
                LIMIT 3
                """,
                (lid,),
            ).fetchall()

        total_att = stats["total_attempts"] if stats and stats["total_attempts"] else 0
        correct_att = stats["correct_attempts"] if stats and stats["correct_attempts"] else 0
        attempts_7d = stats["attempts_7d"] if stats and stats["attempts_7d"] else 0
        last_active = stats["last_active_at"] if stats else None

        accuracy_pct = round((correct_att / total_att * 100.0), 1) if total_att > 0 else 0.0

        current_stage = ""
        current_letter = ""
        if latest_attempt:
            current_stage = latest_attempt["exercise_id"] or ""
            current_letter = _format_skill_to_letter(latest_attempt["skill_id"] or "")

        top_weak_letters = [
            _format_skill_to_letter(ws["skill_id"])
            for ws in (weak_skills or [])
        ]

        # Status:
        # struggling: total_att >= 3 and accuracy_pct < 60.0
        # inactive: no attempts in last 7 days (or never active)
        # active: attempts in last 7 days and not struggling
        if total_att >= 3 and accuracy_pct < 60.0:
            status = "struggling"
        elif attempts_7d == 0:
            status = "inactive"
        else:
            status = "active"

        learners.append({
            "id": lid,
            "name": l_row["name"] or "",
            "batch": l_row["batch"],
            "preferred_language": l_row["preferred_language"] or "English",
            "last_active_at": last_active.isoformat() if last_active else None,
            "current_stage": current_stage,
            "current_letter": current_letter,
            "accuracy_pct": accuracy_pct,
            "attempts_7d": attempts_7d,
            "top_weak_letters": top_weak_letters,
            "status": status,
        })

    summary = {
        "total_learners": len(learners),
        "active_this_week": sum(1 for l in learners if l["attempts_7d"] > 0),
        "struggling": sum(1 for l in learners if l["status"] == "struggling"),
    }

    return {
        "summary": summary,
        "learners": learners,
    }


def get_teacher_learner_detail(teacher_id: str, learner_id: str) -> dict | None:
    """Return detailed progress and attempt history for a learner.

    Returns None if learner does not exist or does NOT belong to this teacher (enables 404).
    """
    with get_connection() as conn:
        l_row = conn.execute(
            """
            SELECT learner_id, name, batch, phone, email, preferred_language, created_at
            FROM resonant.learners
            WHERE learner_id = %s AND teacher_id = %s
            """,
            (learner_id, teacher_id),
        ).fetchone()

    if not l_row:
        return None

    now = datetime.now(timezone.utc)
    lid = str(l_row["learner_id"])

    with get_connection() as conn:
        stats = conn.execute(
            """
            SELECT
                COUNT(*) as total_attempts,
                COUNT(*) FILTER (WHERE outcome = 'correct') as correct_attempts,
                COUNT(*) FILTER (WHERE created_at >= %s - interval '7 days') as attempts_7d,
                MAX(created_at) as last_active_at
            FROM resonant.practice_attempts
            WHERE learner_id = %s
            """,
            (now, lid),
        ).fetchone()

        latest_attempt = conn.execute(
            """
            SELECT skill_id, exercise_id
            FROM resonant.practice_attempts
            WHERE learner_id = %s
            ORDER BY created_at DESC
            LIMIT 1
            """,
            (lid,),
        ).fetchone()

        weak_skills = conn.execute(
            """
            SELECT skill_id, language, mastery, attempts, correct_count,
                   next_review_at
            FROM resonant.skill_progress
            WHERE learner_id = %s AND attempts > 0
            ORDER BY mastery ASC, attempts DESC
            """,
            (lid,),
        ).fetchall()

        recent_attempts_rows = conn.execute(
            """
            SELECT submission_id, exercise_id, skill_id, exercise_type,
                   outcome, response_time_ms, hint_used, attempt_number, created_at
            FROM resonant.practice_attempts
            WHERE learner_id = %s
            ORDER BY created_at DESC
            LIMIT 50
            """,
            (lid,),
        ).fetchall()

    total_att = stats["total_attempts"] if stats and stats["total_attempts"] else 0
    correct_att = stats["correct_attempts"] if stats and stats["correct_attempts"] else 0
    attempts_7d = stats["attempts_7d"] if stats and stats["attempts_7d"] else 0
    last_active = stats["last_active_at"] if stats else None
    accuracy_pct = round((correct_att / total_att * 100.0), 1) if total_att > 0 else 0.0

    current_stage = ""
    current_letter = ""
    if latest_attempt:
        current_stage = latest_attempt["exercise_id"] or ""
        current_letter = _format_skill_to_letter(latest_attempt["skill_id"] or "")

    skill_progress = [
        {
            "skill_id": row["skill_id"],
            "language": row["language"],
            "attempts": int(row["attempts"]),
            "correct_count": int(row["correct_count"]),
            "accuracy_pct": round(
                int(row["correct_count"]) / int(row["attempts"]) * 100.0,
                1,
            ),
            "mastery_estimate": float(row["mastery"]),
            "mastery_method": "bayesian_knowledge_tracing",
            "next_review_at": (
                row["next_review_at"].isoformat()
                if row.get("next_review_at") is not None else None
            ),
            "review_due": (
                row.get("next_review_at") is not None
                and row["next_review_at"] <= now
            ),
        }
        for row in (weak_skills or [])
    ]
    top_weak_letters = [
        _format_skill_to_letter(row["skill_id"])
        for row in skill_progress[:5]
    ]

    if total_att >= 3 and accuracy_pct < 60.0:
        status = "struggling"
    elif attempts_7d == 0:
        status = "inactive"
    else:
        status = "active"

    recent_attempts = [
        {
            "submission_id": str(r["submission_id"]),
            "exercise_id": r["exercise_id"],
            "skill_id": r["skill_id"],
            "exercise_type": r["exercise_type"],
            "outcome": r["outcome"],
            "response_time_ms": r["response_time_ms"],
            "hint_used": r["hint_used"],
            "attempt_number": r["attempt_number"],
            "created_at": r["created_at"].isoformat() if r["created_at"] else None,
        }
        for r in recent_attempts_rows
    ]

    from assessment_service import get_teacher_assessment_report

    assessment_report = get_teacher_assessment_report(teacher_id, learner_id) or {
        "recent_assessments": [],
        "assessment_error_summary": [],
    }
    return {
        "id": lid,
        "name": l_row["name"] or "",
        "batch": l_row["batch"],
        "phone": l_row["phone"],
        "email": l_row["email"],
        "preferred_language": l_row["preferred_language"],
        "created_at": l_row["created_at"].isoformat() if l_row["created_at"] else None,
        "last_active_at": last_active.isoformat() if last_active else None,
        "current_stage": current_stage,
        "current_letter": current_letter,
        "accuracy_pct": accuracy_pct,
        "total_attempts": total_att,
        "attempts_7d": attempts_7d,
        "top_weak_letters": top_weak_letters,
        "skill_progress": skill_progress,
        "status": status,
        "recent_attempts": recent_attempts,
        **assessment_report,
    }


def create_password_reset_token(email: str) -> str | None:
    """Create a short-lived signed token (15 mins) for password reset.
    Returns token if email exists, None otherwise.
    Never logs email or token.
    """
    with get_connection() as conn:
        row = conn.execute(
            "SELECT teacher_id FROM resonant.teachers WHERE email = lower(%s)",
            (email.strip(),),
        ).fetchone()
    if not row:
        return None

    teacher_id = str(row["teacher_id"])
    if not _JWT_OK:
        raise RuntimeError("python-jose is not installed.")
    exp = datetime.now(timezone.utc) + timedelta(minutes=_RESET_TOKEN_EXPIRY_MINUTES)
    return _jwt.encode(
        {"sub": teacher_id, "purpose": "pwd_reset", "exp": exp},
        _get_jwt_secret(),
        algorithm=_ALGORITHM,
    )


def reset_password_with_token(token: str, new_password: str) -> bool:
    """Verify reset token and update teacher's password hash."""
    if not _JWT_OK:
        raise RuntimeError("python-jose is not installed.")
    try:
        payload = _jwt.decode(token, _get_jwt_secret(), algorithms=[_ALGORITHM])
        if payload.get("purpose") != "pwd_reset":
            return False
        teacher_id = payload.get("sub")
    except Exception:
        return False

    password_hash = _hash_password(new_password)
    with get_connection() as conn:
        res = conn.execute(
            """
            UPDATE resonant.teachers
            SET password_hash = %s
            WHERE teacher_id = %s
            RETURNING teacher_id
            """,
            (password_hash, teacher_id),
        ).fetchone()
    return res is not None


def delete_teacher_learner(teacher_id: str, learner_id: str) -> bool:
    """Deletes learner and cascades to attempts/progress.
    Only succeeds if the learner belongs to teacher_id.
    """
    with get_connection() as conn:
        # Check ownership
        owner = conn.execute(
            "SELECT learner_id FROM resonant.learners WHERE learner_id = %s AND teacher_id = %s",
            (learner_id, teacher_id),
        ).fetchone()
        if not owner:
            return False

        # ON DELETE CASCADE handles practice_attempts, quiz_results, skill_progress
        conn.execute(
            "DELETE FROM resonant.learners WHERE learner_id = %s",
            (learner_id,),
        )
        return True


def delete_teacher_account(teacher_id: str) -> bool:
    """Deletes the teacher account.
    Learners are kept unassigned (teacher_id set to NULL).
    """
    with get_connection() as conn:
        # Disassociate learners (set teacher_id = NULL)
        conn.execute(
            "UPDATE resonant.learners SET teacher_id = NULL WHERE teacher_id = %s",
            (teacher_id,),
        )
        # Delete teacher
        row = conn.execute(
            "DELETE FROM resonant.teachers WHERE teacher_id = %s RETURNING teacher_id",
            (teacher_id,),
        ).fetchone()
        return row is not None



