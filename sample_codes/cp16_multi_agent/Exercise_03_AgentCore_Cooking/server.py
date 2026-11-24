"""RuntimeのMCPをIAM署名付きで中継する。ツール定義は持たない。"""
import argparse
from pathlib import Path
import sys

from fastmcp.server.providers.proxy import FastMCPProxy

sys.path.insert(0, str(Path(__file__).resolve().parent / "scripts"))
from connection import connect, remote_transport


def create_proxy(url=None):
    # 操作ごとに新しい接続を使い、Runtimeの古い実行セッションを再利用しない。
    return FastMCPProxy(
        name="AgentCore Cooking Proxy",
        client_factory=lambda: connect(url if url else remote_transport()),
        provider_error_strategy="raise",
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", help="ローカル検証用の転送先。省略時はRuntime")
    parser.add_argument("--port", type=int, default=8000)
    args = parser.parse_args()
    create_proxy(args.url).run(transport="http", host="127.0.0.1", port=args.port,
                               path="/mcp", host_origin_protection=True)
