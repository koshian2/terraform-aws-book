"""GatewayのPolicyで許可・拒否を判定する足し算MCP。"""
from typing import Annotated
from fastmcp import FastMCP
from pydantic import Field

mcp = FastMCP("Policy observability calculator")

@mcp.tool()
def add(a: Annotated[int, Field(ge=-1000000, le=1000000)],
        b: Annotated[int, Field(ge=-1000000, le=1000000)]) -> dict:
    """Add two integers. The Gateway authorizes each calculation."""
    return {'a': a, 'b': b, 'sum': a + b}


if __name__ == "__main__":
    mcp.run(transport="http", host="0.0.0.0", port=8000, path="/mcp", stateless_http=True)
