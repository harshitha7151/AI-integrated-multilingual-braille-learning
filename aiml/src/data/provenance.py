"""Small source-manifest contract for reproducible data acquisition."""

from dataclasses import asdict, dataclass
from datetime import datetime
import hashlib
import json
from pathlib import Path


@dataclass(frozen=True)
class DatasetManifest:
    name: str
    source_url: str
    revision: str
    license: str
    acquired_at: str
    downloaded: bool = False
    sha256: str | None = None
    notes: str = ""

    def validate(self) -> None:
        for field in ("name", "source_url", "revision", "license", "acquired_at"):
            if not getattr(self, field).strip():
                raise ValueError(f"manifest field {field} cannot be blank")
        parsed = datetime.fromisoformat(self.acquired_at.replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            raise ValueError("acquired_at must include a timezone")
        if self.downloaded:
            if not self.sha256 or len(self.sha256) != 64:
                raise ValueError("downloaded data requires a 64-character SHA-256")
            try:
                int(self.sha256, 16)
            except ValueError as error:
                raise ValueError("sha256 must be hexadecimal") from error
        elif self.sha256 is not None:
            raise ValueError("sha256 must be absent when downloaded is false")

    def write(self, path: str | Path) -> None:
        self.validate()
        destination = Path(path)
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(json.dumps(asdict(self), indent=2) + "\n", encoding="utf-8")


def sha256_file(path: str | Path) -> str:
    """Hash a file in bounded memory without loading it all at once."""
    digest = hashlib.sha256()
    with Path(path).open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()
