"""AWS上の処理を呼び出すローカルHTTP MCPサーバー。"""
import asyncio
import uuid
from typing import Literal
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent / "scripts"))
import common
import boto3
from fastmcp import FastMCP
from client import connect, QUESTION
from contracts import request, transfer_id

mcp = FastMCP('AgentCore Handoff')


def remote(value):
    request(value, ('create', 'status', 'talk', 'handoff', 'advance'))
    request_path = common.save('mcp-request', value)
    cfg, call = connect()
    try:
        result = call(value)
    except Exception as exc:
        raise RuntimeError(f"Request failed for case {value['case_id']}; inspect status before retry. Saved: {request_path}. {exc}") from exc
    path = common.save('mcp-result', result)
    output = {'result': result, 'result_file': str(path)}
    if value['action'] in ('handoff', 'advance') and result.get('state', {}).get('owner') == 'successor':
        # Observer-only read with the local user's credentials, never passed to the answering agent.
        try:
            session = boto3.Session(profile_name=cfg['aws_profile'], region_name=cfg['aws_region'])
            receipt = session.resource('dynamodb').Table(cfg['tables']['inbox']).get_item(
                Key={'case_id': value['case_id']}, ConsistentRead=True)['Item']
            if receipt['transfer_id'] != result['state']['transfer_id'] or receipt['transfer_id'] != transfer_id(value['case_id'], receipt['packet']):
                raise ValueError('Receipt does not match committed handoff')
            output['handoff_record'] = receipt
            output['observation'] = '後任が保存した引き継ぎ情報です。次の質問にこの情報や前任の回答を付け足さないでください。'
        except Exception as exc:
            # Transfer already succeeded: an observer read failure must not look like a failed handoff.
            output['observation_error'] = f'Handoff committed, but receipt inspection failed: {exc}'
    common.save('mcp-observation', output)
    return output


@mcp.tool()
async def create_case(mode: Literal['minimal', 'complete'] = 'complete') -> dict:
    """Create one fictional furniture case with a fresh ID and the sample case-notes.md.

    minimal INITIALLY sends only '本棚の購入相談中。'; complete initially sends full notes.
    Successor may ask predecessor questions to enrich either initial packet during handoff.
    Initially predecessor owns the case. Does NOT talk or transfer automatically.
    Show the case ID and owner, then perform only the steps the user requested.
    Creates DynamoDB records. Do not automatically retry a failed creation.
    """
    value = {'action': 'create', 'case_id': str(uuid.uuid4()), 'mode': mode,
             'notes': (common.ROOT / 'case-notes.md').read_text(encoding='utf-8-sig')}
    return await asyncio.to_thread(remote, value)


@mcp.tool()
async def get_case_status(case_id: str) -> dict:
    """Read current owner/version and saved QA phase/revision/events; no model call.

    Display actual saved utterances and evidence, never invent a dialogue.
    """
    return await asyncio.to_thread(remote, {'action': 'status', 'case_id': case_id})


@mcp.tool()
async def ask_current_owner(case_id: str, message: str = QUESTION) -> dict:
    """Ask the currently assigned AWS representative. Return its text verbatim and answered_by.

    For the handoff comparison, use the default question before and after transfer.
    Send ONLY the user's exact question: never append previous replies, known facts,
    handoff records, summaries or the coding agent's conversation history. Do not answer on the
    representative's behalf. This calls Bedrock once; it does not ship/order anything.
    """
    return await asyncio.to_thread(remote, {'action': 'talk', 'case_id': case_id, 'message': message})


@mcp.tool()
async def handoff_case(case_id: str) -> dict:
    """Start QA-based handoff. Successor LLM asks a question or accepts the record.

    Show state.progress.events verbatim with speakers, phase and revision, then stop.
    If awaiting_answer, owner remains predecessor: use advance_handoff only when requested.
    If already enough context, successor may accept immediately and owner changes.
    Does not ask a follow-up question. Repeating an already completed transfer is idempotent.
    Never copy the observed packet or predecessor's reply into subsequent questions.
    On failure inspect get_case_status before deciding whether to retry.
    """
    return await asyncio.to_thread(remote, {'action': 'handoff', 'case_id': case_id})


@mcp.tool()
async def advance_handoff(case_id: str, expected_revision: int) -> dict:
    """Advance ONE QA round, using the revision from the most recent status/start result.

    Predecessor LLM answers successor's pending question from original notes; successor
    LLM then asks another question or accepts. Maximum two question/answer pairs.
    Show the actual new utterances with speakers and A2A IDs. Do not invent a dialogue.
    Do not loop automatically unless explicitly requested. On error inspect status.
    Repeating the same expected_revision does not advance a second round.
    """
    return await asyncio.to_thread(remote, {'action': 'advance', 'case_id': case_id,
                                           'expected_revision': expected_revision})


if __name__ == '__main__': mcp.run(transport="http", host="127.0.0.1", port=8000, path="/mcp")
