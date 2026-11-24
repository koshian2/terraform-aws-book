"""Create a demo user without putting their password into Terraform state."""
import argparse
import getpass

import boto3

from common import settings


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--username", required=True)
    parser.add_argument("--group", choices=["regular", "vip"], required=True)
    args = parser.parse_args()
    config = settings()
    password = getpass.getpass("New password (12+ chars, upper/lowercase, digit, symbol): ")
    if password != getpass.getpass("Confirm password: "):
        raise SystemExit("Passwords do not match")
    client = boto3.Session(profile_name=config["aws_profile"], region_name=config["aws_region"]).client("cognito-idp")
    try:
        client.admin_create_user(UserPoolId=config["user_pool_id"], Username=args.username, MessageAction="SUPPRESS")
    except client.exceptions.UsernameExistsException:
        raise SystemExit("User already exists. Use the existing password or reset it in the Cognito console.")
    try:
        client.admin_set_user_password(UserPoolId=config["user_pool_id"], Username=args.username, Password=password, Permanent=True)
    except Exception:
        print("User created but password setup failed. Reset the password in the Cognito console.")
        raise
    client.admin_add_user_to_group(UserPoolId=config["user_pool_id"], Username=args.username, GroupName=args.group)
    print(f"Created user: {args.username}, group: {args.group}")


if __name__ == "__main__":
    main()
