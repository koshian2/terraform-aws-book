"""Log in to Entra and launch a coding agent with an in-memory bearer token."""
import argparse
from datetime import datetime, timezone
import json
import os
import shutil
import subprocess
from common import ROOT, settings, safe_failure
from client import login

SERVER = "agentcore-entra-obo"
TOKEN_ENV = "AGENTCORE_ENTRA_ACCESS_TOKEN"

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("agent", choices=["codex", "claude"])
    args = parser.parse_args()
    executable = shutil.which(args.agent)
    if not executable:
        raise RuntimeError("Coding agent CLI was not found in PATH")
    cfg = settings()
    token, claims = login(cfg, "ログインするEntraユーザーを選択してください")
    print("トークン有効期限 (UTC):", datetime.fromtimestamp(claims["exp"], timezone.utc).isoformat())
    folder = ROOT / ("codex" if args.agent == "codex" else "claude-code")
    if args.agent == "codex":
        path = folder / ".codex/config.toml"
        content = (f'[mcp_servers.{SERVER}]\nurl = {json.dumps(cfg["gateway_url"])}\n'
                   f'bearer_token_env_var = "{TOKEN_ENV}"\nstartup_timeout_sec = 120\ntool_timeout_sec = 180\n')
    else:
        path = folder / ".mcp.json"
        content = json.dumps({"mcpServers": {SERVER: {"type": "http", "url": cfg["gateway_url"],
            "headers": {"Authorization": "Bearer ${" + TOKEN_ENV + "}"}}}}, indent=2) + "\n"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    env = os.environ.copy()
    env[TOKEN_ENV] = token
    try:
        command = [executable, "--no-daemon"] if args.agent == "codex" else [executable]
        return subprocess.call(command, cwd=folder, env=env)
    finally:
        env.pop(TOKEN_ENV, None)

if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(json.dumps(safe_failure(error)))
        raise SystemExit(1)
