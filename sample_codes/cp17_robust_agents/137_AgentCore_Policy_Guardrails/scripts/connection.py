"""Gatewayへ接続し、MCP応答とPolicy拒否を区別する。"""
import json

import httpx2
from mcp import ClientSession, MCPError
from mcp.client.streamable_http import streamable_http_client


def leaves(exc):
    if isinstance(exc, BaseExceptionGroup):
        return [leaf for child in exc.exceptions for leaf in leaves(child)]
    return [exc]


def policy_denial(exc):
    """401・一般の403・通信障害を、Policy拒否成功として扱わない。"""
    if isinstance(exc, MCPError):
        error = exc.error.model_dump()
    elif isinstance(exc, httpx2.HTTPStatusError):
        try:
            error = exc.response.json().get("error", {})
        except (ValueError, AttributeError):
            return None
    else:
        return None
    message = error.get("message", "")
    if error.get("code") == -32002 and any(s in message.lower() for s in ("denied", "blocked by policy")):
        status = "output_suppressed" if "output blocked by policy" in message.lower() else "policy_denied"
        return {"status": status, "code": error["code"], "message": message}
    return None


async def read_error(response):
    if response.is_error:
        await response.aread()


async def call(url, token, tool, arguments):
    try:
        async with httpx2.AsyncClient(
            headers={"Authorization": f"Bearer {token}"}, timeout=120,
            event_hooks={"response": [read_error]},
        ) as http:
            async with streamable_http_client(url, http_client=http, terminate_on_close=False) as (read, write):
                async with ClientSession(read, write, read_timeout_seconds=120) as session:
                    await session.initialize()
                    tools = await session.list_tools()
                    if tool not in [t.name for t in tools.tools]:
                        raise RuntimeError(f"Tool is not visible: {tool}")
                    result = await session.call_tool(tool, arguments)
                    return {
                        "status": "tool_error" if result.is_error else "ok",
                        "result": result.model_dump(mode="json", by_alias=True, exclude_none=True),
                    }
    except Exception as exc:
        errors = leaves(exc)
        denials = [policy_denial(error) for error in errors]
        if denials and all(d is not None for d in denials):
            return denials[0]
        raise


def data_of(record):
    result = record.get("result", {})
    if "structuredContent" in result:
        return result["structuredContent"]
    content = result.get("content", [])
    if len(content) == 1 and content[0].get("type") == "text":
        return json.loads(content[0]["text"])
    raise ValueError("Unexpected MCP result schema")
