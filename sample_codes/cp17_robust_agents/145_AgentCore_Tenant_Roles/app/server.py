"""One shared MCP tool, with membership supplied by the authenticated Gateway."""
import asyncio
import json
import os
from fastmcp import FastMCP
from fastmcp.server.dependencies import get_http_headers
from interceptor import HEADER
from tenant_data import read_inquiry

mcp = FastMCP('Tenant inquiries', strict_input_validation=True, mask_error_details=True)


@mcp.tool()
async def get_inquiry(ticket_id: str) -> dict:
    """Read an inquiry belonging to the signed-in user's company, e.g. T001.

Company membership is determined by authentication and cannot be selected here.
"""
    tenant = get_http_headers().get(HEADER.lower(), '')
    try:
        return await asyncio.to_thread(read_inquiry, tenant, ticket_id,
                                       json.loads(os.environ['TENANT_CONFIG']), os.environ['DATA_REGION'])
    except Exception as error:
        code = getattr(error, 'response', {}).get('Error', {}).get('Code', type(error).__name__)
        print('inquiry_failed', code)
        raise ValueError('Inquiry access failed. Check membership and permissions.') from None


if __name__ == '__main__':
    mcp.run(transport='http', host='0.0.0.0', port=8000, path='/mcp', stateless_http=True)
