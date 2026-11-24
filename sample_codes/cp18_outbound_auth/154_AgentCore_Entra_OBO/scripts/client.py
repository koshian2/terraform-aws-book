"""Interactive PKCE -> Gateway OBO. Tokens exist only in this process's memory."""
import argparse
import asyncio
from datetime import datetime, timezone
import importlib.metadata
import json
import os
from pathlib import Path
import sys
import uuid
import webbrowser

from common import ROOT, safe_failure, settings, diagnostic_words
import httpx
import jwt
import msal
from mcp import ClientSession
from mcp.client.streamable_http import streamable_http_client


def configure_private_browser():
    """Use Edge/Chrome private mode for MSAL on Windows and macOS."""
    if sys.platform == "win32":
        roots = [Path(os.environ[key]) for key in
                 ("PROGRAMFILES(X86)", "PROGRAMFILES", "LOCALAPPDATA") if os.environ.get(key)]
        candidates = [(root / relative, flag) for relative, flag in (
            ("Microsoft/Edge/Application/msedge.exe", "--inprivate"),
            ("Google/Chrome/Application/chrome.exe", "--incognito"),
        ) for root in roots]
    elif sys.platform == "darwin":
        candidates = [(root / relative, flag) for relative, flag in (
            ("Google Chrome.app/Contents/MacOS/Google Chrome", "--incognito"),
            ("Microsoft Edge.app/Contents/MacOS/Microsoft Edge", "--inprivate"),
        ) for root in (Path("/Applications"), Path.home() / "Applications")]
    else:
        raise RuntimeError("Private browser login supports Windows and macOS")
    selected = next(((path, flag) for path, flag in candidates if path.is_file()), None)
    if selected is None:
        print("プライベートログインにはMicrosoft EdgeまたはGoogle Chromeをインストールしてください。",
              file=sys.stderr, flush=True)
        raise RuntimeError("No supported private browser found")

    class PrivateBrowser(webbrowser.BackgroundBrowser):
        def open(self, url, new=0, autoraise=True):
            if not super().open(url, new, autoraise):
                raise RuntimeError("Private browser launch failed")
            return True

    path, flag = selected
    webbrowser.register("entra-private", None,
                        PrivateBrowser([str(path), flag, "--new-window", "%s"]), preferred=True)


def validate_claims(claims, config):
    expected = {"ver": "2.0", "tid": config["tenant_id"],
                "azp": config["local_client_id"], "scp": "access_as_user"}
    if any(claims.get(key) != value for key, value in expected.items()):
        raise ValueError("Unexpected inbound token claims")
    uuid.UUID(claims["oid"])
    return claims


def login(config, label):
    configure_private_browser()
    print(f"{label}: プライベートウィンドウで検証ユーザーを選択してください。"
          "前回のログインを引き継がない場合は、既存のプライベートウィンドウをすべて閉じてください。",
          flush=True)
    app = msal.PublicClientApplication(
        config["local_client_id"],
        authority=f"https://login.microsoftonline.com/{config['tenant_id']}",
        token_cache=msal.TokenCache(), enable_broker_on_windows=False,
    )
    result = app.acquire_token_interactive(
        scopes=[config["scope"]], prompt="select_account", timeout=300,
    )
    if "access_token" not in result:
        # Do not emit error_description or the complete result dictionary.
        raise RuntimeError("Entra interactive login failed; inspect sign-in logs")
    token = result["access_token"]
    jwks = jwt.PyJWKClient(
        f"https://login.microsoftonline.com/{config['tenant_id']}/discovery/v2.0/keys",
        timeout=30,
    )
    claims = jwt.decode(
        token, jwks.get_signing_key_from_jwt(token).key, algorithms=["RS256"],
        audience=config["api_client_id"],
        issuer=f"https://login.microsoftonline.com/{config['tenant_id']}/v2.0",
        options={"require": ["exp", "iat", "nbf", "aud", "iss", "oid", "scp", "azp", "tid", "ver"]},
    )
    return token, validate_claims(claims, config)


def extract_profile(result):
    """Accept Graph JSON or the Gateway's HTTP response wrapper, never dump raw results."""
    if result.isError:
        import re
        raw = result.model_dump_json() if hasattr(result, "model_dump_json") else ""
        markers = [name for name in (
            "AccessDenied", "not authorized", "GetWorkloadAccessToken", "GetResourceOauth2Token",
            "GetSecretValue", "InvalidClient", "invalid_client", "invalid_grant", "consent_required",
            "insufficient_scope", "Unauthorized", "ValidationException", "TOKEN_EXCHANGE",
            "JWT_AUTHORIZATION_GRANT", "clientSecret", "jsonKey", "SecretString",
        ) if name.lower() in raw.lower()]
        error = RuntimeError("Gateway tool returned an error")
        error.public_detail = {"stage": "gateway_tool", "markers": markers,
                               "diagnostic_words": diagnostic_words(raw),
                               "entra_codes": sorted(set(re.findall(r"AADSTS\d+", raw))),
                               "aws_actions": sorted(set(re.findall(r"bedrock-agentcore:[A-Za-z]+", raw)))}
        raise error
    candidates = []
    if result.structuredContent:
        candidates.append(result.structuredContent)
    for item in result.content:
        if getattr(item, "type", None) == "text":
            try:
                candidates.append(json.loads(item.text))
            except (TypeError, ValueError):
                pass
    profiles = []
    for candidate in candidates:
        if isinstance(candidate, dict) and "body" in candidate:
            status = candidate.get("statusCode", candidate.get("status", 200))
            if str(status) != "200":
                continue
            candidate = candidate["body"]
            if isinstance(candidate, str):
                candidate = json.loads(candidate)
        if isinstance(candidate, dict) and isinstance(candidate.get("id"), str):
            uuid.UUID(candidate["id"])
            profiles.append({k: candidate.get(k) for k in ("id", "displayName", "userPrincipalName")})
    if not profiles or len({p["id"] for p in profiles}) != 1:
        raise ValueError("Missing or conflicting Graph profile result")
    return profiles[0]


