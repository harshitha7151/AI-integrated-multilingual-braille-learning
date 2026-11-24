"""Download the official corrected ASSISTments Skill Builder CSV."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src"))

from data.assistments_2009 import (  # noqa: E402
    DOWNLOAD_FILE_ID,
    EXPECTED_SHA256,
    sha256_file,
)


DOWNLOAD_URL = (
    "https://drive.usercontent.google.com/download"
    f"?id={DOWNLOAD_FILE_ID}&export=download&confirm=t"
)
DEFAULT_OUTPUT = (
    ROOT
    / "data"
    / "raw"
    / "assistments_2009_2010"
    / "skill_builder_data_corrected_collapsed.csv"
)


def download(output: Path, *, acknowledge_use_conditions: bool) -> Path:
    if not acknowledge_use_conditions:
        raise ValueError(
            "Review the official dataset page and responsible-use terms, then "
            "rerun with --acknowledge-use-conditions."
        )
    output = Path(output)
    if output.is_file() and sha256_file(output) == EXPECTED_SHA256:
        return output
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(output.suffix + ".download")
    request = Request(DOWNLOAD_URL, headers={"User-Agent": "Resonant-Research/1.0"})
    with urlopen(request, timeout=120) as response, temporary.open("wb") as handle:
        while chunk := response.read(1024 * 1024):
            handle.write(chunk)
    actual_hash = sha256_file(temporary)
    if actual_hash != EXPECTED_SHA256:
        temporary.unlink(missing_ok=True)
        raise ValueError(
            "downloaded file did not match the verified corrected release: "
            f"expected={EXPECTED_SHA256}, actual={actual_hash}"
        )
    temporary.replace(output)
    return output


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--acknowledge-use-conditions", action="store_true")
    arguments = parser.parse_args()
    saved = download(
        arguments.output,
        acknowledge_use_conditions=arguments.acknowledge_use_conditions,
    )
    print(f"Verified dataset: {saved}")
    print(f"SHA-256: {sha256_file(saved)}")
