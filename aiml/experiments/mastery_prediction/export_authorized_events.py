"""Export a minimal, authorized, pseudonymized Resonant training snapshot.

This command is intentionally opt-in. It requires an external authorization
manifest, an approval environment value matching that manifest, and a secret
HMAC key. It never exports names, contact details, learner codes, answers,
tutor text, audio, or teacher identifiers.
"""

from __future__ import annotations

import argparse
import csv
from datetime import datetime, timezone
import hashlib
import hmac
import json
import os
from pathlib import Path
from uuid import UUID


ROOT = Path(__file__).resolve().parents[2]
PROCESSED_ROOT = (ROOT / "data" / "processed").resolve()


def load_authorization(path: Path, *, now: datetime | None = None) -> dict:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("authorization manifest must be a JSON object")
    required = {
        "authorization_id",
        "approved_at",
        "expires_at",
        "purpose",
        "consent_basis",
        "data_minimization_reviewed",
        "learner_ids",
    }
    missing = sorted(required - set(payload))
    if missing:
        raise ValueError("authorization manifest is missing: " + ", ".join(missing))
    if payload["data_minimization_reviewed"] is not True:
        raise ValueError("data minimization review is required")
    if payload["purpose"] != "resonant_next_attempt_research":
        raise ValueError("authorization purpose is not valid for this export")
    if not str(payload["consent_basis"]).strip():
        raise ValueError("consent_basis cannot be blank")
    current = now or datetime.now(timezone.utc)
    expires = datetime.fromisoformat(
        str(payload["expires_at"]).replace("Z", "+00:00")
    )
    if expires.tzinfo is None:
        expires = expires.replace(tzinfo=timezone.utc)
    if expires <= current:
        raise ValueError("authorization manifest has expired")
    learners = payload["learner_ids"]
    if not isinstance(learners, list) or not learners:
        raise ValueError("authorization manifest requires learner_ids")
    payload["learner_ids"] = [str(UUID(str(value))) for value in learners]
    if len(set(payload["learner_ids"])) != len(payload["learner_ids"]):
        raise ValueError("authorization manifest contains duplicate learner_ids")
    return payload


def pseudonymize_learner(learner_id: str, secret: str) -> str:
    if len(secret.encode("utf-8")) < 32:
        raise ValueError("RESONANT_RESEARCH_PSEUDONYM_KEY must be at least 32 bytes")
    digest = hmac.new(
        secret.encode("utf-8"),
        str(UUID(learner_id)).encode("ascii"),
        hashlib.sha256,
    ).hexdigest()
    return f"resonant-{digest[:32]}"


def _validated_output(path: Path) -> Path:
    resolved = path.resolve()
    if not resolved.is_relative_to(PROCESSED_ROOT):
        raise ValueError("output must stay under aiml/data/processed")
    return resolved