def verify_profile(profile, claims):
    if profile["id"].lower() != claims["oid"].lower():
        raise AssertionError("Graph user does not match the verified inbound user's oid")


async def call_gateway(config, token, claims, extra_argument_test=False):
    async with httpx.AsyncClient(
        headers={"Authorization": "Bearer " + token},
        timeout=120, follow_redirects=False,
    ) as http:
        async with streamable_http_client(
            config["gateway_url"], http_client=http, terminate_on_close=False,
        ) as (read, write, _):
            async with ClientSession(read, write) as session:
                await session.initialize()
                listed = await session.list_tools()
                if listed.nextCursor or [t.name for t in listed.tools] != [config["tool_name"]]:
                    raise AssertionError("Unexpected tools exposed")
                if listed.tools[0].inputSchema.get("properties"):
                    raise AssertionError("The profile tool must not expose input properties")
                result = await session.call_tool(config["tool_name"], {})
                profile = extract_profile(result)
                verify_profile(profile, claims)
                extra_status = "not_run"
                if extra_argument_test:
                    unexpected = await session.call_tool(
                        config["tool_name"], {"user_id": "00000000-0000-0000-0000-000000000000"},
                    )
                    if unexpected.isError:
                        extra_status = "rejected"
                    else:
                        verify_profile(extract_profile(unexpected), claims)
                        extra_status = "ignored_same_user"  # Not strict argument rejection.
                return profile, extra_status


async def rejection_checks(config, token):
    header, payload, signature = token.split(".")
    signature = ("A" if signature[0] != "A" else "B") + signature[1:]
    modified = ".".join([header, payload, signature])
    checks = {}
    async with httpx.AsyncClient(timeout=60,
                                 follow_redirects=False) as http:
        for label, bearer in [("no_token", None), ("malformed_token", "invalid"),
                              ("tampered_signature", modified)]:
            response = await http.post(
                config["gateway_url"],
                headers={} if bearer is None else {"Authorization": "Bearer " + bearer},
                json={"jsonrpc": "2.0", "id": 1, "method": "tools/list"},
            )
            checks[label] = {"status": "passed" if response.status_code in (401, 403) else "failed",
                             "http_status": response.status_code}
    return checks


async def run(args, report):
    config = settings()
    report["region"] = config["aws_region"]
    token_a, claims_a = login(config, "User A")
    profile, _ = await call_gateway(config, token_a, claims_a)
    report["checks"]["gateway_user_a"] = {"status": "passed"}
    if args.show_profile:
        print(json.dumps(profile, ensure_ascii=False))
    if args.two_users:
        token_b, claims_b = login(config, "User B (a DIFFERENT user)")
        if claims_a["oid"] == claims_b["oid"]:
            raise ValueError("Select a different user for User B")
        await call_gateway(config, token_b, claims_b)
        report["checks"]["gateway_user_b"] = {"status": "passed"}
        await call_gateway(config, token_a, claims_a)
        report["checks"]["a_b_a_isolation"] = {"status": "passed"}
    if args.negative:
        report["checks"].update(await rejection_checks(config, token_a))
        _, status = await call_gateway(config, token_a, claims_a, extra_argument_test=True)
        report["checks"]["extra_user_id"] = {"status": status}
    report["outcome"] = ("failed" if any(x["status"] == "failed" for x in report["checks"].values())
                         else "gateway_partial_success_remaining_checks_not_run")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--two-users", action="store_true")
    parser.add_argument("--negative", action="store_true")
    parser.add_argument("--show-profile", action="store_true", help="Print selected PII locally; no tokens")
    parser.add_argument("--report", action="store_true", help="Save checks only under ignored results/")
    args = parser.parse_args()
    report = {"started_at": datetime.now(timezone.utc).isoformat(),
              "versions": {p: importlib.metadata.version(p) for p in ("boto3", "mcp", "msal", "PyJWT")},
              "checks": {k: {"status": "not_run"} for k in (
                  "gateway_user_a", "gateway_user_b", "a_b_a_isolation", "no_token", "malformed_token",
                  "tampered_signature", "extra_user_id", "expired_token", "wrong_audience",
                  "missing_scope", "app_only", "missing_consent", "invalid_outbound_credentials")}}
    try:
        asyncio.run(run(args, report))
    except Exception as error:
        report["failure"] = safe_failure(error)
        report["outcome"] = "failed"
    except KeyboardInterrupt:
        report["outcome"] = "interrupted"
    report["finished_at"] = datetime.now(timezone.utc).isoformat()
    text = json.dumps(report, indent=2, ensure_ascii=False)
    print(text)
    if args.report:
        folder = ROOT / "results"
        folder.mkdir(exist_ok=True)
        (folder / f"verification-{datetime.now(timezone.utc):%Y%m%dT%H%M%S%fZ}.json").write_text(text + "\n", encoding="utf-8")
    return 1 if report["outcome"] in ("failed", "interrupted") else 0


if __name__ == "__main__":
    raise SystemExit(main())
