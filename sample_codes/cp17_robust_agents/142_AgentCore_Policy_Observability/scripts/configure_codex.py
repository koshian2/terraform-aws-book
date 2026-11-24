"""CodexのコールバックをCognitoへ登録してから接続設定を生成する。"""
import argparse
import base64
import hashlib
import json
import subprocess
import secrets
import time

import boto3
import httpx2
import tomllib
from urllib.parse import parse_qs, urlsplit, urlunsplit
from common import ROOT


def callback_url(server_url):
    # Codex rmcp-client/oauth_callback.rs: SHA-256先頭9バイトのbase64url。
    # このサンプルの接続先はTerraformが生成した正規化済みGateway URL。
    parsed = urlsplit(server_url)
    if parsed.scheme != "https" or not parsed.hostname:
        raise ValueError("Expected an HTTPS Gateway URL")
    normalized = urlunsplit(parsed._replace(fragment=""))
    identifier = base64.urlsafe_b64encode(hashlib.sha256(normalized.encode()).digest()[:9]).decode()
    return f"http://127.0.0.1:8766/callback/{identifier}"


def terraform(*args, capture=False):
    return subprocess.run(
        ["terraform", f"-chdir={ROOT / 'terraform'}", *args], check=True,
        capture_output=capture, text=True, encoding="utf-8",
    ).stdout


def check_plan(plan):
    # configureではコールバック登録以外の保留中の変更を適用しない。
    for change in plan.get("resource_changes", []):
        detail = change["change"]
        if detail["actions"] == ["no-op"]:
            continue
        if change["address"] != "aws_cognito_user_pool_client.local" or detail["actions"] != ["update"]:
            raise RuntimeError("先に通常のTerraform plan・applyで配置を完了してください。")
        before, after = detail["before"], detail["after"]
        changed = {key for key in before.keys() | after.keys() if before.get(key) != after.get(key)}
        if changed - {"callback_urls"}:
            raise RuntimeError("コールバック以外の変更があるため適用しません。通常のplanで確認してください。")



def verify_login_ready(cfg, callback, *, attempts=24, interval=5, required_successes=3):
    """Cognitoの登録と認可画面の両方を確認する。ログイン・トークン取得はしない。"""
    cognito = boto3.Session(profile_name=cfg["aws_profile"], region_name=cfg["aws_region"]).client("cognito-idp")
    verifier = secrets.token_urlsafe(32)
    params = {
        "response_type": "code", "client_id": cfg["client_id"],
        "redirect_uri": callback, "scope": " ".join(cfg["scopes"]),
        "state": secrets.token_urlsafe(24), "code_challenge_method": "S256",
        "code_challenge": base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode(),
        "resource": cfg["mcp_url"],
    }
    reason = "ログイン画面を確認できませんでした"
    successes = 0
    for attempt in range(attempts):
        ready = False
        # 検証時のCookieや接続を次の試行へ引き継がない。
        with httpx2.Client(timeout=15, follow_redirects=False) as http:
            registered = cognito.describe_user_pool_client(
                UserPoolId=cfg["user_pool_id"], ClientId=cfg["client_id"],
            )["UserPoolClient"]
            if callback not in registered.get("CallbackURLs", []):
                reason = "CognitoにコールバックURLがまだ反映されていません"
            else:
                response = http.get(cfg["login_base"] + "/oauth2/authorize", params=params)
                # 期待するCognitoドメイン内の/loginだけを追跡する。
                location = response.headers.get("location", "")
                parsed = urlsplit(location)
                expected = urlsplit(cfg["login_base"])
                if response.status_code == 302 and parsed.scheme == expected.scheme and parsed.netloc == expected.netloc and parsed.path == "/login":
                    page = http.get(location)
                    if page.status_code == 200 and 'name="username"' in page.text and "An error was encountered" not in page.text:
                        ready = True
                    else:
                        reason = f"ログイン画面が未準備です（HTTP {page.status_code}）"
                else:
                    error = parse_qs(parsed.query).get("error", ["なし"])[0]
                    reason = f"認可エンドポイントがログイン画面へ進めません（HTTP {response.status_code}、パス {parsed.path}、error={error}）"
        successes = successes + 1 if ready else 0
        if successes >= required_successes:
            print(f"Cognitoのコールバック登録とログイン画面を{required_successes}回連続で確認しました。")
            return
        if ready:
            reason = f"ログイン画面への到達を確認しました（連続{successes}/{required_successes}回）"
        if attempt + 1 < attempts:
            print(f"{reason}。反映の安定を待っています。", flush=True)
            time.sleep(interval)
    raise RuntimeError(reason + "。設定生成は完了していません。--overwriteで再実行してください。")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--overwrite", action="store_true", help="生成済み設定を更新する")
    args = parser.parse_args()
    target = ROOT / "codex/.codex/config.toml"
    if target.exists() and not args.overwrite:
        raise SystemExit("設定が既にあります。更新する場合は--overwriteを指定してください。")
    url = terraform("output", "-raw", "mcp_url", capture=True).strip()
    callback = callback_url(url)
    # 次回の通常applyでも登録が元に戻らないよう、専用の変数ファイルへ保存。
    variables = ROOT / "terraform/zz-codex-callback.auto.tfvars.json"
    variables.write_text(json.dumps({"codex_oauth_callback_url": callback}, indent=2) + "\n", encoding="utf-8")
    terraform("plan", "-input=false", "-out=codex-callback.tfplan")
    plan = json.loads(terraform("show", "-json", "codex-callback.tfplan", capture=True))
    check_plan(plan)
    terraform("apply", "-input=false", "codex-callback.tfplan")
    config = terraform("output", "-raw", "codex_mcp_config", capture=True)
    servers = tomllib.loads(config)["mcp_servers"]
    if len(servers) != 1 or next(iter(servers.values()))["oauth"]["callback_url"] != callback:
        raise RuntimeError("CognitoとCodexのコールバック設定が一致しません。")
    cfg = json.loads(terraform("output", "-json", "client_config", capture=True))
    verify_login_ready(cfg, callback)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(config, encoding="utf-8")
    print(f"Created {target}")


if __name__ == "__main__":
    main()
