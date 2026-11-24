"""Cognitoでログインし、Gateway配下の3種類のツールを呼び出します。"""
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


async def call(transport, *, local=False, query="AWS Lambda maximum execution timeout"):
    async with Client(transport, mode="legacy", timeout=120) as client:
        names = [tool.name for tool in await client.list_tools()]
        print(f"Tools: {', '.join(names)}")
        hello = "hello_world" if local else "hello-runtime___hello_world"
        if hello not in names:
            raise RuntimeError(f"Hello Worldツールがありません: {names}")
        result = await client.call_tool(hello, {})
        texts = [item.text for item in result.content if item.type == "text"]
        if result.is_error or texts != ["Hello World"]:
            raise RuntimeError(f"想定外の応答: {result}")
        print(texts[0])
        if local:
            return
        result = await client.call_tool("calculator___add", {"a": 12, "b": 30})
        if result.is_error:
            raise RuntimeError(f"Lambda呼び出し失敗: {result}")
        print("Lambda (12 + 30):")
        for item in result.content:
            if item.type == "text":
                print(item.text)
        # 外部MCP側にも接頭辞があるため、一覧から実際の名前を選ぶ。
        candidates = [name for name in names if name.startswith("aws___") and name.split("___")[-1] == "search_documentation"]
        if len(candidates) != 1:
            raise RuntimeError(f"AWS検索ツールを一意に特定できません: {candidates}")
        result = await client.call_tool(candidates[0], {"search_phrase": query})
        if result.is_error:
            raise RuntimeError(f"AWS検索失敗: {result}")
        print("AWS Knowledge MCP:")
        for item in result.content:
            if item.type == "text":
                print(item.text)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--local", action="store_true", help="ローカルサーバーを認証なしで確認")
    parser.add_argument("--no-browser", action="store_true", help="ログインURLを表示し、ブラウザを自動起動しない")
    parser.add_argument("--query", default="AWS Lambda maximum execution timeout", help="AWSドキュメント検索語")
    args = parser.parse_args()
    if args.local:
        transport = "http://127.0.0.1:8000/mcp"
    else:
        config = settings()
        transport = AgentCoreTransport(config["mcp_url"], login(config, no_browser=args.no_browser))
    asyncio.run(call(transport, local=args.local, query=args.query))
