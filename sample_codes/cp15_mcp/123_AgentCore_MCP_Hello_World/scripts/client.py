"""ツール一覧を取得し、hello_worldの応答を確認します。"""

import argparse
import asyncio

from connection import connect, remote_transport


async def main(args):
    transport = args.url if args.url else remote_transport()
    async with connect(transport) as client:
        tools = await client.list_tools()
        names = [tool.name for tool in tools]
        print(f"Tools: {', '.join(names)}")
        if names != ["hello_world"]:
            raise RuntimeError(f"想定外のツール一覧です: {names}")
        result = await client.call_tool("hello_world", {})
        texts = [item.text for item in result.content if item.type == "text"]
        if result.is_error or texts != ["Hello World"]:
            raise RuntimeError(f"想定外の応答です: {result}")
        print(texts[0])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", help="ローカル確認用のURL。省略時はTerraform出力からAWSに接続")
    asyncio.run(main(parser.parse_args()))
