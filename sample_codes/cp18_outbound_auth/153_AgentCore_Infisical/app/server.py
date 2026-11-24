"""Expose one fixed demo configuration through the Runtime's IAM identity."""
import asyncio
import os

from mcp.server.fastmcp import FastMCP
from mcp.server.transport_security import TransportSecuritySettings

from infisical_aws import get_demo_message as read_message

mcp = FastMCP("Infisical AWS Auth demo", host="0.0.0.0", port=8000,
              stateless_http=True, json_response=True,
              transport_security=TransportSecuritySettings(enable_dns_rebinding_protection=False))


@mcp.tool()
async def get_demo_message() -> dict:
    """Read DEMO_MESSAGE from the sample project's dev environment using the application's AWS identity."""
    try:
        return await asyncio.to_thread(
            read_message, os.environ["INFISICAL_HOST"], os.environ["INFISICAL_IDENTITY_ID"],
            os.environ["INFISICAL_PROJECT_ID"], os.environ["STS_REGION"],
        )
    except Exception:
        # Never include SDK/HTTP exception text, signed requests or token values.
        raise ValueError("Infisical read failed. Check AWS Auth and project permissions.") from None


if __name__ == "__main__":
    mcp.run(transport="streamable-http")
