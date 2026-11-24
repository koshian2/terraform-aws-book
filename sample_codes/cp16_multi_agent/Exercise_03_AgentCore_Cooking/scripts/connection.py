"""Terraformの出力を読み、AgentCoreへIAM署名付きで接続します。"""

from contextlib import asynccontextmanager

import boto3
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest
from fastmcp import Client
from fastmcp.client.transports.base import ClientTransport, TransportOptions
from mcp.client.streamable_http import streamable_http_client
import httpx2

from urllib.parse import quote
import common


class SigV4(httpx2.Auth):
    requires_request_body = True

    def __init__(self, session, region):
        self.session = session
        self.region = region

    def auth_flow(self, request):
        credentials = self.session.get_credentials()
        if credentials is None:
            raise RuntimeError("AWSの認証情報が見つかりません。プロファイルとログイン状態を確認してください。")
        # セッションIDなどのMCPヘッダーを含め、HTTPリクエストごとに署名する。
        for header in ("authorization", "x-amz-date", "x-amz-security-token"):
            request.headers.pop(header, None)
        aws_request = AWSRequest(
            method=request.method, url=str(request.url), data=request.content,
            headers=dict(request.headers),
        )
        SigV4Auth(credentials.get_frozen_credentials(), "bedrock-agentcore", self.region).add_auth(aws_request)
        request.headers.update(dict(aws_request.headers))
        yield request


class AgentCoreTransport(ClientTransport):
    """AgentCoreへの接続では、終了時にMCPのDELETEを送信しません。"""

    def __init__(self, url, auth):
        self.url = url
        self.auth = auth

    @asynccontextmanager
    async def connect_session(self, *, transport_options=None, **session_kwargs):
        options = transport_options or TransportOptions()
        timeout = session_kwargs.get("read_timeout_seconds") or 720
        # AWSのセッション終了はRuntimeのアイドルタイムアウトに任せる。
        # ローカル側のHTTP接続は、このコンテキストの終了時に閉じる。
        async with (
            httpx2.AsyncClient(auth=self.auth, timeout=httpx2.Timeout(timeout, connect=30)) as http,
            streamable_http_client(
                self.url, http_client=http, terminate_on_close=False,
            ) as (read, write),
            options.session_class(read, write, **session_kwargs) as session,
        ):
            yield session


def remote_transport():
    config = common.settings()
    session = boto3.Session(profile_name=config["aws_profile"], region_name=config["aws_region"])
    arn = quote(config["runtime_arn"], safe="")
    url = f"https://bedrock-agentcore.{config['aws_region']}.amazonaws.com/runtimes/{arn}/invocations?qualifier=DEFAULT"
    return AgentCoreTransport(url, auth=SigV4(session, config["aws_region"]))


def connect(transport):
    # 初期化ハンドシェイクとMcp-Session-Idを使う接続を明示する。
    return Client(transport, mode="legacy", timeout=720)
