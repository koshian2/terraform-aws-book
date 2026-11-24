"""One role per Runtime; A2A server using the official SDK adapter."""
import asyncio
import json
import os
from pathlib import Path

import boto3
from botocore.config import Config
from a2a.server.agent_execution import AgentExecutor
from a2a.server.tasks import TaskUpdater
from a2a.types import AgentCapabilities, AgentCard, AgentSkill, DataPart, Part, TaskState, TextPart
from a2a.utils import new_task, new_agent_text_message
from bedrock_agentcore.runtime import serve_a2a

from contracts import digest, validate_stage_input

PROMPTS = json.loads(Path(__file__).with_name("prompts.json").read_text(encoding="utf-8"))


class Writer(AgentExecutor):
    def __init__(self, stage, model, model_id):
        self.stage, self.model, self.model_id = stage, model, model_id

    async def execute(self, context, event_queue):
        task = context.current_task or new_task(context.message)
        if not context.current_task:
            await event_queue.enqueue_event(task)
        updater = TaskUpdater(event_queue, task.id, task.context_id)
        await updater.start_work()
        try:
            value = json.loads(context.get_user_input())
            validate_stage_input(value, self.stage)
            response = await asyncio.to_thread(self.model.converse, modelId=self.model_id,
                system=[{"text": PROMPTS["common"] + "\n" + PROMPTS[self.stage]}],
                messages=[{"role": "user", "content": [{"text": json.dumps(value, ensure_ascii=False)}]}],
                inferenceConfig={"maxTokens": 2500})
            if response["stopReason"] != "end_turn":
                raise ValueError("Model did not complete the draft: " + response["stopReason"])
            text = "\n".join(b["text"] for b in response["output"]["message"]["content"] if "text" in b)
            if not text.strip():
                raise ValueError("Empty draft")
            result = {"stage": self.stage, "input_sha256": digest(value), "text": text,
                      "model_id": self.model_id, "usage": response.get("usage", {})}
            await updater.add_artifact([Part(root=DataPart(data=result))], name=self.stage)
            await updater.complete()
        except Exception as exc:
            print(json.dumps({"event": "stage_failed", "stage": self.stage, "error_type": type(exc).__name__}), flush=True)
            await updater.update_status(TaskState.failed,
                new_agent_text_message(f"{self.stage} failed: {type(exc).__name__}: {exc}"), final=True)

    async def cancel(self, context, event_queue):
        raise NotImplementedError("This bounded synchronous sample does not support cancellation")


def card(stage):
    return AgentCard(name=f"sequential-{stage}", description=f"Product publishing draft: {stage}",
        url="http://localhost:9000/", version="1.0.0", capabilities=AgentCapabilities(streaming=False),
        default_input_modes=["text"], default_output_modes=["application/json"],
        skills=[AgentSkill(id=stage, name=stage, description=PROMPTS[stage], tags=["writing"])])


if __name__ == "__main__":
    stage = os.environ["STAGE"]
    model = boto3.client("bedrock-runtime", region_name=os.environ["SAMPLE_REGION"],
                          config=Config(read_timeout=120, retries={"total_max_attempts": 1}))
    serve_a2a(Writer(stage, model, os.environ["MODEL_ID"]), card(stage), host="0.0.0.0", port=9000)
