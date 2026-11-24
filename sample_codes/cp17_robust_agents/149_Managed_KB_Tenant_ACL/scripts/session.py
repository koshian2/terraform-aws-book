"""ユーザー切り替え前にCognitoのブラウザセッションを終了する。"""
import argparse
from http.server import BaseHTTPRequestHandler, HTTPServer
import shutil
import subprocess
import time
from urllib.parse import urlencode, urlsplit
import webbrowser
from common import ROOT, settings

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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--client', choices=['browser', 'codex'], default='browser')
    args = parser.parse_args()
    if args.client == 'codex':
        executable = shutil.which('codex.cmd') or shutil.which('codex')
        if not executable:
            raise RuntimeError('Codex CLI was not found')
        subprocess.run([executable, 'mcp', 'logout', 'agentcore-kb-tenant'], cwd=ROOT/'codex', check=True)
    browser_logout(settings())
    print('次のユーザーでログインしてください。エージェントは再起動してください。')

if __name__ == '__main__':
    main()
