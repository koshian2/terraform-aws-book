"""CloudFormation lifecycle only; never handles end-user consent requests.

Owns a dedicated Cognito client, primary OIDC provider, and consent portal as
one resource to resolve the generated callback URL dependency. No secrets are
returned to CloudFormation or logged. Bundles a pinned SDK for the new APIs.
"""
import hashlib
import json
import time
import urllib.request

import boto3
from botocore.exceptions import ClientError


def resource_name(event):
    p = event['ResourceProperties']
    key = '|'.join([event['StackId'], event['LogicalResourceId'], p['Name'],
                    p['GatewayId'], p['UserPoolId']])
    return p['Name'][:30] + '-' + hashlib.sha256(key.encode()).hexdigest()[:12]


def find_portal(api, name):
    token = None
    while True:
        page = api.list_consent_portals(**({'nextToken': token} if token else {}))
        for item in page.get('consentPortals', []):
            if item['name'] == name:
                return api.get_consent_portal(consentPortalIdentifier=item['consentPortalId'])
        token = page.get('nextToken')
        if not token:
            return None


def find_client(cognito, pool, name):
    token = None
    while True:
        page = cognito.list_user_pool_clients(UserPoolId=pool, MaxResults=60,
                                              **({'NextToken': token} if token else {}))
        for item in page['UserPoolClients']:
            if item['ClientName'] == name:
                return cognito.describe_user_pool_client(UserPoolId=pool, ClientId=item['ClientId'])['UserPoolClient']
        token = page.get('NextToken')
        if not token:
            return None


def missing(exc):
    return isinstance(exc, ClientError) and exc.response['Error']['Code'] == 'ResourceNotFoundException'


def create_after_iam_propagation(call, **kwargs):
    # The role policy is deployed just before the stack. Bound retries strictly;
    # a persistent denial is returned to CloudFormation, never ignored.
    for attempt in range(13):
        try:
            return call(**kwargs)
        except ClientError as exc:
            if exc.response['Error']['Code'] != 'AccessDeniedException' or attempt == 12:
                raise
            time.sleep(5)


def wait_portal(api, identifier, deadline, deleting=False):
    while time.monotonic() < deadline:
        try:
            portal = api.get_consent_portal(consentPortalIdentifier=identifier)
        except ClientError as exc:
            if deleting and missing(exc):
                return None
            raise
        if not deleting:
            if portal['status'] == 'ACTIVE' and portal.get('portalUrl'):
                return portal
            if portal['status'] in ('FAILED', 'UPDATE_FAILED'):
                raise RuntimeError('Portal entered ' + portal['status'])
        time.sleep(3)
    raise TimeoutError('Portal lifecycle wait timed out')


def client_settings(pool, name, callback, scopes=None):
    return dict(UserPoolId=pool, ClientName=name, AllowedOAuthFlowsUserPoolClient=True,
                AllowedOAuthFlows=['code'], AllowedOAuthScopes=scopes or ['openid'],
                CallbackURLs=[callback], DefaultRedirectURI=callback,
                SupportedIdentityProviders=['COGNITO'],
                ExplicitAuthFlows=['ALLOW_REFRESH_TOKEN_AUTH'],
                PreventUserExistenceErrors='ENABLED', EnableTokenRevocation=True,
                AccessTokenValidity=60, IdTokenValidity=60, RefreshTokenValidity=1,
                TokenValidityUnits={'AccessToken': 'minutes', 'IdToken': 'minutes', 'RefreshToken': 'days'})


def remove(api, cognito, p, name, deadline):
    portal = find_portal(api, name)
    if portal:
        if portal['status'] != 'DELETING':
            api.delete_consent_portal(consentPortalIdentifier=portal['consentPortalId'])
        wait_portal(api, portal['consentPortalId'], deadline, deleting=True)
    try:
        api.delete_oauth2_credential_provider(name=name + '-oidc')
    except ClientError as exc:
        if not missing(exc):
            raise
    try:
        app = find_client(cognito, p['UserPoolId'], name)
        if app:
            cognito.delete_user_pool_client(UserPoolId=p['UserPoolId'], ClientId=app['ClientId'])
    except ClientError as exc:
        if not missing(exc):
            raise


