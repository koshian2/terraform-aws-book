import hashlib
import json
import uuid
import re

SPECIALISTS = ("cost", "commute", "environment")
ROLES = (*SPECIALISTS, "summary")


def encoded(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def digest(value):
    return hashlib.sha256(encoded(value)).hexdigest()


def validate_inputs(value):
    if set(value) != {"run_id", "input_hashes"} or str(uuid.UUID(value["run_id"])) != value["run_id"]:
        raise ValueError("Expected run UUID and input hashes")
    validate_hashes(value["input_hashes"], {"common", *SPECIALISTS})
    return value["run_id"]


def validate_hashes(hashes, names):
    if not isinstance(hashes, dict) or set(hashes) != names or any(
            not isinstance(h, str) or not re.fullmatch(r"[0-9a-f]{64}", h) for h in hashes.values()):
        raise ValueError("Invalid Markdown input hashes")


def validate_request(value, role):
    run_id = value.get("run_id")
    if str(uuid.UUID(run_id)) != run_id or role not in ROLES or value.get("role") != role:
        raise ValueError("Invalid run ID or role")
    if set(value) != ({"run_id", "role", "input_hashes", "reports"} if role == "summary" else {"run_id", "role", "input_hashes"}):
        raise ValueError("Specialists cannot receive other evaluations or arbitrary prompts")
    validate_hashes(value["input_hashes"], {"common"} if role == "summary" else {"common", role})
    if role == "summary":
        reports = value["reports"]
        if not isinstance(reports, list) or len(reports) != 3 or {r["role"] for r in reports} != set(SPECIALISTS):
            raise ValueError("All three independent reports are required")
        for r in reports:
            if r["run_id"] != run_id or r["key"] != f"runs/{run_id}/{r['role']}/output.json":
                raise ValueError("Unexpected report location")
    return run_id


def request_rpc(value, request_id):
    return {"jsonrpc": "2.0", "id": request_id, "method": "message/send", "params": {
        "message": {"role": "user", "messageId": str(uuid.uuid4()), "parts": [{"kind": "text", "text": encoded(value).decode()}]},
        "configuration": {"blocking": True}}}


def extract_rpc(response, request_id):
    if response.get("jsonrpc") != "2.0" or response.get("id") != request_id or "error" in response:
        raise RuntimeError("A2A response error: " + str(response.get("error")))
    task = response.get("result", {})
    if task.get("status", {}).get("state") != "completed":
        raise RuntimeError("A2A task did not complete: " + str(task.get("status")))
    data = [p["data"] for a in task.get("artifacts", []) for p in a.get("parts", []) if p.get("kind") == "data"]
    if len(data) != 1:
        raise ValueError("Expected one report reference")
    return data[0]