def export_events(
    *,
    authorization_path: Path,
    output_path: Path,
    as_of: datetime,
) -> tuple[Path, Path]:
    authorization = load_authorization(authorization_path)
    approval = os.getenv("RESONANT_RESEARCH_EXPORT_APPROVAL", "")
    if approval != authorization["authorization_id"]:
        raise RuntimeError("research export approval does not match authorization_id")
    pseudonym_key = os.getenv("RESONANT_RESEARCH_PSEUDONYM_KEY", "")
    if len(pseudonym_key.encode("utf-8")) < 32:
        raise RuntimeError("RESONANT_RESEARCH_PSEUDONYM_KEY is missing or too short")
    database_url = os.getenv("RESONANT_DATABASE_URL")
    if not database_url:
        raise RuntimeError("RESONANT_DATABASE_URL is not configured")
    output = _validated_output(output_path)

    try:
        import psycopg
        from psycopg.rows import dict_row
    except ImportError as error:
        raise RuntimeError("psycopg is required for an authorized export") from error

    query = """
        SELECT submission_id::text AS submission_id, learner_id::text AS learner_id,
               skill_id, language, outcome, response_time_ms, hint_used,
               created_at, exercise_type AS question_type, difficulty,
               input_status, TRUE AS counts_for_learning,
               NULL::text AS error_category, intervention_type,
               NULL::text AS assessment_type
        FROM resonant.practice_attempts
        WHERE learner_id = ANY(%s::uuid[]) AND created_at < %s
        UNION ALL
        SELECT ('assessment-' || a.attempt_id::text) AS submission_id,
               a.learner_id::text AS learner_id, q.skill_id, s.language,
               CASE WHEN a.correct THEN 'correct' ELSE 'incorrect' END AS outcome,
               a.response_time_ms, a.hint_used, a.created_at,
               q.exercise_type AS question_type, q.difficulty,
               a.input_status, a.counts_for_learning, a.error_category,
               a.intervention_type, s.assessment_type
        FROM resonant.assessment_attempts a
        JOIN resonant.assessment_questions q
          ON q.assessment_id = a.assessment_id AND q.question_id = a.question_id
        JOIN resonant.assessment_sessions s ON s.assessment_id = a.assessment_id
        WHERE a.learner_id = ANY(%s::uuid[]) AND a.created_at < %s
        ORDER BY created_at, submission_id
    """
    learner_ids = authorization["learner_ids"]
    with psycopg.connect(database_url, row_factory=dict_row) as connection:
        rows = connection.execute(
            query,
            (learner_ids, as_of, learner_ids, as_of),
        ).fetchall()
    if not rows:
        raise ValueError("authorized export contains no eligible events")

    fieldnames = [
        "submission_id",
        "learner_id",
        "skill_id",
        "language",
        "outcome",
        "response_time_ms",
        "hint_used",
        "created_at",
        "question_type",
        "difficulty",
        "input_status",
        "counts_for_learning",
        "error_category",
        "intervention_type",
        "assessment_type",
        "data_origin",
        "research_authorization_id",
    ]
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fieldnames)
        writer.writeheader()
        for raw in rows:
            row = dict(raw)
            row["learner_id"] = pseudonymize_learner(
                row["learner_id"],
                pseudonym_key,
            )
            row["created_at"] = row["created_at"].astimezone(
                timezone.utc
            ).isoformat()
            row["data_origin"] = "consented_resonant_events"
            row["research_authorization_id"] = authorization["authorization_id"]
            writer.writerow({name: row.get(name) for name in fieldnames})

    data_hash = hashlib.sha256(output.read_bytes()).hexdigest()
    provenance_path = output.with_suffix(output.suffix + ".provenance.json")
    provenance_path.write_text(
        json.dumps(
            {
                "authorization_id": authorization["authorization_id"],
                "data_origin": "consented_resonant_events",
                "research_eligible": True,
                "pseudonymization_method": "HMAC-SHA256 truncated to 128 bits",
                "export_as_of": as_of.astimezone(timezone.utc).isoformat(),
                "source_sha256": data_hash,
                "rows": len(rows),
                "learner_count": len(
                    {
                        pseudonymize_learner(value, pseudonym_key)
                        for value in learner_ids
                    }
                ),
                "purpose": authorization["purpose"],
                "consent_basis": authorization["consent_basis"],
                "excluded_personal_fields": sorted(
                    {
                        "name",
                        "phone",
                        "email",
                        "batch",
                        "teacher_id",
                        "learner_code",
                        "raw answers",
                        "tutor text/audio",
                    }
                ),
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    return output, provenance_path


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--authorization", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--as-of", required=True)
    arguments = parser.parse_args()
    cutoff = datetime.fromisoformat(arguments.as_of.replace("Z", "+00:00"))
    if cutoff.tzinfo is None:
        raise ValueError("--as-of must include a timezone")
    csv_path, manifest_path = export_events(
        authorization_path=arguments.authorization,
        output_path=arguments.output,
        as_of=cutoff.astimezone(timezone.utc),
    )
    print(
        json.dumps(
            {
                "csv": str(csv_path),
                "provenance": str(manifest_path),
            },
            indent=2,
        )
    )
