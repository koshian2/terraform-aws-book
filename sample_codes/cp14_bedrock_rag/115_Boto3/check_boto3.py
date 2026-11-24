import boto3

session = boto3.Session(profile_name="develop")
identity = session.client("sts").get_caller_identity()
print(identity["Account"])
