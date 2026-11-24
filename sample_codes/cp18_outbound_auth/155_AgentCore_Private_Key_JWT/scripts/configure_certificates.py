"""Create public certificates and save their public references for Terraform."""
import argparse
import base64
import hashlib
import json
import subprocess
import boto3
from asn1crypto import pem
from cryptography import x509
from cryptography.hazmat.primitives import serialization
from datetime import datetime, timezone
from common import ROOT
from make_cert import create_certificate

def output(name):
    result = subprocess.run(["terraform", "output", "-json", name], cwd=ROOT / "terraform/keys",
        check=True, capture_output=True, text=True, encoding="utf-8")
    return json.loads(result.stdout)

def main():
    argparse.ArgumentParser(description=__doc__).parse_args()
    keys, cfg = output("key_arns"), output("settings")
    kms = boto3.Session(profile_name=cfg["aws_profile"], region_name=cfg["aws_region"]).client("kms")
    folder = ROOT / "certificates"
    folder.mkdir(exist_ok=True)
    thumbs = {}
    for label, arn in keys.items():
        path = folder / f"{label}.cer"
        if path.exists():
            der = path.read_bytes()
            cert = x509.load_der_x509_certificate(der)
            public = cert.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
            if public != kms.get_public_key(KeyId=arn)["PublicKey"] or cert.not_valid_after_utc <= datetime.now(timezone.utc):
                raise RuntimeError("Existing certificate is expired or belongs to another key; review certificate rotation")
            thumb = base64.urlsafe_b64encode(hashlib.sha256(der).digest()).rstrip(b"=").decode()
        else:
            der, thumb = create_certificate(kms, arn, label)
            path.write_bytes(der)
            (folder / f"{label}.pem").write_bytes(pem.armor("CERTIFICATE", der))
        thumbs[label] = thumb
        print(f"Entraの{label}アプリへ登録: {path}")
    (ROOT / "terraform/certificates.auto.tfvars.json").write_text(json.dumps({
        "key_arns": keys, "certificate_thumbprints": thumbs,
        "aws_profile": cfg["aws_profile"], "aws_region": cfg["aws_region"]}, indent=2) + "\n", encoding="utf-8")

if __name__ == "__main__":
    main()
