"""エージェントからのHTTP接続を、IAM署名付きでAgentCoreへ中継します。"""

import argparse

from fastmcp.server.providers.proxy import FastMCPProxy

from connection import connect, remote_transport


def main(args):
    # 操作ごとに接続を作り、アイドルタイムアウト後のセッションを再利用しない。
    proxy = FastMCPProxy(
        name="AgentCore Hello World",
        client_factory=lambda: connect(args.url if args.url else remote_transport()),
        provider_error_strategy="raise",
    )
    proxy.run(
        transport="http", host="127.0.0.1", port=8001, path="/mcp",
        host_origin_protection=True,
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", help="ローカル中継確認用の転送先。省略時はAgentCore")
    main(parser.parse_args())
