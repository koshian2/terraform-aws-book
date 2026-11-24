"""Application contracts carried inside A2A messages and artifacts."""
import hashlib
import json

STAGES = ("brief", "copy", "social")


def encoded(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def digest(value):
    return hashlib.sha256(encoded(value)).hexdigest()


def validate_product(product):
    if not isinstance(product, dict) or len(encoded(product)) > 12000:
        raise ValueError("product must be an object of at most 12000 UTF-8 bytes")
    if not isinstance(product.get("name"), str) or not product["name"].strip():
        raise ValueError("product.name is required")
    for key in ("facts", "constraints"):
        values = product.get(key)
        if not isinstance(values, list) or not values or not all(isinstance(v, str) and v.strip() for v in values):
            raise ValueError(f"product.{key} must contain non-empty strings")


def validate_stage_input(value, stage):
    if value.get("stage") != stage:
        raise ValueError("Wrong stage")
    validate_product(value.get("product"))
    previous = value.get("previous")
    index = STAGES.index(stage)
    if index == 0:
        if previous is not None:
            raise ValueError("First stage must not have a predecessor")
    elif not isinstance(previous, dict) or previous.get("stage") != STAGES[index-1] or not previous.get("text"):
        raise ValueError("Immediate predecessor is required")
    if len(encoded(value)) > 60000:
        raise ValueError("Stage input too large")


def validate_output(value, stage, expected_hash):
    if not isinstance(value, dict) or value.get("stage") != stage or value.get("input_sha256") != expected_hash:
        raise ValueError("Stage output provenance mismatch")
    if not isinstance(value.get("text"), str) or not value["text"].strip() or len(value["text"]) > 16000:
        raise ValueError("Stage returned missing or oversized text")
