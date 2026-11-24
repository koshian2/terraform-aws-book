"""Create a case, talk, hand off, then continue through the same entrypoint."""
import argparse
import json
import uuid
from pathlib import Path
import common
import boto3
from botocore.config import Config
from contracts import digest, encoded
from transport import invoke_json

QUESTION = '本棚の件、続きお願いします。次は何をすればいいんでしたっけ？'


def connect():
    cfg = common.settings()
    session = boto3.Session(profile_name=cfg['aws_profile'], region_name=cfg['aws_region'])
    api = session.client('bedrock-agentcore', config=Config(read_timeout=300, retries={'total_max_attempts': 1}))
    return cfg, lambda value: invoke_json(api, cfg['router_arn'], value)


def emit(value):
    print(json.dumps(value, ensure_ascii=False, indent=2))


def show(value, shown=0):
    """Display saved utterances verbatim, without generating a summary."""
    names = {'predecessor': '前任', 'successor': '後任'}
    labels = {'initial_record': '最初に渡した記録', 'question': '確認質問',
              'answer': '確認への回答', 'ready': '受領内容の整理'}
    state = value.get('state')
    print(f"\n案件ID: {value.get('case_id') or (state or {}).get('case_id')}", flush=True)
    if 'text' in value:
        print(f"【{names.get(value.get('answered_by'), value.get('answered_by'))} → 顧客】\n{value['text']}", flush=True)
    if state:
        progress = state.get('progress', {})
        events = progress.get('events', [])
        for e in events[shown:]:
            print(f"\n【{names.get(e['speaker'], e['speaker'])}：{labels.get(e['kind'], e['kind'])}】\n{e['text']}", flush=True)
            if e.get('a2a'):
                print(f"  A2A request: {e['a2a']['request_id']} / task: {e['a2a']['task_id']}")
            elif e.get('generated_in'):
                print(f"  A2A task: {e['generated_in']['task_id']}")
            if e.get('cached'): print('  保存済みのモデル出力を再利用')
        print(f"\n現在の担当: {names.get(state['owner'], state['owner'])}（担当版数 {state['version']}）", flush=True)
        if progress:
            print(f"進行: {progress['phase']} / revision={progress['revision']}", flush=True)
            if progress['phase'] == 'awaiting_answer':
                print('後任から確認質問が来ています。担当はまだ前任です。')
                print(f"次の操作: python client.py advance {state['case_id']} --revision {progress['revision']}")
            elif progress['phase'] == 'completed': print('受領が完了し、現在の担当は後任です。')
        if value.get('stale_request'): print('古い進行番号のため、処理を進めず現在の記録を表示しました。')
        if value.get('already_transferred'): print('この案件はすでに引き継ぎ済みです。')
        return len(events)
    return shown


