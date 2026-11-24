"""Feed the generated public portal Client ID back into Gateway JWT settings."""
from common import ROOT, settings, terraform
import argparse
import json
import os
import subprocess


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--auto-approve', action='store_true')
    args = p.parse_args()
    config = settings()
    (ROOT / "terraform" / 'portal.auto.tfvars.json').write_text(json.dumps({'portal_client_id': config['portal_client_id']}, indent=2) + '\n')
    command = [terraform(), 'apply', '-input=false']
    if args.auto_approve:
        command.append('-auto-approve')
    subprocess.run(command, cwd=ROOT / "terraform", env=os.environ.copy(), check=True)


if __name__ == '__main__':
    main()