def provision(api, cognito, p, name, deadline, stack_id):
    scopes = ['openid'] + ([p['InvokeScope']] if p.get('InvokeScope') else [])
    app = find_client(cognito, p['UserPoolId'], name)
    if not app:
        # Bootstrap URI is replaced before the custom resource reports SUCCESS.
        app = cognito.create_user_pool_client(GenerateSecret=True,
            **client_settings(p['UserPoolId'], name, 'http://localhost:8765/callback', scopes))['UserPoolClient']
    provider_config = {'customOauth2ProviderConfig': {
        'clientId': app['ClientId'], 'clientSecret': app['ClientSecret'],
        'clientAuthenticationMethod': 'CLIENT_SECRET_BASIC',
        'oauthDiscovery': {'discoveryUrl': p['Issuer'] + '/.well-known/openid-configuration'}}}
    try:
        provider = api.get_oauth2_credential_provider(name=name + '-oidc')
        actual = provider.get('oauth2ProviderConfigOutput', {}).get('customOauth2ProviderConfig', {})
        if actual.get('clientAuthenticationMethod') != 'CLIENT_SECRET_BASIC':
            provider = api.update_oauth2_credential_provider(name=name + '-oidc',
                credentialProviderVendor='CustomOauth2', oauth2ProviderConfigInput=provider_config)
    except ClientError as exc:
        if not missing(exc):
            raise
        provider = create_after_iam_propagation(api.create_oauth2_credential_provider, name=name + '-oidc',
            credentialProviderVendor='CustomOauth2', oauth2ProviderConfigInput=provider_config)
    # Tag after creation: creation-time tagging checks a wildcard ARN without
    # passing RequestTag context. Explicit TagResource checks both the provider
    # ARN and its parent Token Vault; the manager role must allow both.
    api.tag_resource(resourceArn=provider['credentialProviderArn'],
        tags={'Project': 'agentcore-github-consent-portal', 'StackId': stack_id})
    idp = {'credentialProviderArn': provider['credentialProviderArn'], 'scopes': scopes}
    portal = find_portal(api, name)
    if not portal:
        portal = create_after_iam_propagation(api.create_consent_portal, name=name, executionRoleArn=p['ExecutionRoleArn'],
            idpConfig=idp, sources=[{'type': 'agentcore-gateway', 'identifier': p['GatewayId']}])
    else:
        portal = wait_portal(api, portal['consentPortalId'], deadline)
        if portal['executionRoleArn'] != p['ExecutionRoleArn'] or portal['idpConfig'] != idp:
            portal = api.update_consent_portal(consentPortalIdentifier=portal['consentPortalId'],
                executionRoleArn=p['ExecutionRoleArn'], idpConfig=idp)
    portal = wait_portal(api, portal['consentPortalId'], deadline)
    api.tag_resource(resourceArn=portal['consentPortalArn'],
        tags={'Project': 'agentcore-github-consent-portal', 'StackId': stack_id})
    cognito.update_user_pool_client(ClientId=app['ClientId'],
        **client_settings(p['UserPoolId'], name, portal['portalUrl'].rstrip('/') + '/callback', scopes))
    return {'PortalId': portal['consentPortalId'], 'PortalArn': portal['consentPortalArn'],
            'PortalUrl': portal['portalUrl'].rstrip('/'), 'CognitoClientId': app['ClientId'],
            'IdpProviderArn': provider['credentialProviderArn'], 'IdpProviderName': name + '-oidc'}


def respond(event, status, physical_id, data, reason='Completed'):
    body = json.dumps({'Status': status, 'Reason': reason, 'PhysicalResourceId': physical_id,
        'StackId': event['StackId'], 'RequestId': event['RequestId'],
        'LogicalResourceId': event['LogicalResourceId'], 'NoEcho': False, 'Data': data}).encode()
    request = urllib.request.Request(event['ResponseURL'], data=body, method='PUT',
                                      headers={'Content-Type': '', 'Content-Length': str(len(body))})
    # Avoid losing CFN acknowledgement to a transient S3 response error.
    for attempt in range(3):
        try:
            with urllib.request.urlopen(request, timeout=10) as response:
                response.read()
            return
        except Exception:
            if attempt == 2:
                raise
            time.sleep(1 + attempt)


def handler(event, context):
    api = boto3.client('bedrock-agentcore-control')
    cognito = boto3.client('cognito-idp')
    p = event['ResourceProperties']
    name = event.get('PhysicalResourceId') if event['RequestType'] == 'Delete' else resource_name(event)
    name = name or resource_name(event)
    deadline = time.monotonic() + min(780, context.get_remaining_time_in_millis() / 1000 - 60)
    try:
        if event['RequestType'] == 'Delete':
            remove(api, cognito, p, name, deadline)
            data = {}
        else:
            data = provision(api, cognito, p, name, deadline, event['StackId'])
    except Exception as exc:
        # Never emit the event, tokens, client secrets, or signed ResponseURL.
        code = exc.response['Error']['Code'] if isinstance(exc, ClientError) else type(exc).__name__
        diagnostic = {'operation': event['RequestType'], 'error_type': code}
        if isinstance(exc, ClientError):
            diagnostic['api_operation'] = exc.operation_name
            if code in ('AccessDeniedException', 'AccessDenied'):
                diagnostic['permission_error'] = exc.response['Error'].get('Message', '')
        print(json.dumps(diagnostic))
        reason = 'Lifecycle failed: ' + diagnostic.get('api_operation', '') + ' ' + code
        if 'permission_error' in diagnostic:
            reason += ': ' + diagnostic['permission_error'][:1400]
        respond(event, 'FAILED', name, {}, reason)
        return
    respond(event, 'SUCCESS', name, data)
