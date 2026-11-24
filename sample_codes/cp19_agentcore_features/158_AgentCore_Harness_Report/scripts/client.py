"""Harnessに作業を依頼し、入力と成果物を転送するクライアント。"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
from pathlib import Path, PurePosixPath
import shlex
import subprocess
import sys
from datetime import datetime, timezone
import uuid

ROOT = Path(__file__).resolve().parents[1]
REMOTE = "/tmp/expense-report"
DEFAULT_PROMPT = "この3か月分の経費CSVから、支出の傾向が分かるHTMLレポートを作ってください。グラフと、気になった点の説明も入れてください。作成したコードを実行し、集計と成果物を確認してください。"
MAX_FILE = 4 * 1024 * 1024


def save_json(path: Path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def setup():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")


def config():
    result = subprocess.run(["terraform", "-chdir=terraform", "output", "-json", "client_config"],
                            cwd=ROOT, stdin=subprocess.DEVNULL, capture_output=True, check=True,
                            encoding="utf-8", timeout=20)
    return json.loads(result.stdout)


def python_command(source: str) -> str:
    # コードはBase64で渡し、入力値をシェル構文に直接埋め込まない。
    encoded = base64.b64encode(source.encode()).decode()
    return "python3 -c " + shlex.quote(f"import base64; exec(base64.b64decode('{encoded}'))")


def command(api, meta, source: str) -> str:
    response = api.invoke_agent_runtime_command(agentRuntimeArn=meta["harness_arn"],
                                                runtimeSessionId=meta["session_id"],
                                                body={"command": python_command(source), "timeout": 60})
    stdout, stderr, exit_code = [], [], None
    stream = response["stream"]
    try:
        for event in stream:
            if "chunk" not in event:
                raise RuntimeError(f"Remote command error: {event}")
            chunk = event["chunk"]
            delta = chunk.get("contentDelta", {})
            stdout.append(delta.get("stdout", ""))
            stderr.append(delta.get("stderr", ""))
            if "contentStop" in chunk:
                exit_code = chunk["contentStop"]["exitCode"]
    finally:
        stream.close()
    if exit_code != 0:
        raise RuntimeError(f"Remote command exit={exit_code}: {''.join(stderr)[-4000:]}")
    return "".join(stdout)


def upload(api, meta, csv_path):
    data = csv_path.read_bytes()
    if len(data) > 128 * 1024:
        raise ValueError("Demo CSV must be <=128 KiB.")
    data.decode("utf-8-sig")
    encoded = base64.b64encode(data).decode()
    result = command(api, meta, f"""
