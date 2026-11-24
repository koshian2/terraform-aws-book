"""Memoryの短期イベントを使い、呼び出しごとに会話を復元する。"""
from datetime import datetime, timezone
import json
import uuid


class Memory:
    def __init__(self, api, memory_id, actor_id):
        self.api = api
        self.scope = {"memoryId": memory_id, "actorId": actor_id}

    def events(self, session_id):
        events = []
        size = 0
        for page in self.api.get_paginator("list_events").paginate(
                **self.scope, sessionId=session_id, includePayloads=True):
            for event in page["events"]:
                size += len(json.dumps(event.get("payload", []), ensure_ascii=False))
                if size > 60000:
                    raise ValueError("会話が長くなりました。新しい相談を開始してください。")
                events.append(event)
        return sorted(events, key=lambda e: (e["eventTimestamp"], e["eventId"]))

    def messages(self, events):
        messages = []
        for event in events:
            for block in event.get("payload", []):
                item = block.get("conversational", {})
                role, text = item.get("role", "").lower(), item.get("content", {}).get("text")
                if role not in ("user", "assistant") or not isinstance(text, str):
                    raise ValueError("未対応の会話イベントです。")
                if messages and messages[-1]["role"] == role:
                    messages[-1]["content"][0]["text"] += "\n\n" + text
                else:
                    messages.append({"role": role, "content": [{"text": text}]})
        return messages

    def save(self, session_id, question, answer, sources):
        # 料理IDと出典も回答と一緒に残し、次の呼び出しで特定できるようにする。
        text = answer
        if sources:
            text += "\n参照したレシピ: " + json.dumps(
                [{"recipe_id": s["recipe_id"], "name": s["name"], "uri": s["uri"]} for s in sources],
                ensure_ascii=False)
        result = self.api.create_event(**self.scope, sessionId=session_id,
            clientToken=str(uuid.uuid4()), eventTimestamp=datetime.now(timezone.utc),
            payload=[{"conversational": {"role": role, "content": {"text": value}}}
                     for role, value in [("USER", question), ("ASSISTANT", text)]])
        return result["event"]["eventId"]

    def sessions(self, next_token=None):
        args = {**self.scope, "maxResults": 10, "filter": {"eventFilter": "HAS_EVENTS"}}
        if next_token:
            args["nextToken"] = next_token
        page = self.api.list_sessions(**args)
        items = []
        for summary in page.get("sessionSummaries", []):
            # ListSessions自体はタイトルを返さない。最初の質問を表示用に使う。
            try:
                events = self.events(summary["sessionId"])
                messages = self.messages(events)
                preview = next((m["content"][0]["text"][:100] for m in messages if m["role"] == "user"), "")
            except ValueError:
                preview = "長い会話（履歴の取得上限を超えています）"
            items.append({"session_id": summary["sessionId"],
                          "created_at": summary["createdAt"].isoformat(), "first_question": preview})
        return {"sessions": items, "next_token": page.get("nextToken")}
