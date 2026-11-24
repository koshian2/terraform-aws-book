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
        ['terraform', f'-chdir={ROOT / "terraform"}', 'output', '-json', 'observation_config'], cwd=ROOT, encoding='utf-8'))


def matching_spans(spans, call, cfg):
    expected = 'ALLOW' if call['case'] == 'allow' else 'DENY'
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--calls', type=Path, default=ROOT / Path('results/latest-calls.json'))
    parser.add_argument('--wait-seconds', type=int, default=300)
    parser.add_argument('--output', type=Path, default=ROOT / Path('results/latest-spans.json'))
    args = parser.parse_args()
    if not 0 <= args.wait_seconds <= 900:
        parser.error('--wait-seconds must be 0-900')
    cfg = config()
    calls = json.loads(args.calls.read_text(encoding='utf-8'))
    aws = boto3.Session(profile_name=cfg['aws_profile'], region_name=cfg['aws_region'])
    logs = aws.client('logs', config=Config(connect_timeout=10, read_timeout=30))
    deadline = time.monotonic() + args.wait_seconds
    query = ('fields @timestamp, @message | filter @message like /' + cfg['gateway_id']
             + '/ | filter @message like /authorization_decision/ | sort @timestamp asc | limit 100')
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
        observed = {call['case']: len(matching_spans(spans, call, cfg)) for call in calls['calls']}
        status = ('observed' if observed.keys() == {'allow', 'deny'} and all(observed.values())
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
