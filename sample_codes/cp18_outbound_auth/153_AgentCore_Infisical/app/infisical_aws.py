"""Authenticate with IAM's temporary credentials; return only a fixed demo value."""
import base64
import json
import re
from urllib.parse import quote

import boto3
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest
import httpx


class InfisicalError(Exception):
    """Bounded error without request headers, tokens or response bodies."""


def encode(value):
    return base64.b64encode(value.encode()).decode()


def aws_login_payload(identity_id, region, credentials):
    if not re.fullmatch(r"[a-z]{2}(?:-[a-z]+)+-\d", region):
        raise ValueError("Invalid AWS region")
    endpoint = f"https://sts.{region}.amazonaws.com/"
    request = AWSRequest(
        method="POST", url=endpoint,
        data="Action=GetCallerIdentity&Version=2011-06-15",
        headers={"Content-Type": "application/x-www-form-urlencoded; charset=utf-8",
                 "Host": f"sts.{region}.amazonaws.com"},
    )
    SigV4Auth(credentials, "sts", region).add_auth(request)
    return {
        "identityId": identity_id,
        "iamHttpRequestMethod": "POST",
        "iamRequestUrl": encode(endpoint),
        "iamRequestBody": encode(request.data),
        "iamRequestHeaders": encode(json.dumps(dict(request.headers.items()))),
    }


def checked_json(response, operation):
    if response.status_code != 200:
        raise InfisicalError(f"{operation} failed (HTTP {response.status_code})")
    try:
        value = response.json()
        if not isinstance(value, dict):
            raise ValueError()
        return value
    except ValueError:
        raise InfisicalError(f"{operation} returned invalid JSON") from None


def get_demo_message(host, identity_id, project_id, region, *, session=None, http=None):
    # No caller-supplied host, project, environment or secret name from MCP.
    if host not in {"https://app.infisical.com", "https://us.infisical.com", "https://eu.infisical.com"}:
        raise InfisicalError("Unsupported Infisical host")
    session = session or boto3.Session()
    credentials = session.get_credentials()
    if credentials is None:
        raise InfisicalError("AWS credentials are unavailable")
    payload = aws_login_payload(identity_id, region, credentials.get_frozen_credentials())
    if http is None:
        with httpx.Client(timeout=20, follow_redirects=False) as client:
            return fetch_message(client, host, project_id, payload)
    return fetch_message(http, host, project_id, payload)


def fetch_message(http, host, project_id, payload):
    # No shared cache and no disk persistence of the Infisical access token.
    login = checked_json(http.post(host + "/api/v1/auth/aws-auth/login", json=payload), "AWS Auth")
    token = login.get("accessToken")
    if not isinstance(token, str) or not token:
        raise InfisicalError("AWS Auth returned no access token")
    result = checked_json(http.get(
        host + "/api/v4/secrets/" + quote("DEMO_MESSAGE", safe=""),
        headers={"Authorization": "Bearer " + token},
        params={"projectId": project_id, "environment": "dev", "secretPath": "/",
                "expandSecretReferences": "false", "includeImports": "false"},
    ), "Secret read")
    secret = result.get("secret", {})
    if (not isinstance(secret, dict) or secret.get("secretKey") != "DEMO_MESSAGE"
            or secret.get("secretValueHidden") is True
            or not isinstance(secret.get("secretValue"), str)):
        raise InfisicalError("Demo secret is unavailable")
    return {"status": "ok", "name": "DEMO_MESSAGE", "message": secret["secretValue"]}
