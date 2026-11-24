"""One-shot Cognito Authorization Code + PKCE login; stdout is the access token."""
import argparse
import base64
import hashlib
from http.server import BaseHTTPRequestHandler, HTTPServer
import secrets
import sys
import time
from urllib.parse import parse_qs, urlencode, urlsplit
import webbrowser

from common import settings
import httpx


def pkce_challenge(verifier):
    return base64.urlsafe_b64encode(hashlib.sha256(verifier.encode("ascii")).digest()).rstrip(b"=").decode("ascii")


def callback_code(path, expected_state):
    parsed = urlsplit(path)
    if parsed.path != "/callback":
        raise ValueError("Unexpected callback path")
    query = parse_qs(parsed.query)
    states = query.get("state", [])
    if len(states) != 1 or not secrets.compare_digest(states[0], expected_state):
        raise ValueError("OAuth state mismatch")
    if "error" in query:
        raise RuntimeError("Cognito rejected the authorization request")
    codes = query.get("code", [])
    if len(codes) != 1 or not codes[0]:
        raise ValueError("Missing or ambiguous authorization code")
    return codes[0]


def login(config, no_browser=False):
    verifier = secrets.token_urlsafe(48)
    state = secrets.token_urlsafe(32)
    redirect = urlsplit(config["callback_url"])
    if redirect.scheme != "http" or redirect.hostname != "localhost" or redirect.path != "/callback":
        raise ValueError("This sample requires http://localhost:<port>/callback")
    result = {}

    class Callback(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass # Do not log authorization codes or request URLs.

        def do_GET(self):
            try:
                code = callback_code(self.path, state)
            except ValueError:
                self.send_error(400, "Invalid callback")
                return # Ignore unrelated/forged callbacks and keep waiting.
            except RuntimeError as exc:
                result["error"] = exc
                message = b"Login was not completed. Return to your terminal."
            else:
                result["code"] = code
                message = b"Authorization received. You can close this tab."
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(message)))
            self.end_headers()
            self.wfile.write(message)

    url = config["login_base"] + "/oauth2/authorize?" + urlencode({
        "response_type": "code", "client_id": config["client_id"],
        "redirect_uri": config["callback_url"], "scope": " ".join(config["scopes"]),
        "state": state, "code_challenge_method": "S256",
        "code_challenge": pkce_challenge(verifier),
    })
    with HTTPServer(("127.0.0.1", redirect.port), Callback) as server:
        server.timeout = 1
        print("Open this URL in a browser on this computer:\n" + url, file=sys.stderr)
        if not no_browser:
            webbrowser.open(url)
        deadline = time.monotonic() + 300
        while not result and time.monotonic() < deadline:
            server.handle_request()
    if "error" in result:
        raise result["error"]
    if "code" not in result:
        raise TimeoutError("Login timed out after 300 seconds")
    with httpx.Client(timeout=30) as client:
        response = client.post(config["login_base"] + "/oauth2/token", data={
            "grant_type": "authorization_code", "client_id": config["client_id"],
            "code": result["code"], "redirect_uri": config["callback_url"],
            "code_verifier": verifier,
        })
        response.raise_for_status()
        tokens = response.json()
    if tokens.get("token_type", "").lower() != "bearer" or not tokens.get("access_token"):
        raise RuntimeError("Cognito did not return a Bearer access token")
    # ID/refresh tokens are deliberately neither printed nor persisted.
    print(f"Login succeeded; token expires in {tokens['expires_in']} seconds.", file=sys.stderr)
    return tokens["access_token"]


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--no-browser", action="store_true")
    args = parser.parse_args()
    try:
        print(login(settings(), args.no_browser))
    except Exception as exc:
        print(f"Login failed: {exc}", file=sys.stderr)
        sys.exit(1)
