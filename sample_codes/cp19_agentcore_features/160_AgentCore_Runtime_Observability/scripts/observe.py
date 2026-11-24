"""Read only this Gateway's Policy spans; never repeat tool calls while waiting."""
import argparse
import json
from pathlib import Path
import subprocess
import time

import boto3
from botocore.config import Config

from common import ROOT


def config():
    return json.loads(subprocess.check_output(
        ['terraform', 'output', '-json', 'observation_config'], cwd=ROOT / 'terraform', encoding='utf-8'))


def matching_spans(spans, call, cfg):
    expected = 'DENY' if call['case'] == 'deny' else 'ALLOW'
    policy = cfg['allow_policy_id'] if expected == 'ALLOW' else cfg['deny_policy_id']
    matches = []
    for span in spans:
        attrs = span.get('attributes', {})
        if (span.get('name') == 'AgentCore.Policy.AuthorizeAction'
                and span.get('traceId') == call['trace_id']
                and attrs.get('aws.agentcore.policy.target_resource.id') == cfg['gateway_id']
                and attrs.get('aws.agentcore.gateway.policy.arn') == cfg['policy_engine_arn']
                and attrs.get('aws.agentcore.gateway.policy.mode') == 'ENFORCE'
                and attrs.get('aws.agentcore.policy.authorization_decision') == expected
                and policy in attrs.get('aws.agentcore.policy.determining_policies', [])
                and attrs.get('aws.agentcore.policy.mismatched_policies') == []):
            matches.append(span)
    return matches


def is_descendant(span, ancestor_id, spans):
    by_id = {s['spanId']: s for s in spans}
    parent = span.get('parentSpanId')
    seen = set()
    while parent and parent not in seen:
        if parent == ancestor_id:
            return True
        seen.add(parent)
        parent = by_id.get(parent, {}).get('parentSpanId')
    return False


def evaluate(spans, calls, cfg):
    checks = {}
    for call in calls:
        related = [s for s in spans if s.get('traceId') == call['trace_id']]
        gateway = [s for s in related if s.get('name') == 'AgentCore.Gateway.InvokeTool'
                   and s.get('attributes', {}).get('gateway.id') == cfg['gateway_id']]
        policy = matching_spans(related, call, cfg)
        app = [s for s in related if s.get('name') == 'quote.calculate_quote']
        result = {'policy': len(policy) == 1, 'gateway': len(gateway) == 1}
        if call['case'] == 'deny':
            result['no_runtime_spans_observed'] = not app and not any(
                s.get('name') == 'AgentCore.Runtime.Invoke' for s in related)
        else:
            outcome = 'SUCCESS' if call['case'] == 'allow' else 'NOT_FOUND'
            result['runtime_outcome'] = (len(app) == 1 and
                app[0].get('attributes', {}).get('quote.outcome') == outcome)
            result['gateway_parent_chain'] = (len(app) == len(gateway) == 1 and
                is_descendant(app[0], gateway[0]['spanId'], related))
            children = ([s for s in related if is_descendant(s, app[0]['spanId'], related)]
                        if len(app) == 1 else [])
            result['database'] = any(s.get('attributes', {}).get('rpc.method') == 'GetItem'
                                     for s in children)
            result['product_check'] = any(s.get('name') == 'quote.check_product' and
                s.get('attributes', {}).get('quote.lookup_outcome') ==
                ('FOUND' if outcome == 'SUCCESS' else 'NOT_FOUND') for s in children)
            compute = [s for s in children if s.get('name') == 'quote.compute_total']
            result['calculation'] = (len(compute) == 1 and
                compute[0].get('attributes', {}).get('quote.total') == 600
                if outcome == 'SUCCESS' else not compute)
            result['not_infrastructure_error'] = bool(children) and all(
                s.get('status', {}).get('code') != 'ERROR' for s in children + app)
        checks[call['case']] = result
    return checks


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--calls', type=Path, default=ROOT / 'results/latest-calls.json')
    parser.add_argument('--wait-seconds', type=int, default=300)
    parser.add_argument('--output', type=Path, default=ROOT / 'results/latest-spans.json')
    args = parser.parse_args()
    if not 0 <= args.wait_seconds <= 900:
        parser.error('--wait-seconds must be 0-900')
    cfg = config()
    calls = json.loads(args.calls.read_text(encoding='utf-8'))
    aws = boto3.Session(profile_name=cfg['aws_profile'], region_name=cfg['aws_region'])
    logs = aws.client('logs', config=Config(connect_timeout=10, read_timeout=30))
    deadline = time.monotonic() + args.wait_seconds
    trace_ids = [call['trace_id'] for call in calls['calls']]
    if not all(len(t) == 32 and all(c in '0123456789abcdef' for c in t) for t in trace_ids):
        raise ValueError('Invalid trace IDs in calls artifact')
    query = ('fields @timestamp, @message | filter traceId in ' + json.dumps(trace_ids)
             + ' | sort @timestamp asc | limit 500')
    while True:
        qid = logs.start_query(logGroupName=cfg['log_group'],
            startTime=int(calls['started_at_epoch']) - 5,
            endTime=int(calls['finished_at_epoch']) + 10, queryString=query)['queryId']
        query_deadline = time.monotonic() + 60
        try:
            while True:
                response = logs.get_query_results(queryId=qid)
                if response['status'] == 'Complete':
                    break
                if response['status'] not in ('Running', 'Scheduled'):
                    raise RuntimeError('Logs query did not complete: ' + response['status'])
                if time.monotonic() >= query_deadline:
                    raise TimeoutError('Logs query deadline exceeded')
                time.sleep(2)
        except BaseException:
            logs.stop_query(queryId=qid)
            raise
        spans = [json.loads(next(f['value'] for f in row if f['field'] == '@message'))
                 for row in response['results']]
        observed = evaluate(spans, calls['calls'], cfg)
        status = ('observed' if observed.keys() == {'allow', 'deny', 'not_found'}
                  and all(all(v.values()) for v in observed.values())
                  else 'incomplete_observation')
        artifact = {'status': status, 'gateway_id': cfg['gateway_id'], 'query': query,
                    'matches': observed, 'spans': spans}
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(artifact, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        print(json.dumps({'status': status, 'matches': observed, 'span_count': len(spans)}), flush=True)
        if status == 'observed':
            return 0
        if time.monotonic() >= deadline:
            return 2
        time.sleep(min(15, max(0, deadline - time.monotonic())))


if __name__ == '__main__':
    raise SystemExit(main())
