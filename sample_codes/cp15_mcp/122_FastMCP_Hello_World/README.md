# FastMCPのローカルHTTPサーバーでHello World

引数なしの `hello_world` ツールを1つだけ公開するMCPサーバーです。コーディングエージェントから呼び出すと、文字列 `Hello World` を返します。エージェントがその結果をチャットに表示します。

FastMCPの `transport="http"` を使い、Streamable HTTPで通信します。接続先は `http://127.0.0.1:8000/mcp` です。サーバーとエージェントは同じマシン・ネットワーク環境で動かしてください。ローカルのループバックアドレスで待ち受けます（詳細は[FastMCP公式の起動方法](https://gofastmcp.com/deployment/running-server)を参照）。

## 構成

```text
122_FastMCP_Hello_World/
├── server.py
├── pyproject.toml
├── commands.sh
├── codex/.codex/config.toml
├── claude-code/.mcp.json
├── antigravity/.agents/mcp_config.json
└── kiro/.kiro/settings/mcp.json
```

`server.py` の `@mcp.tool` がPython関数をMCPツールとして公開します。`return` の文字列がツールの結果です。サーバーの起動ログとは区別してください。

## 起動する

Python 3.14とuvを用意し、このサンプルのルートで [commands.sh](commands.sh) のコマンドを順に実行します。Windows・macOSとも同じコマンドを使えます。初回の `uv sync` で依存パッケージをインストールします。

サーバーを起動したターミナルは開いたままにします。エージェントの設定にはHTTPのURLだけを指定しているため、エージェントがサーバーを自動起動する構成ではありません。

## エージェントから接続する

利用する製品のフォルダをプロジェクトとして開きます。設定は配置済みです。設定ファイルの追加・接続確認の詳しい操作は [121番のREADME](../121_AWS_Knowledge_MCP/README.md) を参照してください。

| 製品 | 開くフォルダ | 設定ファイル |
|---|---|---|
| Codex | `codex/` | [.codex/config.toml](codex/.codex/config.toml) |
| Claude Code | `claude-code/` | [.mcp.json](claude-code/.mcp.json) |
| Antigravity | `antigravity/` | [.agents/mcp_config.json](antigravity/.agents/mcp_config.json) |
| Kiro | `kiro/` | [.kiro/settings/mcp.json](kiro/.kiro/settings/mcp.json) |

クライアントを再読み込みし、MCPの管理画面で `hello-world` サーバーと `hello_world` ツールを確認します。Codex・Claude Codeでは対話画面の `/mcp` を使えます。プロジェクトの信頼確認やツール利用の確認が表示されたら、内容を確認して許可します。

チャットに次を入力してください。

> hello-world MCPサーバーのhello_worldツールを呼び出して、返された文字列だけを表示してください。ツールを呼び出せなければ、その旨を伝えてください。

期待するツール結果は次のとおりです。

```text
Hello World
```

呼び出し履歴で `hello_world` の実行成功と結果を確認してください。エージェントが文章を生成しただけでは接続確認になりません。

## 接続できないとき・停止するとき

まずサーバーのターミナルが起動中か、接続先に `/mcp` が付いているかを確認します。8000番ポートが使用中なら、`server.py` のポートと使用するエージェントの設定URLを同じ番号に変更します。WSLやコンテナで動かす場合、`127.0.0.1` が別の環境を指すことがあるため、最初はサーバーとエージェントを同じ環境で試してください。

終了時はサーバーのターミナルでCtrl+Cを押します。MCP登録も解除する場合は、対象の設定ファイルから `hello-world` の項目を削除します。
