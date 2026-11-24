"""Gatewayが検証したJWTを使用する。単独のJWT検証器としては使わない。"""
import base64
import copy
import json
import os
import time


def identity(headers):
    headers = {key.lower(): value for key, value in headers.items()}
    scheme, token = headers.get('authorization', '').split(' ', 1)
    if scheme.lower() != 'bearer':
        raise ValueError('Bearer token required')
    parts = token.split('.')
    if len(parts) != 3:
        raise ValueError('Invalid token')
    claims = json.loads(base64.urlsafe_b64decode(parts[1] + '=' * (-len(parts[1]) % 4)))
    tenant, email = claims.get('tenant_id'), claims.get('acl_email')
    if (claims.get('iss') != os.environ['COGNITO_ISSUER']
            or claims.get('client_id') != os.environ['COGNITO_CLIENT_ID']
            or claims.get('token_use') != 'access'
            or claims.get('exp', 0) <= time.time()
            or os.environ['INVOKE_SCOPE'] not in claims.get('scope', '').split()
            or tenant not in json.loads(os.environ['ALLOWED_TENANTS'])
            or not isinstance(email, str) or '@' not in email):
        raise ValueError('Invalid identity context')
    return tenant, email


def reject(body, message):
    return {'interceptorOutputVersion': '1.0', 'mcp': {
        'transformedGatewayResponse': {'statusCode': 200, 'body': {
            'jsonrpc': '2.0', 'id': body.get('id'),
            'error': {'code': -32602, 'message': message},
        }}
    }}


def handler(event, context):
    request = event['mcp']['gatewayRequest']
    body = copy.deepcopy(request['body'])
    if isinstance(body, str):
        body = json.loads(body)
    if not isinstance(body, dict):
        raise ValueError('JSON-RPC object required')
    # initialize・tools/listなどを検索リクエストとして扱わない。
    if body.get('method') != 'tools/call':
        return {'interceptorOutputVersion': '1.0', 'mcp': {
            'transformedGatewayRequest': {'body': body}}}
    try:
        tenant, email = identity(request.get('headers', {}))
        params = body['params']
        if params.get('name') != os.environ['TOOL_NAME']:
            return reject(body, 'Unsupported tool')
        args = params.get('arguments', {})
        query = args.get('retrievalQuery', {}).get('text')
        if not isinstance(query, str) or not query.strip() or len(query) > 4000:
            return reject(body, 'A query of 1-4000 characters is required')
    except (ValueError, TypeError, KeyError, AttributeError):
        return reject(body, 'Verified tenant and user context are required')
    # 引数を再構築する。任意フィルター・userContext・KB ID・nextTokenは引き継がない。
    params['arguments'] = {
        'retrievalQuery': {'text': query},
        'retrievalConfiguration': {'managedSearchConfiguration': {
            'filter': {'equals': {'key': 'tenant_id', 'value': tenant}},
        }},
        'userContext': {'userId': email},
    }
    # JWT、メール、質問・文書本文はログへ出さない。
    print(json.dumps({'decision': 'SCOPED', 'tenant_id': tenant,
                      'tool': params['name'], 'request_id': getattr(context, 'aws_request_id', None)}))
    return {'interceptorOutputVersion': '1.0', 'mcp': {
        'transformedGatewayRequest': {'body': body}}}
