"""Select tenant-scoped credentials from server-owned configuration."""
import re
import uuid
import boto3
from botocore.config import Config

SDK_CONFIG = Config(connect_timeout=5, read_timeout=20, retries={'max_attempts': 2})


def read_inquiry(tenant_id, ticket_id, tenants, region):
    if not isinstance(tenant_id, str) or tenant_id not in tenants:
        raise PermissionError('Missing or unknown tenant')
    if not isinstance(ticket_id, str) or not re.fullmatch(r'T[0-9]{3}', ticket_id):
        raise ValueError('Expected a ticket ID such as T001')
    target = tenants[tenant_id]
    sts = boto3.client('sts', region_name=region, config=SDK_CONFIG)
    credentials = sts.assume_role(
        RoleArn=target['role_arn'], RoleSessionName=f'inquiry-{uuid.uuid4().hex}',
        DurationSeconds=900)['Credentials']
    # Credentials and clients are request-local, never written to os.environ.
    dynamodb = boto3.client('dynamodb', region_name=region, config=SDK_CONFIG,
        aws_access_key_id=credentials['AccessKeyId'],
        aws_secret_access_key=credentials['SecretAccessKey'],
        aws_session_token=credentials['SessionToken'])
    item = dynamodb.get_item(TableName=target['table_name'],
                            Key={'ticket_id': {'S': ticket_id}}).get('Item')
    if item is None:
        return {'ticket_id': ticket_id, 'found': False}
    return {'ticket_id': ticket_id, 'found': True, 'text': item['text']['S']}
