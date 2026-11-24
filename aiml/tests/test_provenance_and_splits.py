import json

import pytest

from data.provenance import DatasetManifest, sha256_file
from evaluation.splits import learner_group_split


def test_manifest_requires_hash_for_downloaded_data(tmp_path):
    manifest = DatasetManifest(
        name="tiny-fixture",
        source_url="https://example.org/source",
        revision="v1",
        license="CC0-1.0",
        acquired_at="2026-11-20T10:00:00+00:00",
    )
    path = tmp_path / "manifest.json"
    manifest.write(path)
    assert json.loads(path.read_text(encoding="utf-8"))["downloaded"] is False
    with pytest.raises(ValueError, match="SHA-256"):
        DatasetManifest(**{**manifest.__dict__, "downloaded": True}).validate()


def test_sha256_file_streaming_helper(tmp_path):
    target = tmp_path / "data.bin"
    target.write_bytes(b"resonant")
    assert sha256_file(target) == "e7e119c68e7218b473f4427872683797bdc1bdf05e45804dc4eefe05d86588f2"


def test_learner_group_split_is_reproducible_and_disjoint():
    groups = ["a"] * 4 + ["b"] * 4 + ["c"] * 4 + ["d"] * 4
    train_a, test_a = learner_group_split(groups, test_size=0.25, seed=17)
    train_b, test_b = learner_group_split(groups, test_size=0.25, seed=17)
    assert train_a.tolist() == train_b.tolist()
    assert test_a.tolist() == test_b.tolist()
    assert set(groups[i] for i in train_a).isdisjoint(groups[i] for i in test_a)


def test_learner_group_split_rejects_single_group():
    with pytest.raises(ValueError, match="two unique"):
        learner_group_split(["same"] * 10)