def demo(call, notes, modes=('minimal', 'complete'), step_by_step=False):
    results = []
    def pause(label):
        if not step_by_step: return True
        try: return input(f'\n{label}：Enterで実行 / qでここで終了 > ').strip().lower() != 'q'
        except (EOFError, KeyboardInterrupt): return False

    for mode in modes:
        cid = str(uuid.uuid4())
        row = {'case_id': cid, 'mode': mode}
        print(f'\n--- {mode}: {cid} ---', flush=True)
        common.save('demo-request', {'case_id': cid, 'mode': mode, 'notes': notes})
        def checkpoint(): common.save('demo-progress', row)
        def stop():
            checkpoint()
            print(f'\n停止しました。案件は保存済みです。再開前に状態を確認してください。\npython client.py status {cid}')
        row['created'] = call({'action': 'create', 'case_id': cid, 'mode': mode, 'notes': notes})
        checkpoint()
        show(row['created'])
        if not pause('前任に次の対応を質問する'): return stop()
        print(f'\n顧客の質問: {QUESTION}', flush=True)
        row['before'] = call({'action': 'talk', 'case_id': cid, 'message': QUESTION})
        assert row['before']['answered_by'] == 'predecessor'
        checkpoint()
        show(row['before'])
        if not pause('引き継ぎを開始し、後任の確認を読む'): return stop()
        row['handoff_steps'] = []
        step = call({'action': 'handoff', 'case_id': cid})
        shown = 0
        while True:
            row['handoff_steps'].append(step)
            checkpoint()
            progress = step['state']['progress']
            shown = show(step, shown)
            if step['state']['owner'] == 'successor': break
            if progress['revision'] > 2: raise RuntimeError('Too many handoff steps')
            if not pause('1段階進め、前任の回答と後任の次の発言を読む'): return stop()
            step = call({'action': 'advance', 'case_id': cid, 'expected_revision': progress['revision']})
        row['duplicate'] = call({'action': 'handoff', 'case_id': cid})
        assert row['duplicate']['already_transferred'] is True
        assert row['duplicate']['state']['version'] == 1
        print('\n検証: 同じ引き継ぎの再実行でも担当版数は1のままです。')
        if not pause('同じ顧客質問を、現在の担当である後任へ送る'): return stop()
        print(f'\n顧客の質問: {QUESTION}', flush=True)
        row['after'] = call({'action': 'talk', 'case_id': cid, 'message': QUESTION})
        checkpoint()
        show(row['after'])
        assert row['after']['answered_by'] == 'successor'
        initial = '本棚の購入相談中。' if mode == 'minimal' else notes
        assert progress['packet'] == initial
        final_packet = encoded({'initial_record': initial,
            'qa': [{'speaker': e['speaker'], 'text': e['text']} for e in progress['events'] if e['kind'] in ('question', 'answer')],
            'accepted_summary': progress['events'][-1]['text']}).decode()
        assert row['after']['context_sha256'] == digest(final_packet)
        row['persisted'] = call({'action': 'status', 'case_id': cid})
        assert row['persisted']['state']['owner'] == 'successor'
        results.append(row)
        common.save('demo-case', row)
        print(f'\n{mode}: QAと担当変更、後任が参照した記録のハッシュを確認しました。')
    path = common.save('demo', results)
    print(f'PASS: ownership persisted, duplicate handoff safe, context hashes verified. {path}')
    print('Response quality is for human review; the checks do not prove semantic correctness.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    create = sub.add_parser('create')
    create.add_argument('--mode', choices=['minimal', 'complete'], default='complete')
    create.add_argument('--notes', type=Path, default=common.ROOT / 'case-notes.md')
    create.add_argument('--case-id', default=None, help='Reuse the same ID only to retry identical case creation')
    for name in ('status', 'handoff'):
        sub.add_parser(name).add_argument('case_id')
    advance = sub.add_parser('advance')
    advance.add_argument('case_id')
    advance.add_argument('--revision', type=int, required=True)
    talk = sub.add_parser('talk')
    talk.add_argument('case_id')
    talk.add_argument('message', nargs='?', default=QUESTION)
    test = sub.add_parser('demo')
    test.add_argument('--notes', type=Path, default=common.ROOT / 'case-notes.md')
    test.add_argument('--mode', choices=['minimal', 'complete', 'both'], default='both')
    test.add_argument('--step', action='store_true', help='Pause before each operation; Enter continues, q stops')
    for command in (create, talk, advance, sub.choices['status'], sub.choices['handoff']):
        command.add_argument('--json', action='store_true', help='Print raw JSON instead of the conversation view')
    args = parser.parse_args()
    _, call = connect()
    if args.command == 'demo':
        modes = ('minimal', 'complete') if args.mode == 'both' else (args.mode,)
        demo(call, args.notes.read_text(encoding='utf-8-sig'), modes, args.step)
        return
    value = {'action': args.command, 'case_id': getattr(args, 'case_id', None) or str(uuid.uuid4())}
    if args.command == 'create': value.update(mode=args.mode, notes=args.notes.read_text(encoding='utf-8-sig'))
    if args.command == 'talk': value['message'] = args.message
    if args.command == 'advance': value['expected_revision'] = args.revision
    common.save('request', value)  # Preserve case UUID even if the network response is lost.
    result = call(value)
    path = common.save(args.command, result)
    if args.json: emit(result)
    else:
        show(result)
        print(f'\n原文JSON: {path}')


if __name__ == '__main__': main()
