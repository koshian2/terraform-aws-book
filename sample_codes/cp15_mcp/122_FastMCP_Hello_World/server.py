from fastmcp import FastMCP

mcp = FastMCP("Hello World")


@mcp.tool
def hello_world() -> str:
    """Hello Worldを返します。"""
    return "Hello World"


if __name__ == "__main__":
    mcp.run(transport="http", host="127.0.0.1", port=8000, path="/mcp")
