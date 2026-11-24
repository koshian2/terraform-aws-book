import hashlib
import json
import uuid


def encoded(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()


def digest(value):
    return hashlib.sha256(encoded(value)).hexdigest()


def case_id(value):
    if not isinstance(value, str) or str(uuid.UUID(value)) != value:
        raise ValueError("Expected canonical case UUID")
    return value


def request(value, actions):
    if not isinstance(value, dict) or value.get("action") not in actions:
        raise ValueError("Unsupported action")
    fields = {"action", "case_id"}
    if value["action"] == "create": fields |= {"mode", "notes"}
    if value["action"] == "talk": fields |= {"message"}
    if value["action"] == "advance": fields |= {"expected_revision"}
    if value["action"] == "review": fields |= {"revision", "packet", "dialogue"}
    if value["action"] == "receive": fields |= {"packet", "transfer_id"}
    if set(value) != fields: raise ValueError("Unexpected fields")
    case_id(value["case_id"])
    if value["action"] == "create":
        if value["mode"] not in ("minimal", "complete"): raise ValueError("Invalid mode")
        bounded_text(value["notes"], 12000)
    if value["action"] == "talk": bounded_text(value["message"], 2000)
    if value["action"] == "advance":
        if type(value['expected_revision']) is not int or not 0 <= value['expected_revision'] <= 3:
            raise ValueError('Invalid expected revision')
    if value["action"] == "review":
        bounded_text(value['packet'], 12000)
        dialogue = value['dialogue']
        if type(value['revision']) is not int or not 0 <= value['revision'] <= 2:
            raise ValueError('Invalid review revision')
        if not isinstance(dialogue, list) or len(dialogue) != value['revision'] * 2:
            raise ValueError('Expected complete question/answer pairs')
        for i, event in enumerate(dialogue):
            if set(event) != {'speaker', 'text'} or event['speaker'] != ('successor' if i % 2 == 0 else 'predecessor'):
                raise ValueError('Invalid dialogue order')
            bounded_text(event['text'], 4000)
    if value["action"] == "receive":
        bounded_text(value["packet"], 12000)
        if value["transfer_id"] != transfer_id(value["case_id"], value["packet"]):
            raise ValueError("Invalid transfer hash")
    return value


def bounded_text(value, limit):
    if not isinstance(value, str) or not value.strip() or len(value) > limit:
        raise ValueError("Invalid text length")


def transfer_id(cid, packet):
    return digest({"case_id": cid, "from": "predecessor", "to": "successor", "packet": packet})


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
    if len(data) != 1: raise ValueError("Expected one result")
    return data[0]
