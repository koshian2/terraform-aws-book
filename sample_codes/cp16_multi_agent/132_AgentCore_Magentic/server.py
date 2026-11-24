"""AWS上の処理を呼び出すローカルHTTP MCPサーバー。"""
import asyncio
import uuid
from typing import Literal
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent / "scripts"))
import common
from fastmcp import FastMCP
from client import connect, REQUEST
from contracts import manager_request

mcp = FastMCP('AgentCore Magentic')


def remote(value):
    manager_request(value)
    path = common.save('mcp-request', value)
    _, call = connect()
    try:
        result = call(value)
    except Exception as exc:
        raise RuntimeError(f"Case {value['case_id']}: inspect get_case_status before retrying. Request: {path}. {exc}") from exc
    saved = common.save('mcp-result', result)
    return {'result': result, 'result_file': str(saved)}


@mcp.tool()
async def create_case(scenario: Literal['normal', 'delayed'] = 'delayed') -> dict:
    """Start a fictional dealer coordination case and generate its initial plan in AWS.

    For a requested demo, display the initial plan then automatically call advance_case
    until completed or blocked, maximum 9 advances. No confirmation between rounds.
    Show actual new questions, specialist replies and plan-change reasons each round.
    AWS chooses specialists and questions; never invent or replace their decisions.
    Uses Bedrock and DynamoDB, but performs no bookings, payments or real claims.
    On an error inspect status and stop; do not automatically retry creation.
    """
    return await asyncio.to_thread(remote, {'action': 'create', 'case_id': str(uuid.uuid4()),
                                           'scenario': scenario, 'request': REQUEST})


@mcp.tool()
async def advance_case(case_id: str, expected_revision: int) -> dict:
    """Execute the pending AWS-selected consultation and update the dealer's plan.

    Use the latest revision. Announce the pending specialist before calling this tool.
    Display only newly returned actual questions, replies and plan changes with speakers.
    For an ongoing demo, continue automatically until completed or blocked (max 9 calls).
    The dealer retains ownership; the coding agent only observes and advances the AWS manager.
    On an error inspect status then stop. Do not retry or change infrastructure/policies.
    """
    return await asyncio.to_thread(remote, {'action': 'advance', 'case_id': case_id,
                                           'expected_revision': expected_revision})


@mcp.tool()
async def get_case_status(case_id: str) -> dict:
    """Read saved plans and actual A2A replies without calling any model or advancing."""
    return await asyncio.to_thread(remote, {'action': 'status', 'case_id': case_id})


if __name__ == '__main__': mcp.run(transport="http", host="127.0.0.1", port=8000, path="/mcp")
