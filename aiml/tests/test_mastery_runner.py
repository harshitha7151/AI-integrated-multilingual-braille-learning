import sys
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
from uuid import uuid4

import pandas as pd
import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "experiments" / "mastery_prediction"))

from export_authorized_events import load_authorization, pseudonymize_learner
from run_experiment import _qualification, run


def test_mastery_runner_refuses_personal_columns_before_training(tmp_path):
    source = tmp_path / "events.csv"
    pd.DataFrame([{"phone": "5550100"}]).to_csv(source, index=False)
    with pytest.raises(ValueError, match="forbidden personal"):
        run(source, "2026-11-01T00:00:00Z")


def test_mastery_runner_refuses_insufficient_event_rows(tmp_path):
    source = tmp_path / "events.csv"
    frame = pd.DataFrame(
        [
            {"submission_id": f"s{i}", "learner_id": f"p{i % 3}", "skill_id": "a", "language": "English", "outcome": "correct" if i % 2 else "incorrect", "response_time_ms": 500 + i, "hint_used": False, "created_at": f"2026-11-{i + 1:02d}T00:00:00Z"}
            for i in range(1, 8)
        ]
    )
    frame.to_csv(source, index=False)
    with pytest.raises(ValueError):
        run(source, "2026-11-05T00:00:00Z", minimum_rows=10)


def test_authorization_manifest_and_pseudonyms_are_explicit_and_stable(tmp_path):
    learner_id = str(uuid4())
    manifest = tmp_path / "authorization.json"
    manifest.write_text(
        json.dumps(
            {
                "authorization_id": "review-2026-11",
                "approved_at": "2026-11-01T00:00:00Z",
                "expires_at": "2027-01-01T00:00:00Z",
                "purpose": "resonant_next_attempt_research",
                "consent_basis": "documented test authorization",
                "data_minimization_reviewed": True,
                "learner_ids": [learner_id],
            }
        ),
        encoding="utf-8",
    )
    loaded = load_authorization(
        manifest,
        now=datetime(2026, 11, 22, tzinfo=timezone.utc),
    )
    assert loaded["learner_ids"] == [learner_id]
    first = pseudonymize_learner(learner_id, "x" * 32)
    second = pseudonymize_learner(learner_id, "x" * 32)
    assert first == second
    assert learner_id not in first


def test_qualification_requires_automated_gates_and_human_review():
    train = pd.DataFrame(
        {
            "learner_id": [f"train-{index}" for index in range(20)],
            "language": ["English"] * 20,
            "target_incorrect": [index % 2 for index in range(20)],
        }
    )
    test = pd.DataFrame(
        {
            "learner_id": [f"test-{index}" for index in range(10)],
            "language": ["English"] * 10,
            "target_incorrect": [index % 2 for index in range(10)],
        }
    )
    metrics = {"roc_auc": 0.75, "brier_score": 0.19}
    unreviewed = _qualification(
        metrics,
        train=train,
        test=test,
        minimum_train_rows=20,
        minimum_test_rows=10,
        minimum_train_learners=20,
        minimum_test_learners=10,
        minimum_roc_auc=0.6,
        maximum_brier=0.25,
        minimum_language_test_rows=10,
        minimum_language_test_learners=10,
        approved_by=None,
    )
    reviewed = _qualification(
        metrics,
        train=train,
        test=test,
        minimum_train_rows=20,
        minimum_test_rows=10,
        minimum_train_learners=20,
        minimum_test_learners=10,
        minimum_roc_auc=0.6,
        maximum_brier=0.25,
        minimum_language_test_rows=10,
        minimum_language_test_learners=10,
        approved_by="independent-review-42",
    )
    assert unreviewed["automated_gates_passed"] is True
    assert unreviewed["passed"] is False
    assert reviewed["passed"] is True


def test_mastery_runner_rejects_provenance_hash_mismatch(tmp_path):
    source = tmp_path / "events.csv"
    pd.DataFrame(
        [
            {
                "submission_id": "s1",
                "learner_id": "pseudo-1",
                "skill_id": "a",
                "language": "English",
                "outcome": "incorrect",
                "response_time_ms": 500,
                "hint_used": False,
                "created_at": "2026-11-01T00:00:00Z",
            }
        ]
    ).to_csv(source, index=False)
    provenance = tmp_path / "events.provenance.json"
    provenance.write_text(
        json.dumps(
            {
                "authorization_id": "review-1",
                "data_origin": "consented_resonant_events",
                "research_eligible": True,
                "pseudonymization_method": "HMAC-SHA256",
                "export_as_of": "2026-11-22T00:00:00Z",
                "source_sha256": hashlib.sha256(b"other").hexdigest(),
            }
        ),
        encoding="utf-8",
    )
    with pytest.raises(ValueError, match="source_sha256"):
        run(
            source,
            "2026-11-05T00:00:00Z",
            provenance_path=provenance,
        )
