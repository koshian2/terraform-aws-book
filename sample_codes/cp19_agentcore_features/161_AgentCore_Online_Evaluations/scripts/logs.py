"""Runtimeが自動作成するロググループとの競合を避け、保持期間を設定する。"""
import os
import boto3

logs = boto3.client("logs")
group = os.environ["DEMO_LOG_GROUP"]
try:
    logs.create_log_group(logGroupName=group)
except logs.exceptions.ResourceAlreadyExistsException:
    pass
logs.put_retention_policy(logGroupName=group, retentionInDays=7)
print(f"Ready: {group}")
