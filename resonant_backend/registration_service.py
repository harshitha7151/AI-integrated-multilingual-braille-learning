"""Registration helpers: create a new learner with a hashed 6-digit code,
and restore an existing account by phone/email + code."""

import hashlib
import os
import secrets

from database import get_connection
from uuid import uuid4


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _generate_code() -> str:
    """Return a cryptographically random 6-digit string (zero-padded)."""
    return f"{secrets.randbelow(1_000_000):06d}"


def _hash_code(code: str) -> str:
    """SHA-256 hex digest of the 6-digit code (no salt needed; short-lived
    shared secret; not a user password).  Never log the raw code."""
    return hashlib.sha256(code.encode()).hexdigest()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def register_learner(name: str, phone: str | None, email: str | None,
                     batch: str | None, language: str, consent: bool,
                     teacher_id: str | None = None) -> dict:
    """Insert a new learner row and return learner_id + plaintext code.

    The plaintext code is returned exactly once and never stored.
    ``code_hash`` (SHA-256) is persisted instead.
    """
    learner_id = uuid4()
    code = _generate_code()
    code_hash = _hash_code(code)
    consent_at = "now()" if consent else None

    with get_connection() as conn:
        # Build query dynamically so NULL columns are truly NULL (not '').
        row = conn.execute(
            """
            INSERT INTO resonant.learners
                (learner_id, username, preferred_language,
                 name, phone, email, batch, consent_at, code_hash, teacher_id)
            VALUES (%s, %s, %s, %s, %s, %s, %s,
                    CASE WHEN %s THEN now() ELSE NULL END, %s, %s)
            RETURNING learner_id, username, preferred_language,
                      name, phone, email, batch, consent_at, created_at
            """,
            (
                learner_id,
                name,          # username = name for backward compat
                language,
                name,
                phone or None,
                email or None,
                batch or None,
                consent,
                code_hash,
                teacher_id or None,
            ),
        ).fetchone()
    result = dict(row)
    result["learner_code"] = code   # plaintext, returned once only
    return result


def restore_learner(phone_or_email: str, code: str) -> dict | None:
    """Look up learner by phone or email and verify the 6-digit code.

    Returns the learner dict (without the code) on success, None on mismatch.
    Does NOT log the phone/email or code.
    """
    code_hash = _hash_code(code)
    with get_connection() as conn:
        row = conn.execute(
            """
            SELECT learner_id, username, preferred_language,
                   name, phone, email, batch, consent_at, created_at,
                   code_hash
            FROM resonant.learners
            WHERE (phone = %s OR email = %s)
              AND code_hash = %s
            LIMIT 1
            """,
            (phone_or_email, phone_or_email, code_hash),
        ).fetchone()
    if row is None:
        return None
    result = dict(row)
    result.pop("code_hash", None)   # never expose the hash downstream
    return result


def update_learner_language(learner_id: str, code: str, language: str) -> dict | None:
    """Update a saved preference after verifying the learner restore code."""
    candidate_hash = _hash_code(code)
    with get_connection() as conn:
        row = conn.execute(
            "SELECT code_hash FROM resonant.learners WHERE learner_id = %s",
            (learner_id,),
        ).fetchone()
        if row is None or not row.get("code_hash") or not secrets.compare_digest(
            row["code_hash"], candidate_hash
        ):
            return None
        updated = conn.execute(
            """
            UPDATE resonant.learners
            SET preferred_language = %s
            WHERE learner_id = %s
            RETURNING learner_id, preferred_language
            """,
            (language, learner_id),
        ).fetchone()
    return dict(updated) if updated else None


def verify_learner_code(learner_id: str, code: str) -> bool:
    """Verify the locally held learner restore code without exposing its hash."""
    candidate_hash = _hash_code(code)
    with get_connection() as conn:
        row = conn.execute(
            "SELECT code_hash FROM resonant.learners WHERE learner_id = %s",
            (learner_id,),
        ).fetchone()
    return bool(
        row
        and row.get("code_hash")
        and secrets.compare_digest(row["code_hash"], candidate_hash)
    )

