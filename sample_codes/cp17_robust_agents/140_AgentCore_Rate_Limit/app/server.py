"""Gatewayで呼び出し回数を制限する足し算MCP。"""
from typing import Annotated
from fastmcp import FastMCP
from pydantic import Field

mcp = FastMCP("Rate limit calculator")

@mcp.tool()
def add(a: Annotated[int, Field(ge=-1000000, le=1000000)],
        b: Annotated[int, Field(ge=-1000000, le=1000000)]) -> dict:
    """Add two integers. Call once for each calculation; Gateway may rate-limit calls."""
    return {'a': a, 'b': b, 'sum': a + b}


if __name__ == "__main__":
    mcp.run(transport="http", host="0.0.0.0", port=8000, path="/mcp", stateless_http=True)
