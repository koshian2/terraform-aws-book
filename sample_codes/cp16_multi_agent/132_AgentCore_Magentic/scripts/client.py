"""Run dealer coordination continuously, displaying consultations and updated plans."""
import argparse
import json
import uuid
import common
import boto3
from botocore.config import Config
from contracts import MAX_CALLS
from orchestration import completion_evidence
from transport import invoke_json

REQUEST = '事故で車を修理することになりました。修理と、その間に使う車の手配案を調整してください。予約前に条件と自己負担を説明してください。'
NAMES = {'repair': '修理工場', 'insurance': '保険会社', 'rental': 'レンタカー会社'}


def connect():
    cfg = common.settings()
    session = boto3.Session(profile_name=cfg['aws_profile'], region_name=cfg['aws_region'])
    api = session.client('bedrock-agentcore', config=Config(read_timeout=330, retries={'total_max_attempts': 1}))
    def call(value):
        common.save('request', value)
        result = invoke_json(api, cfg['manager_arn'], value)
        path = common.save('response', result)
        if 'state' not in result: raise RuntimeError(f'Unexpected response; see {path}')
        return result
    return cfg, call


def show(state, observed=0, planned=0):
    print(f"\n案件: {state['case_id']} / 窓口: ディーラー / phase={state['phase']} / revision={state['revision']}", flush=True)
    for obs in state['observations'][observed:]:
        print(f"\n【照会{obs['number']}：ディーラー → {NAMES[obs['role']]}】\n{obs['question']}", flush=True)
        print(f"条件: {json.dumps(obs['parameters'], ensure_ascii=False)}")
        print(f"【{NAMES[obs['role']]} → ディーラー】\n{obs['reply']['text']}", flush=True)
        print(f"A2A request={obs['a2a']['request_id']} / task={obs['a2a']['task_id']}")
    for plan in state['plans'][planned:]:
        decision = plan['decision']
        print(f"\n【ディーラーの計画更新 #{plan['revision']}】\n根拠: {decision['change_reason']}", flush=True)
        for item in decision['plan']: print('- '+item)
        print('未解決: '+' / '.join(decision['unresolved']))
        nxt = decision['next']
        if nxt['kind'] == 'consult': print(f"次の照会先: {NAMES[nxt['role']]}\n質問: {nxt['question']}")
        else: print(f"\n【ディーラーから顧客への説明】\n{nxt['message']}", flush=True)
    if state.get('stop_reason'): print('システムによる停止: '+state['stop_reason'])
    if state.get('completion_evidence', {}).get('ready'):
        print('照会結果から計算した手配候補: '+json.dumps(state['completion_evidence'], ensure_ascii=False))


def verify(state):
    if state['phase'] != 'completed': raise RuntimeError('Not completed: '+state.get('stop_reason', state['phase']))
    assert state['owner'] == 'dealer'
    assert state['completion_evidence'] == completion_evidence(state['observations'])
    assert state['completion_evidence']['ready']
    assert len(state['observations']) <= MAX_CALLS
    assert all(o['a2a']['request_id'] and o['a2a']['task_id'] for o in state['observations'])
    assert len(state['plans']) == len(state['observations'])+1
    if state['scenario'] == 'delayed':
        repair = [o for o in state['observations'] if o['role'] == 'repair']
        assert repair[0]['reply']['facts']['repair_days'] == 3
        assert repair[-1]['reply']['facts']['repair_days'] == 10
        for role in ('insurance', 'rental'):
            assert {3, 10} <= {o['parameters']['days'] for o in state['observations'] if o['role'] == role}, f'No before/after comparison for {role}'
    print('PASS: 窓口の維持・照会記録・最新条件に基づく手配案を確認。文章の正しさは原文で確認してください。')


def run(call, scenario, step=False):
    cid = str(uuid.uuid4())
    print('ディーラーが相談を受け付け、初期計画を作成しています…', flush=True)
    if not step:
        print('問い合わせと計画更新を自動で進めます。Enter操作は不要です。', flush=True)
    state = call({'action': 'create', 'case_id': cid, 'scenario': scenario, 'request': REQUEST})['state']
    show(state)
    for _ in range(MAX_CALLS+1):
        if state['phase'] in ('completed', 'blocked'): break
        if step:
            try: proceed = input('\n次の照会と計画更新：Enterで実行 / qで停止 > ').strip().lower() != 'q'
            except (EOFError, KeyboardInterrupt): proceed = False
            if not proceed:
                print(f'保存済み案件から再開できます: python client.py status {cid}')
                return state
        observed, planned = len(state['observations']), len(state['plans'])
        if state['phase'] == 'waiting':
            action = state['plans'][-1]['decision']['next']
            print(f"\n▶ {NAMES[action['role']]}へ問い合わせ中…回答を受けてディーラーが計画を更新します。", flush=True)
        else:
            print('\n▶ 保存済みの回答をもとにディーラーが計画を更新しています…', flush=True)
        state = call({'action': 'advance', 'case_id': cid, 'expected_revision': state['revision']})['state']
        show(state, observed, planned)
    path = common.save('run', state)
    print(f'全記録: {path}')
    verify(state)
    return state


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    demo = sub.add_parser('run')
    demo.add_argument('--scenario', choices=['normal', 'delayed'], default='delayed')
    demo.add_argument('--step', action='store_true', help='説明用：各照会の前でEnterを待つ（通常は自動進行）')
    create = sub.add_parser('create')
    create.add_argument('--scenario', choices=['normal', 'delayed'], default='delayed')
    create.add_argument('--request', default=REQUEST)
    create.add_argument('--case-id', default=None)
    status = sub.add_parser('status')
    status.add_argument('case_id')
    adv = sub.add_parser('advance')
    adv.add_argument('case_id')
    adv.add_argument('--revision', type=int, required=True)
    for p in (create, status, adv): p.add_argument('--json', action='store_true')
    args = parser.parse_args()
    _, call = connect()
    if args.command == 'run':
        run(call, args.scenario, args.step)
        return
    value = {'action': args.command, 'case_id': getattr(args, 'case_id', None) or str(uuid.uuid4())}
    if args.command == 'create': value.update(scenario=args.scenario, request=args.request)
    if args.command == 'advance': value['expected_revision'] = args.revision
    result = call(value)
    if args.json: print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        show(result['state'])
        if result.get('stale_request'): print('古い進行番号のため処理を進めず、現在の記録を表示しました。')


if __name__ == '__main__': main()
