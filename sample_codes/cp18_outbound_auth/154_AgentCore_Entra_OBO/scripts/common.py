"""Public configuration. Never persist token caches."""
import json
import logging
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
# Do not let SDK/protocol debug logs serialize credentials or OAuth responses.
logging.disable(logging.CRITICAL)


def settings():
    result = subprocess.run(
        ["terraform", "output", "-json", "client_config"], cwd=ROOT / "terraform",
        capture_output=True, text=True, encoding="utf-8", timeout=30,
    )
    if result.returncode:
        raise RuntimeError("Terraform outputs unavailable; apply the reviewed plan first")
    config = json.loads(result.stdout)
    validate_gateway_url(config["gateway_url"], config["aws_region"])
    return config


def validate_gateway_url(url, region):
    from urllib.parse import urlsplit
    parsed = urlsplit(url)
    suffix = f".gateway.bedrock-agentcore.{region}.amazonaws.com"
    if (parsed.scheme != "https" or not (parsed.hostname or "").endswith(suffix)
            or parsed.username or parsed.password or parsed.port not in (None, 443)
            or parsed.query or parsed.fragment or parsed.path != "/mcp"):
        raise ValueError("Unexpected Gateway URL; refusing to send user token")


def diagnostic_words(text):
    """Emit only fixed vocabulary, never arbitrary text from remote responses."""
    import re
    vocabulary = set("failed failure error unable cannot could not to the a an is are be was were has have been with without for of on in from and or must required invalid missing unsupported token access refresh user workload identity oauth provider credential credentials secret client configuration grant exchange scope scopes jwt authorization authentication resource request response target graph external managed internal server service permission permissions denied insufficient expired signature audience issuer claim claims does exist found enabled disabled supported flow session name value json key parse parsing retrieve obtain get validate validation process processing only currently provided empty format secretstring clientsecret default passthrough http status bearer exception before after create update retrieve retrieval rejected forbidden unauthorized timeout unknown configurationerror credentialserror".split())
    return [word for word in re.findall(r"\b[a-zA-Z]+\b", str(text).lower()) if word in vocabulary][:100]


def safe_failure(error):
    # Exception bodies may contain HTTP headers or token endpoint responses.
    result = {"status": "failed", "error_type": type(error).__name__}
    if isinstance(error, BaseExceptionGroup):
        result["causes"] = [safe_failure(child) for child in error.exceptions]
    if getattr(error, "public_detail", None):
        result["detail"] = error.public_detail
    response = getattr(error, "response", None)
    if isinstance(response, dict):
        result["aws_error_code"] = response.get("Error", {}).get("Code", "unknown")
        result["request_id"] = response.get("ResponseMetadata", {}).get("RequestId")
        result["diagnostic_words"] = diagnostic_words(response.get("Error", {}).get("Message", ""))
    elif hasattr(response, "status_code"):
        result["http_status"] = response.status_code
        result["request_id"] = response.headers.get("x-amzn-requestid")
        # Only OAuth error identifiers; never raw headers, URLs or response bodies.
        import re
        matched = re.search(r'error="([a-z_]+)"', response.headers.get("www-authenticate", ""))
        if matched:
            result["oauth_error"] = matched.group(1)
    if error.__cause__ is not None and not isinstance(error, BaseExceptionGroup):
        result["cause"] = safe_failure(error.__cause__)
    return result
