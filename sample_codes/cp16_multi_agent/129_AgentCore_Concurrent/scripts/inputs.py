"""Validate all local Markdown before uploading a fresh run snapshot."""
from pathlib import Path
import uuid
from contracts import SPECIALISTS, digest

NAMES = ("common", *SPECIALISTS)
MAX_BYTES = 60000


def load_documents(input_dir):
    root = Path(input_dir).expanduser().resolve(strict=True)
    documents = {}
    for name in NAMES:
        path = (root / f"{name}.md").resolve(strict=True)
        if path.parent != root or not path.is_file():
            raise ValueError("Expected regular Markdown files inside input directory")
        data = path.read_bytes()
        if not 0 < len(data) <= MAX_BYTES:
            raise ValueError(f"{name}.md must contain 1..{MAX_BYTES} UTF-8 bytes")
        value = data.decode("utf-8-sig")
        if not value.strip():
            raise ValueError(f"{name}.md is empty")
        documents[name] = value
    return documents


def upload_documents(s3, bucket, input_dir):
    documents = load_documents(input_dir)
    run_id = str(uuid.uuid4())
    for name, value in documents.items():
        s3.put_object(Bucket=bucket, Key=f"runs/{run_id}/inputs/{name}.md",
                      Body=value.encode("utf-8"), ContentType="text/markdown; charset=utf-8", IfNoneMatch="*")
    return {"run_id": run_id, "input_hashes": {name: digest(value) for name, value in documents.items()}}
