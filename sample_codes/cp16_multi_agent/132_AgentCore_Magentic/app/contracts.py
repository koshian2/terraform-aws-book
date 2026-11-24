import hashlib
import json
import uuid

ROLES = ('repair', 'insurance', 'rental')
MAX_CALLS = 8


def encoded(value): return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()
def digest(value): return hashlib.sha256(encoded(value)).hexdigest()


def identifier(value):
    if not isinstance(value, str) or str(uuid.UUID(value)) != value: raise ValueError('Expected canonical case UUID')


def text(value, maximum=3000):
    if not isinstance(value, str) or not value.strip() or len(value) > maximum: raise ValueError('Invalid text length')


def parameters(role, params):
    if role == 'repair':
        if set(params) != {'stage'} or params['stage'] not in ('estimate', 'confirmed'): raise ValueError('Invalid repair stage')
    elif role in ('insurance', 'rental'):
        fields = {'days'} if role == 'insurance' else {'days', 'vehicle'}
        if set(params) != fields or type(params['days']) is not int or not 1 <= params['days'] <= 30: raise ValueError('Invalid days')
        if role == 'rental' and params['vehicle'] not in ('standard', 'compact'): raise ValueError('Invalid vehicle')
    else: raise ValueError('Unknown specialist')


def manager_request(value):
    if not isinstance(value, dict): raise ValueError('Expected object')
    action = value.get('action')
    fields = {'action', 'case_id'}
    if action == 'create': fields |= {'scenario', 'request'}
    elif action == 'advance': fields |= {'expected_revision'}
    elif action != 'status': raise ValueError('Unsupported action')
    if set(value) != fields: raise ValueError('Unexpected fields')
    identifier(value['case_id'])
    if action == 'create':
        if value['scenario'] not in ('normal', 'delayed'): raise ValueError('Unknown fixture scenario')
        text(value['request'], 2000)
    if action == 'advance' and (type(value['expected_revision']) is not int or not 0 <= value['expected_revision'] <= MAX_CALLS+1):
        raise ValueError('Invalid revision')


def specialist_request(value, role):
    if set(value) != {'case_id', 'scenario', 'role', 'question', 'parameters'} or value['role'] != role:
        raise ValueError('Wrong specialist request')
    identifier(value['case_id'])
    if value['scenario'] not in ('normal', 'delayed'): raise ValueError('Unknown scenario')
    text(value['question'], 1500)
    parameters(role, value['parameters'])


def normalize_decision_json(raw):
    raw = raw.strip()
    if raw.startswith('```') and raw.endswith('```'): raw = raw.split('\n', 1)[1].rsplit('```', 1)[0].strip()
    # Accept only a complete object followed by one redundant closing brace.
    # Never discard prose, another JSON object, or repair an incomplete object.
    value, end = json.JSONDecoder().raw_decode(raw)
    if isinstance(value, dict) and raw[end:].strip() == '}':
        return raw[:end]
    return raw


def decision(raw):
    raw = normalize_decision_json(raw)
    value = json.loads(raw)
    if not isinstance(value, dict) or set(value) != {'plan', 'unresolved', 'change_reason', 'next'}:
        raise ValueError('Invalid manager decision fields')
    for key in ('plan', 'unresolved'):
        if not isinstance(value[key], list) or len(value[key]) > 8: raise ValueError('Invalid ledger list')
        for item in value[key]: text(item, 1000)
    if not value['plan']: raise ValueError('Empty plan')
    text(value['change_reason'], 1500)
    nxt = value['next']
    if not isinstance(nxt, dict): raise ValueError('Invalid next action')
    if nxt.get('kind') == 'consult':
        if set(nxt) != {'kind', 'role', 'question', 'parameters'}: raise ValueError('Invalid consult fields')
        text(nxt['question'], 1500)
        parameters(nxt['role'], nxt['parameters'])
    elif nxt.get('kind') in ('finish', 'blocked'):
        if set(nxt) != {'kind', 'message'}: raise ValueError('Invalid final fields')
        text(nxt['message'], 4000)
    else: raise ValueError('Invalid action kind')
    return value


def request_rpc(value, request_id):
    return {'jsonrpc': '2.0', 'id': request_id, 'method': 'message/send', 'params': {
        'message': {'role': 'user', 'messageId': str(uuid.uuid4()), 'parts': [{'kind': 'text', 'text': encoded(value).decode()}]},
        'configuration': {'blocking': True}}}


def extract_rpc(response, request_id):
    if response.get('jsonrpc') != '2.0' or response.get('id') != request_id or 'error' in response:
        raise RuntimeError('A2A error: ' + str(response.get('error')))
    task = response.get('result', {})
    if task.get('status', {}).get('state') != 'completed': raise RuntimeError('A2A incomplete: ' + str(task.get('status')))
    data = [p['data'] for a in task.get('artifacts', []) for p in a.get('parts', []) if p.get('kind') == 'data']
    if len(data) != 1: raise ValueError('Expected one specialist answer')
    return data[0]
