"""Use a shared reader role, with per-request tenant session tags."""
import re
import uuid
import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

SDK_CONFIG = Config(connect_timeout=5, read_timeout=20, retries={'max_attempts': 2})


def tenant_client(tenant_id, tenants, region, role_arn):
    if not isinstance(tenant_id, str) or tenant_id not in tenants:
        raise PermissionError('Missing or unknown tenant')
    sts = boto3.client('sts', region_name=region, config=SDK_CONFIG)
    credentials = sts.assume_role(
        RoleArn=role_arn, RoleSessionName=f'inquiry-{uuid.uuid4().hex}',
        DurationSeconds=900, Tags=[{'Key': 'TenantId', 'Value': tenant_id}])['Credentials']
    # No process-global credential mutation or cross-tenant cache.
    return boto3.client('dynamodb', region_name=region, config=SDK_CONFIG,
        aws_access_key_id=credentials['AccessKeyId'],
        aws_secret_access_key=credentials['SecretAccessKey'],
        aws_session_token=credentials['SessionToken'])


def read_inquiry(tenant_id, ticket_id, tenants, region, role_arn, table_name):
    if not isinstance(ticket_id, str) or not re.fullmatch(r'T[0-9]{3}', ticket_id):
        raise ValueError('Expected a ticket ID such as T001')
    dynamodb = tenant_client(tenant_id, tenants, region, role_arn)
    item = dynamodb.get_item(TableName=table_name,
                            Key={'tenant_id': {'S': tenant_id}, 'ticket_id': {'S': ticket_id}}).get('Item')
    if item is None:
        return {'ticket_id': ticket_id, 'found': False}
    return {'ticket_id': ticket_id, 'found': True, 'text': item['text']['S']}


def require_denied(call):
    try:
        call()
    except ClientError as error:
        if error.response['Error']['Code'] not in ('AccessDenied', 'AccessDeniedException'):
            raise RuntimeError('Expected AccessDenied, not another service error') from None
    else:
        raise RuntimeError('Isolation violation: forbidden operation succeeded')


def verify_isolation(tenant_id, tenants, region, role_arn, table_name):
    """Only fixed demo resources; never return other tenants' response bodies.

This diagnostic intentionally tries a foreign partition key with the SAME credentials,
so an application-level routing check cannot masquerade as IAM isolation.
"""
    dynamodb = tenant_client(tenant_id, tenants, region, role_arn)
    own = dynamodb.get_item(TableName=table_name,
                           Key={'tenant_id': {'S': tenant_id}, 'ticket_id': {'S': 'T001'}})
    if 'Item' not in own:
        raise RuntimeError('Own demo item missing')
    others = [tenant for tenant in tenants if tenant != tenant_id]
    if not others:
        raise RuntimeError('Another demo tenant is required for this check')
    for target in others:
        require_denied(lambda: dynamodb.get_item(TableName=table_name,
                         Key={'tenant_id': {'S': target}, 'ticket_id': {'S': 'T001'}}))
    # Scan cannot be used to bypass key-scoped access. Never return its data.
    require_denied(lambda: dynamodb.scan(TableName=table_name, Limit=1))
    sts = boto3.client('sts', region_name=region, config=SDK_CONFIG)
    common = {'RoleArn': role_arn, 'RoleSessionName': f'negative-{uuid.uuid4().hex}', 'DurationSeconds': 900}
    require_denied(lambda: sts.assume_role(**common))
    # Runtime's normal path blocks unknown tenants before STS. This diagnostic
    # bypasses that local guard to verify the actual IAM trust condition.
    require_denied(lambda: sts.assume_role(**common, Tags=[{'Key': 'TenantId', 'Value': 'unknown-demo-tenant'}]))
    return {'status': 'pass', 'own_partition_readable': True, 'other_partitions_denied': True,
            'scan_denied': True, 'missing_tag_denied': True, 'unknown_tag_denied': True}
