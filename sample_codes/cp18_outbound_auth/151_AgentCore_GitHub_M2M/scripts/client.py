"""Cognito authenticates the caller; GitHub App credentials never reach this client."""
import argparse
import asyncio
import json
import os

import httpx
from mcp import ClientSession
from mcp.client.streamable_http import streamable_http_client
from common import settings


async def run(args):
    token = os.environ.get("AGENTCORE_ACCESS_TOKEN", "").strip()
    if not token:
        raise SystemExit("Set AGENTCORE_ACCESS_TOKEN using login.py first")
    config = settings()
    async with httpx.AsyncClient(headers={"Authorization": "Bearer " + token},
                                 timeout=120) as http:
        async with streamable_http_client(config["mcp_url"], http_client=http, terminate_on_close=False) as (read, write, _):
            async with ClientSession(read, write) as session:
                await session.initialize()
                if args.action == "list":
                    print((await session.list_tools()).model_dump_json(indent=2))
                    return
                result = await session.call_tool(config["tool_prefix"] + "get_issue", {"issue_number": args.issue_number})
                print(result.model_dump_json(indent=2))
                if result.isError:
                    raise SystemExit(1)
                data = result.structuredContent or json.loads(result.content[0].text)
                if data.get("status") != "ok":
                    raise SystemExit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["list", "get"])
    parser.add_argument("issue_number", nargs="?", type=int, default=1)
    asyncio.run(run(parser.parse_args()))
