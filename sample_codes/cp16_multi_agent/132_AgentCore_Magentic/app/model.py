from strands import Agent
from strands.models import BedrockModel
from botocore.config import Config
from contracts import encoded


def build_model(session, model_id):
    return BedrockModel(model_id=model_id, boto_session=session, streaming=False, max_tokens=2200,
                        boto_client_config=Config(read_timeout=120, retries={'total_max_attempts': 1}))


async def generate(model, prompt, value):
    agent = Agent(model=model, system_prompt=prompt, callback_handler=None, retry_strategy=None)
    response = await agent.invoke_async(encoded(value).decode(), limits={'turns': 1})
    if response.stop_reason != 'end_turn': raise RuntimeError('Incomplete model response: ' + response.stop_reason)
    text = str(response)
    if not text.strip() or len(text) > 15000: raise ValueError('Invalid model output size')
    return text
