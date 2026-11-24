import hashlib
import json
import re
import uuid

PARTICIPANTS = ("development", "procurement", "operations")
SCHEDULE = (*PARTICIPANTS, *PARTICIPANTS, "summary")


def encoded(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def digest(value):
    return hashlib.sha256(encoded(value)).hexdigest()


def validate_hashes(value, names):
    if not isinstance(value, dict) or set(value) != set(names) or any(
        not isinstance(h, str) or not re.fullmatch("[0-9a-f]{64}", h) for h in value.values()):
        raise ValueError("Invalid input hashes")


def validate_inputs(value):
    if set(value) != {"run_id", "input_hashes"} or str(uuid.UUID(value["run_id"])) != value["run_id"]:
        raise ValueError("Expected canonical run UUID and input hashes")
    validate_hashes(value["input_hashes"], ("common", *PARTICIPANTS))
    return value["run_id"]


def output_key(run_id, role, turn):
    return f"runs/{run_id}/{role}/{turn:02d}-output.json"


def validate_history(history, turn):
    if not isinstance(history, list) or len(history) != turn-1:
        raise ValueError("Missing meeting history")
    for i, item in enumerate(history, 1):
        if set(item) != {"turn", "role", "text"} or item["turn"] != i or item["role"] != SCHEDULE[i-1]:
            raise ValueError("Unexpected meeting speaker/order")
        if not isinstance(item["text"], str) or not 0 < len(item["text"]) <= 8000:
            raise ValueError("Invalid utterance")


def validate_request(value, role):
    if set(value) != {"run_id", "role", "turn", "history", "input_hashes"}:
        raise ValueError("Unexpected request fields")
    run_id, turn = value["run_id"], value["turn"]
    if str(uuid.UUID(run_id)) != run_id or type(turn) is not int or not 1 <= turn <= len(SCHEDULE):
        raise ValueError("Invalid run or turn")
    if value["role"] != role or SCHEDULE[turn-1] != role:
        raise ValueError("Unexpected speaker")
    validate_hashes(value["input_hashes"], ("common",) if role == "summary" else ("common", role))
    validate_history(value["history"], turn)
    return run_id


def request_rpc(value, request_id):
    return {"jsonrpc": "2.0", "id": request_id, "method": "message/send", "params": {
        "message": {"role": "user", "messageId": str(uuid.uuid4()), "parts": [{"kind": "text", "text": encoded(value).decode()}]},
        "configuration": {"blocking": True}}}


def extract_rpc(response, request_id):
    if response.get("jsonrpc") != "2.0" or response.get("id") != request_id or "error" in response:
        raise RuntimeError("A2A error: " + str(response.get("error")))
    task = response.get("result", {})
    if task.get("status", {}).get("state") != "completed":
        raise RuntimeError("A2A incomplete: " + str(task.get("status")))
    data = [p["data"] for a in task.get("artifacts", []) for p in a.get("parts", []) if p.get("kind") == "data"]
    if len(data) != 1:
        raise ValueError("Expected one utterance")
    return data[0]
