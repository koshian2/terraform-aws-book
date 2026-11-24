"""Validate a local GitHub App key and apply it via Terraform ephemeral/write-only input."""
import argparse
import asyncio
import json
import os
from pathlib import Path
import subprocess

from cryptography.hazmat.primitives.serialization import load_pem_private_key
from cryptography.hazmat.primitives.asymmetric.rsa import RSAPrivateKey
from common import ROOT, settings
import sys
sys.path.insert(0, str(ROOT / "app"))
from github_app import discover_installation, GitHubError


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--key-file", help="Local PEM path, never the key contents")
    parser.add_argument("--client-id", help="GitHub App Client ID or App ID (not Client Secret)")
    args = parser.parse_args()
    config = settings()
    client_id = args.client_id or config["github_client_id"]
    if client_id == "pending-registration":
        client_id = input("GitHub App Client ID: ").strip()
    path = Path(args.key_file or input("Local private key (.pem) path: ").strip().strip('"')).expanduser()
    pem = path.read_text(encoding="utf-8")
    key = load_pem_private_key(pem.encode(), password=None)
    if not isinstance(key, RSAPrivateKey):
        raise SystemExit("GitHub App requires an RSA private key")
    installation_id = asyncio.run(discover_installation(client_id, pem, config["github_repository"]))
    print("Verified App installation:", installation_id, "repository:", config["github_repository"])
    target = ROOT / "terraform" / "github.auto.tfvars.json"
    old = json.loads(target.read_text(encoding="utf-8")) if target.exists() else {}
    public = {"github_client_id": client_id, "github_installation_id": installation_id,
              "github_key_version": old.get("github_key_version", 0) + 1}
    target.write_text(json.dumps(public, indent=2) + "\n", encoding="utf-8")
    env = dict(os.environ, TF_VAR_github_private_key=pem)
    try:
        subprocess.run(["terraform", "apply"], cwd=ROOT / "terraform", env=env, check=True)
    finally:
        env.pop("TF_VAR_github_private_key", None)


if __name__ == "__main__":
    try:
        main()
    except GitHubError as error:
        raise SystemExit(str(error)) from None