from pathlib import Path
import base64, hashlib, json
root = Path({REMOTE!r})
(root/'input').mkdir(parents=True, exist_ok=True)
(root/'artifacts').mkdir(exist_ok=True)
p = root/'input/expenses.csv'
assert not p.exists(), 'Input already exists; do not overwrite this session.'
p.write_bytes(base64.b64decode({encoded!r}))
print(json.dumps({{'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}}))
""")
    received = json.loads(result)
    assert received["sha256"] == hashlib.sha256(data).hexdigest()
    return data, received


def write_artifacts(out: Path, files: list) -> list:
    # モデルが作ったファイル名・サイズ・ハッシュを検査してから保存する。
    prepared = []
    for item in files:
        name = item["name"]
        p = PurePosixPath(name)
        if (not name or p.is_absolute() or len(p.parts) != 1 or name in (".", "..")
                or any(c in name for c in '\\:/\x00<>"|?*') or name.endswith((".", " "))
                or name.split(".")[0].upper() in {"CON", "PRN", "AUX", "NUL", *(f"COM{i}" for i in range(1, 10)), *(f"LPT{i}" for i in range(1, 10))}):
            raise ValueError(f"Unsafe artifact name: {name!r}")
        if len(item["data"]) > MAX_FILE * 2:
            raise ValueError("Artifact too large")
        data = base64.b64decode(item["data"], validate=True)
        if len(data) > MAX_FILE or hashlib.sha256(data).hexdigest() != item["sha256"]:
            raise ValueError("Artifact size/hash mismatch")
        prepared.append((name, data))
    if len(prepared) > 30 or sum(len(data) for _, data in prepared) > MAX_FILE * 2:
        raise ValueError("Artifact batch too large")
    if len({name.casefold() for name, _ in prepared}) != len(prepared):
        raise ValueError("Duplicate artifact filenames")
    out.mkdir(parents=True, exist_ok=False)
    for name, data in prepared:
        (out / name).write_bytes(data)
    save_json(out.parent / "manifest.json", [{k: v for k, v in item.items() if k != "data"} for item in files])
    return [name for name, _ in prepared]


def fetch(api, meta, run_dir):
    payload = command(api, meta, f"""
from pathlib import Path
import base64, hashlib, json
root = Path({REMOTE!r})/'artifacts'
files = []
total = 0
assert not root.is_symlink(), 'Artifact directory must not be a symlink'
for p in sorted(root.iterdir()) if root.exists() else []:
    if p.is_symlink() or not p.is_file(): continue
    assert p.stat().st_size <= {MAX_FILE}, 'File too large'
    data = p.read_bytes()
    total += len(data)
    assert total <= {MAX_FILE * 2} and len(files) < 30, 'Artifact batch too large'
    files.append({{'name':p.name,'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data),'data':base64.b64encode(data).decode()}})
print(json.dumps(files))
""")
    names = write_artifacts(run_dir / "artifacts", json.loads(payload))
    print("\nArtifacts: " + ", ".join(names), flush=True)
    print(f"Local directory: {run_dir / 'artifacts'}", flush=True)
    return names


def invoke(api, meta, prompt, run_dir):
    response = api.invoke_harness(harnessArn=meta["harness_arn"], runtimeSessionId=meta["session_id"],
                                 actorId="expense-demo", messages=[{"role": "user", "content": [{"text": prompt}]}])
    save_json(run_dir / "request.json", {"prompt": prompt, "session_id": meta["session_id"],
                                       "request_id": response.get("ResponseMetadata", {}).get("RequestId")})
    text, tools, stops, usage = [], [], [], []
    stream = response["stream"]
    try:
        with (run_dir / "events.jsonl").open("w", encoding="utf-8") as f:
            for event in stream:
                # 推論ブロックや署名は表示・保存しない。
                delta = event.get("contentBlockDelta", {}).get("delta", {})
                if "reasoningContent" in delta:
                    continue
                f.write(json.dumps(event, ensure_ascii=False) + "\n")
                f.flush()
                tool = event.get("contentBlockStart", {}).get("start", {}).get("toolUse")
                if tool:
                    tools.append(tool)
                    print(f"\n[tool] {tool['name']} ({tool['toolUseId']})", flush=True)
                if "text" in delta:
                    text.append(delta["text"])
                    print(delta["text"], end="", flush=True)
                if "toolUse" in delta:
                    print(delta["toolUse"].get("input", ""), end="", flush=True)
                if "toolResult" in delta:
                    print("\n[tool result] " + json.dumps(delta["toolResult"], ensure_ascii=False)[:1200], flush=True)
                if "messageStop" in event:
                    stops.append(event["messageStop"]["stopReason"])
                if "metadata" in event:
                    usage.append(event["metadata"])
                for name in ("internalServerException", "validationException", "runtimeClientError"):
                    if name in event:
                        raise RuntimeError(f"{name}: {event[name]}")
    finally:
        stream.close()
        (run_dir / "answer.txt").write_text("".join(text), encoding="utf-8")
        save_json(run_dir / "execution.json", {"tools": tools, "stop_reasons": stops, "metadata": usage})
    if not stops or stops[-1] != "end_turn":
        raise RuntimeError(f"Agent did not finish normally: {stops}. Inspect events before continuing; no automatic retry.")


def session_dir(sid):
    if sid == "latest":
        candidates = []
        for path in (ROOT / "results").glob("*/session.json"):
            meta = json.loads(path.read_text(encoding="utf-8"))
            candidates.append((meta["created_at"], meta["session_id"]))
        if not candidates:
            raise ValueError("セッションの記録がありません。先にstartを実行してください。")
        sid = max(candidates)[1]
        print(f"Session: {sid}", flush=True)
    try:
        canonical = str(uuid.UUID(sid))
    except ValueError:
        raise ValueError("--sessionにはlatest、またはstartが表示したUUIDを指定してください。") from None
    if canonical != sid:
        raise ValueError("Use the session UUID printed by start.")
    return ROOT / "results" / sid


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    start = sub.add_parser("start")
    start.add_argument("--csv", type=Path, default=ROOT / "data/expenses.csv")
    start.add_argument("--prompt", default=DEFAULT_PROMPT)
    for action in ("ask", "fetch", "status", "stop", "isolation"):
        p = sub.add_parser(action)
        p.add_argument("--session", required=True, help="latest、またはstartが表示したUUID")
        if action == "ask":
            p.add_argument("prompt")
    args = parser.parse_args()
    setup()
    import boto3
    from botocore.config import Config
    if args.action == "start":
        meta = config()
        meta.update(session_id=str(uuid.uuid4()), status="starting", created_at=datetime.now(timezone.utc).isoformat())
        directory = session_dir(meta["session_id"])
        directory.mkdir(parents=True)
    else:
        try:
            directory = session_dir(args.session)
        except ValueError as exc:
            parser.error(str(exc))
        meta = json.loads((directory / "session.json").read_text(encoding="utf-8"))
    if args.action == "status":
        print(json.dumps(meta, ensure_ascii=False, indent=2))
        return
    session = boto3.Session(profile_name=meta["aws_profile"], region_name=meta["aws_region"])
    api = session.client("bedrock-agentcore", config=Config(read_timeout=660, retries={"total_max_attempts": 1}))
    cp = session.client("bedrock-agentcore-control")
    if args.action == "start":
        h = cp.get_harness(harnessId=meta["harness_id"])["harness"]
        meta["harness_model_at_start"] = h["model"]
        meta["runtime_arn"] = h["environment"]["agentCoreRuntimeEnvironment"]["agentRuntimeArn"]
        save_json(directory / "session.json", meta)
        print(f"Session: {meta['session_id']}\nResults: {directory}", flush=True)
        print("Harness model: " + json.dumps(h["model"], ensure_ascii=False), flush=True)
        try:
            data, receipt = upload(api, meta, args.csv)
            (directory / "input.csv").write_bytes(data)
            save_json(directory / "upload.json", receipt)
            meta["status"] = "ready"
        finally:
            save_json(directory / "session.json", meta)
    if args.action == "stop":
        result = api.stop_runtime_session(agentRuntimeArn=meta["harness_arn"], runtimeSessionId=meta["session_id"])
        meta.update(status="stopped", stopped_at=datetime.now(timezone.utc).isoformat())
        save_json(directory / "session.json", meta)
        print(json.dumps(result, default=str))
        return
    if args.action == "isolation":
        other = dict(meta, session_id=str(uuid.uuid4()))
        try:
            original = json.loads(command(api, meta, f"import pathlib,json; print(json.dumps({{'exists':pathlib.Path({REMOTE!r}+'/input/expenses.csv').exists()}}))"))
            isolated = json.loads(command(api, other, f"import pathlib,json; print(json.dumps({{'exists':pathlib.Path({REMOTE!r}+'/input/expenses.csv').exists()}}))"))
            report = {"original": original, "other": isolated, "other_session_id": other["session_id"]}
            save_json(directory / "isolation.json", report)
            assert original["exists"] and not isolated["exists"], report
            print("PASS: input exists in original session and is absent in the new session.")
        finally:
            api.stop_runtime_session(agentRuntimeArn=meta["harness_arn"], runtimeSessionId=other["session_id"])
        return
    if meta.get("status") == "stopped":
        raise ValueError("Session was stopped. Start a new sample session.")
    run_dir = directory / datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    run_dir.mkdir()
    if args.action in ("start", "ask"):
        command(api, meta, f"from pathlib import Path; assert Path({REMOTE!r}+'/input/expenses.csv').exists(), 'Session files expired. Start a new session.'; print('ready')")
        invoke(api, meta, args.prompt, run_dir)
    fetch(api, meta, run_dir)
    save_json(directory / "latest.json", {"directory": run_dir.name})


if __name__ == "__main__":
    main()
