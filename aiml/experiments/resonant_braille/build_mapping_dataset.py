"""Export the deterministic multilingual mapping registry as authored JSON."""

from __future__ import annotations

import json
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
REPOSITORY = ROOT.parent
sys.path.insert(0, str(REPOSITORY / "resonant_backend"))

from braille_mapping_registry import REGISTRY_VERSION, mapping_records


def build(output: Path | None = None) -> Path:
    destination = output or (
        ROOT / "data" / "authored" / "resonant_braille_mappings_v1.json"
    )
    records = mapping_records()
    payload = {
        "dataset_id": REGISTRY_VERSION,
        "data_origin": "deterministic_repository_engines",
        "is_learner_data": False,
        "languages": ["English", "Hindi", "Kannada"],
        "coverage_claim": "verified project subset only",
        "records": records,
    }
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return destination


if __name__ == "__main__":
    print(build())

