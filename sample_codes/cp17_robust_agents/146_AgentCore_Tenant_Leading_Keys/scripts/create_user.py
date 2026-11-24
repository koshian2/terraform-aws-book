"""Create a demo user without putting their password into Terraform state."""
import argparse
import getpass

import boto3

from common import settings


def existing_user(client, pool_id, username, tenant):
    try:
        user = client.admin_get_user(UserPoolId=pool_id, Username=username)
    except client.exceptions.UserNotFoundException:
        return False
    attributes = {item["Name"]: item["Value"] for item in user["UserAttributes"]}
    if attributes.get("custom:tenant_id") != tenant:
        raise SystemExit(f"Existing user {username} belongs to a different tenant; no changes made.")
    if not user.get("Enabled") or user.get("UserStatus") != "CONFIRMED":
        raise SystemExit(f"Existing user {username} is not ready for login. Check their status/password in Cognito.")
    print(f"Skipped existing user: {username} ({tenant}). Use the existing password.")
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--username", required=True)
    parser.add_argument("--tenant", required=True, choices=["tenant-a", "tenant-b"])
    args = parser.parse_args()
    config = settings()
    client = boto3.Session(profile_name=config["aws_profile"], region_name=config["aws_region"]).client("cognito-idp")
    if existing_user(client, config["user_pool_id"], args.username, args.tenant):
        return
    password = getpass.getpass("New password (12+ chars, upper/lowercase, digit, symbol): ")
    if password != getpass.getpass("Confirm password: "):
        raise SystemExit("Passwords do not match")
    try:
        client.admin_create_user(UserPoolId=config["user_pool_id"], Username=args.username, MessageAction="SUPPRESS",
                                  UserAttributes=[{"Name": "custom:tenant_id", "Value": args.tenant}])
    except client.exceptions.UsernameExistsException:
        if existing_user(client, config["user_pool_id"], args.username, args.tenant):
            return
        raise
    try:
        client.admin_set_user_password(UserPoolId=config["user_pool_id"], Username=args.username, Password=password, Permanent=True)
    except Exception:
        print("User created but password setup failed. Reset the password in the Cognito console.")
        raise
    print(f"Created user: {args.username}")


if __name__ == "__main__":
    main()
