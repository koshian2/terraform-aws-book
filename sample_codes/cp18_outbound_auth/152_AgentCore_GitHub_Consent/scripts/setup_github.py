"""Configure GitHub App credentials via Terraform write-only values."""
from common import ROOT, settings, terraform
import argparse
import getpass
import json
import os
import subprocess


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--configure', action='store_true')
    args = p.parse_args()
    config = settings()
    print('GitHub App callback URL:', config['github_callback'])
    print('Managed consent portal:', config['portal_url'])
    if not args.configure:
        return
    client_id = input('GitHub App Client ID: ').strip()
    if not client_id:
        raise SystemExit('Client ID is required')
    secret = getpass.getpass('GitHub App Client Secret (not the .pem): ').strip()
    if not secret:
        raise SystemExit('Client Secret is required')
    path = ROOT / "terraform" / 'github.auto.tfvars.json'
    previous = json.loads(path.read_text()) if path.exists() else {}
    path.write_text(json.dumps({'github_client_id': client_id,
        'github_credentials_version': previous.get('github_credentials_version', 1) + 1}, indent=2) + '\n')
    env = dict(os.environ, TF_VAR_github_client_secret=secret)
    try:
        subprocess.run([terraform(), 'apply'], cwd=ROOT / "terraform", env=env, check=True)
    finally:
        env.pop('TF_VAR_github_client_secret', None)


if __name__ == '__main__':
    main()
