"""Cognitoからのサインアウトと、クライアントのPolicyセッション更新。"""
import argparse
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import re
import shutil
import subprocess
import time
import tomllib
from urllib.parse import urlencode, urlsplit
import uuid
import webbrowser
from common import ROOT, settings

SERVER = "agentcore-temporal"

def browser_logout(config, open_browser=webbrowser.open, timeout=300):
    redirect = urlsplit(config["logout_url"])
    if redirect.scheme != "http" or redirect.hostname != "localhost" or redirect.path != "/signed-out":
        raise ValueError("Expected the local sign-out callback")
    completed = False

    class Callback(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_GET(self):
            nonlocal completed
            if self.path != "/signed-out":
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(b"Cognito signed out. Close this tab; a new login window will open.")
            completed = True

    url = config["login_base"] + "/logout?" + urlencode({
        "client_id": config["client_id"], "logout_uri": config["logout_url"],
    })
    with HTTPServer(("127.0.0.1", redirect.port), Callback) as server:
        server.timeout = 1
        print("Signing out of Cognito in your default browser...", flush=True)
        print("If no browser opens, open this URL in the browser Codex uses:\n" + url, flush=True)
        open_browser(url)
        deadline = time.monotonic() + timeout
        while not completed and time.monotonic() < deadline:
            server.handle_request()
    if not completed:
        raise TimeoutError("Cognito sign-out did not complete; new login was not started")


def reset_session(client):
    session_id = str(uuid.uuid4())
    if client == "codex":
        path = ROOT / "codex/.codex/config.toml"
        text = path.read_text(encoding="utf-8")
        tomllib.loads(text)["mcp_servers"][SERVER]
        text, count = re.subn(r'("x-amzn-bedrock-agentcore-policy-session-id"\s*=\s*")[^"]*(")', lambda m: m[1] + session_id + m[2], text)
        if count != 1:
            raise ValueError("Expected exactly one Policy session header")
        tomllib.loads(text)
        path.write_text(text, encoding="utf-8")
    else:
        path = ROOT / "claude-code/.mcp.json"
        config = json.loads(path.read_text(encoding="utf-8"))
        config["mcpServers"][SERVER]["headers"]["x-amzn-bedrock-agentcore-policy-session-id"] = session_id
        path.write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return session_id


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--client", choices=["python", "codex", "claude"], default="python")
    parser.add_argument("--new-session-only", action="store_true")
    args = parser.parse_args()
    if args.new_session_only and args.client == "python":
        parser.error("Pythonクライアントはケースごとに新しいセッションを生成します。")
    if not args.new_session_only:
        if args.client != "python":
            executable = shutil.which(args.client + ".cmd") or shutil.which(args.client)
            if not executable:
                raise RuntimeError(f"{args.client} CLI was not found")
            folder = ROOT / ("codex" if args.client == "codex" else "claude-code")
            subprocess.run([executable, "mcp", "logout", SERVER], cwd=folder, check=True)
        browser_logout(settings())
    if args.client != "python":
        print("New Policy session:", reset_session(args.client))
    print("次に使うユーザーでログインしてください。起動中のエージェントは終了してから再起動してください。")


if __name__ == "__main__":
    main()
