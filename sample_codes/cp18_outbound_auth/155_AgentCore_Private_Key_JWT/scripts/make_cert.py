"""Build a public X.509 certificate using KMS. No local private key is generated."""
import argparse
import base64
from datetime import datetime, timedelta, timezone
import hashlib
import json
from pathlib import Path
import secrets

import common
import boto3
from asn1crypto import algos, keys, pem, x509
from cryptography import x509 as crypto_x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding


def create_certificate(kms, key_arn, label, days=90):
    if label not in ("obo", "m2m") or not 1 <= days <= 365:
        raise ValueError("Use obo/m2m and 1..365 days")
    metadata = kms.get_public_key(KeyId=key_arn)
    if metadata["KeyUsage"] != "SIGN_VERIFY" or metadata["KeySpec"] != "RSA_2048":
        raise ValueError("Expected an RSA_2048 SIGN_VERIFY key")
    public_der = metadata["PublicKey"]
    name = x509.Name.build({"common_name": "entra-graph-pkjwt-" + label})
    now = datetime.now(timezone.utc).replace(microsecond=0)
    # X.509 certificate signature is PKCS#1 SHA256. JWT assertions use PS256.
    algorithm = algos.SignedDigestAlgorithm({"algorithm": "sha256_rsa"})
    tbs = x509.TbsCertificate({
        "version": "v3", "serial_number": secrets.randbits(159) or 1,
        "signature": algorithm, "issuer": name, "subject": name,
        "validity": {"not_before": x509.Time({"utc_time": now - timedelta(minutes=5)}),
                     "not_after": x509.Time({"utc_time": now + timedelta(days=days)})},
        "subject_public_key_info": keys.PublicKeyInfo.load(public_der),
        "extensions": [
            {"extn_id": "basic_constraints", "critical": True, "extn_value": {"ca": False}},
            {"extn_id": "key_usage", "critical": True, "extn_value": {"digital_signature"}},
        ],
    })
    signed = kms.sign(KeyId=key_arn, Message=hashlib.sha256(tbs.dump()).digest(),
                      MessageType="DIGEST", SigningAlgorithm="RSASSA_PKCS1_V1_5_SHA_256")
    der = x509.Certificate({"tbs_certificate": tbs, "signature_algorithm": algorithm,
                            "signature_value": signed["Signature"]}).dump()
    certificate = crypto_x509.load_der_x509_certificate(der)
    certificate.public_key().verify(certificate.signature, certificate.tbs_certificate_bytes,
                                    padding.PKCS1v15(), hashes.SHA256())
    if certificate.public_key().public_bytes(serialization.Encoding.DER,
            serialization.PublicFormat.SubjectPublicKeyInfo) != public_der:
        raise ValueError("Certificate public key does not match KMS")
    thumbprint = base64.urlsafe_b64encode(hashlib.sha256(der).digest()).rstrip(b"=").decode()
    return der, thumbprint


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--label", choices=["obo", "m2m"], required=True)
    parser.add_argument("--key-arn", required=True)
    parser.add_argument("--profile", default="develop")
    parser.add_argument("--region", default="ap-northeast-1")
    parser.add_argument("--days", type=int, default=90)
    args = parser.parse_args()
    if args.key_arn.split(":")[3] != args.region:
        raise ValueError("KMS key must be in the configured region")
    folder = common.ROOT / "certificates"
    outputs = [folder / (args.label + suffix) for suffix in (".cer", ".pem", ".json")]
    if any(p.exists() for p in outputs):
        raise FileExistsError("Certificate already exists; choose a reviewed rotation workflow")
    kms = boto3.Session(profile_name=args.profile, region_name=args.region).client("kms")
    der, thumbprint = create_certificate(kms, args.key_arn, args.label, args.days)
    folder.mkdir(exist_ok=True)
    outputs[0].write_bytes(der)
    outputs[1].write_bytes(pem.armor("CERTIFICATE", der))
    outputs[2].write_text(json.dumps({"x5t#S256": thumbprint}, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"certificate": str(outputs[0]), "signature_verified": True,
                      "x5t#S256": thumbprint}))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(json.dumps(common.safe_failure(error)))
        raise SystemExit(1)
