"""Issue tenant and tier claims exclusively from administrator-managed data."""
import json
import os


def handler(event, context):
    tenant = event['request']['userAttributes'].get('custom:tenant_id')
    mapping = json.loads(os.environ['TENANT_TIERS'])
    if not isinstance(tenant, str) or tenant not in mapping:
        raise ValueError('Missing or unknown tenant membership')
    tier = mapping[tenant]
    if tier not in ('free', 'pro'):
        raise ValueError('Unknown tenant tier')
    event.setdefault('response', {})['claimsAndScopeOverrideDetails'] = {
        'accessTokenGeneration': {
            'claimsToAddOrOverride': {'tenant_id': tenant, 'tier': tier}
        }
    }
    return event
