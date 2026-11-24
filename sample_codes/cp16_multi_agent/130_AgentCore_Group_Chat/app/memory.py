"""Explicit short-term event writes and reads, owned by the meeting chair."""
import asyncio
from datetime import datetime, timezone
import json
from botocore.exceptions import ClientError
from contracts import encoded, digest

ACTOR = "menu-team"


class Journal:
    def __init__(self, api, memory_id, run_id):
        self.api = api
        self.args = {"memoryId": memory_id, "actorId": ACTOR, "sessionId": run_id}

    async def append(self, utterance):
        response = await asyncio.to_thread(self.api.create_event, **self.args,
            eventTimestamp=datetime.now(timezone.utc), clientToken=digest({**self.args, **utterance}),
            payload=[{"conversational": {"role": "ASSISTANT", "content": {"text": encoded(utterance).decode()}}}])
        return response["event"]["eventId"]

    async def load(self, events):
        history = []
        for ref in events:
            for attempt in range(4):
                try:
                    result = await asyncio.to_thread(self.api.get_event, **self.args, eventId=ref["event_id"])
                    break
                except ClientError as exc:
                    if exc.response["Error"]["Code"] != "ResourceNotFoundException" or attempt == 3:
                        raise
                    await asyncio.sleep(0.5 * (attempt + 1))
            event = result["event"]
            if event["actorId"] != ACTOR or event["sessionId"] != self.args["sessionId"]:
                raise ValueError("Memory session mismatch")
            utterance = json.loads(event["payload"][0]["conversational"]["content"]["text"])
            if digest(utterance) != ref["utterance_sha256"]:
                raise ValueError("Memory utterance hash mismatch")
            history.append(utterance)
        return history
