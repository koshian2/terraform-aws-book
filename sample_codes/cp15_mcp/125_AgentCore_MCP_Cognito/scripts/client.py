"""ブラウザでログインし、AgentCoreのhello_worldを直接呼び出します。"""
import argparse
import asyncio
from contextlib import asynccontextmanager

from fastmcp import Client
from fastmcp.client.transports.base import ClientTransport, TransportOptions
import httpx2
from mcp.client.streamable_http import streamable_http_client

from common import settings
from login import login


class AgentCoreTransport(ClientTransport):
    def __init__(self, url, token):
        self.url = url
        self.token = token

    @asynccontextmanager
    async def connect_session(self, *, transport_options=None, **session_kwargs):
        options = transport_options or TransportOptions()
        async with (
            httpx2.AsyncClient(headers={"Authorization": f"Bearer {self.token}"}, timeout=120) as http,
            streamable_http_client(self.url, http_client=http, terminate_on_close=False) as (read, write),
            options.session_class(read, write, **session_kwargs) as session,
        ):
            yield session


async def call(transport):
    async with Client(transport, mode="legacy", timeout=120) as client:
        names = [tool.name for tool in await client.list_tools()]
        print(f"Tools: {', '.join(names)}")
        if names != ["hello_world"]:
            raise RuntimeError(f"想定外のツール一覧: {names}")
        result = await client.call_tool("hello_world", {})
        texts = [item.text for item in result.content if item.type == "text"]
        if result.is_error or texts != ["Hello World"]:
            raise RuntimeError(f"想定外の応答: {result}")
        print(texts[0])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--local", action="store_true", help="ローカルサーバーを認証なしで確認")
    parser.add_argument("--no-browser", action="store_true", help="ログインURLを表示し、ブラウザを自動起動しない")
    args = parser.parse_args()
    if args.local:
        transport = "http://127.0.0.1:8000/mcp"
    else:
        config = settings()
        transport = AgentCoreTransport(config["mcp_url"], login(config, no_browser=args.no_browser))
    asyncio.run(call(transport))
