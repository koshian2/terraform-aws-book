"""Extract ONLY the inbound JWT validated by this Gateway's CUSTOM_JWT authorizer.

This Lambda is not a standalone JWT verifier. Its configured entry point must
remain the authenticated Gateway; never reuse decoding as authentication.
"""
import base64
import json
import os
import time

HEADER = 'X-Amzn-Bedrock-AgentCore-Runtime-Custom-Tenant-Id'


def handler(event, context):
    request = event['mcp']['gatewayRequest']
    headers = {k.lower(): v for k, v in request.get('headers', {}).items()}
    try:
        bearer = headers.get('authorization', '')
        scheme, token = bearer.split(' ', 1)
        if scheme.lower() != 'bearer':
            raise ValueError()
        parts = token.split('.')
        if len(parts) != 3:
            raise ValueError()
        claims = json.loads(base64.urlsafe_b64decode(parts[1] + '=' * (-len(parts[1]) % 4)))
        tenant = claims.get('tenant_id')
        if (claims.get('iss') != os.environ['COGNITO_ISSUER']
                or claims.get('client_id') != os.environ['COGNITO_CLIENT_ID']
                or claims.get('token_use') != 'access'
                or claims.get('exp', 0) <= time.time()
                or os.environ['INVOKE_SCOPE'] not in claims.get('scope', '').split()
                or not isinstance(tenant, str)
                or tenant not in json.loads(os.environ['ALLOWED_TENANTS'])):
            raise ValueError()
    except (ValueError, TypeError, KeyError):
        raise ValueError('Invalid tenant context') from None
    # Return only the trusted value. Gateway gives this precedence over caller headers.
    return {'interceptorOutputVersion': '1.0', 'mcp': {
        'transformedGatewayRequest': {'body': request['body'], 'headers': {HEADER: tenant}}
    }}
