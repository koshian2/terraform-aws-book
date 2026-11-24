"""Code Interpreter tools over local HTTP; the MCP client writes the code."""
import argparse
import asyncio
import json
import subprocess
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path

import anyio
import boto3
from bedrock_agentcore.tools.code_interpreter_client import CodeInterpreter
from fastmcp import FastMCP

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "data"
LIMIT = 20000  # characters of stdout/stderr/file text returned to the agent


def save_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def load_config():
    result = subprocess.run(
        ["terraform", "-chdir=terraform", "output", "-json", "client_config"],
        cwd=ROOT, check=True, capture_output=True, encoding="utf-8",
        stdin=subprocess.DEVNULL, timeout=20,
    )
    return json.loads(result.stdout)


def plain_name(name):
    if not name or name in (".", "..") or any(c in name for c in '/\\:') or Path(name).name != name:
        raise ValueError("Use a plain file name without directories.")
    return name


def parse(response):
    """Flatten the InvokeCodeInterpreter event stream into one result."""
    result = {"stdout": "", "stderr": "", "exit_code": None, "is_error": False}
    for event in response.get("stream", []):
        body = event.get("result")
        if body is None:  # service-side exception event
            result["is_error"] = True
            result["stderr"] += json.dumps(event, ensure_ascii=False, default=str)
            continue
        result["is_error"] = result["is_error"] or bool(body.get("isError"))
        structured = body.get("structuredContent") or {}
        result["stdout"] += structured.get("stdout") or ""
        result["stderr"] += structured.get("stderr") or ""
        if structured.get("exitCode") is not None:
            result["exit_code"] = structured["exitCode"]
        if not structured:
            result["stdout"] += "".join(c.get("text", "") for c in body.get("content", [])
                                        if c.get("type") == "text")
    for key in ("stdout", "stderr"):
        if len(result[key]) > LIMIT:
            result[key] = result[key][:LIMIT] + "\n[truncated]"
    return result


class Sandbox:
    """One Code Interpreter session per process. Methods block; tools run them in a thread."""

    def __init__(self):
        self.client = self.out = None
        self.metadata = {}
        self.lock = asyncio.Lock()
        self.sequence = 0

    def require_client(self):
        if self.client is None:
            raise ValueError("Call code_start first.")
        return self.client

    def start(self):
        if self.client is not None:
            return self.metadata
        config = load_config()
        session = boto3.Session(profile_name=config["aws_profile"], region_name=config["aws_region"])
        now = datetime.now(timezone.utc)
        self.out = ROOT / "results" / now.strftime("%Y%m%dT%H%M%S%fZ")
        self.out.mkdir(parents=True)
        self.sequence = 0
        client = CodeInterpreter(config["aws_region"], session=session)
        session_id = client.start(identifier=config["code_interpreter_id"],
                                  name="code-session", session_timeout_seconds=900)
        self.client = client
        self.metadata = {"code_interpreter_id": config["code_interpreter_id"], "session_id": session_id,
                         "started_at": now.isoformat(), "results": str(self.out)}
        save_json(self.out / "session.json", self.metadata)
        return self.metadata

    def stop(self):
        stopped = self.client is None
        if self.client is not None:
            stopped = self.client.stop()
            if not stopped:
                raise RuntimeError("AWS session stop failed. Retry code_stop or stop it in the AWS console.")
            self.client = None
        self.metadata.update(session_stopped=stopped, ended_at=datetime.now(timezone.utc).isoformat())
        if self.out:
            save_json(self.out / "session.json", self.metadata)
        return self.metadata

    def invoke(self, kind, method, params, source):
        client = self.require_client()
        self.sequence += 1
        stem = f"{self.sequence:03}-{kind}"
        (self.out / f"{stem}.txt").write_text(source, encoding="utf-8", newline="\n")
        result = parse(client.invoke(method, params))
        save_json(self.out / f"{stem}.json", result)
        return result

    def run(self, code):
        return self.invoke("run", "executeCode", {"code": code, "language": "python", "clearContext": False}, code)

    def shell(self, command):
        return self.invoke("shell", "executeCommand", {"command": command}, command)

    def upload(self, name):
        path = DATA / plain_name(name)
        if path.resolve().parent != DATA.resolve():
            raise ValueError("Upload files must stay inside data/.")
        if not path.is_file():
            raise ValueError(f"{name} is not in data/. Available: {sorted(p.name for p in DATA.iterdir())}")
        raw = path.read_bytes()
        try:
            content = raw.decode("utf-8")
        except UnicodeDecodeError:
            content = raw
        self.require_client().upload_file(name, content)
        return {"uploaded": name, "bytes": len(raw)}

    def download(self, name):
        content = self.require_client().download_file(plain_name(name))
        target = self.out / "files" / name
        target.parent.mkdir(exist_ok=True)
        if target.resolve().parent != (self.out / "files").resolve():
            raise ValueError("Download files must stay inside the result directory.")
        if isinstance(content, bytes):
            target.write_bytes(content)
            return {"name": name, "saved_to": str(target), "bytes": len(content)}
        target.write_text(content, encoding="utf-8", newline="")
        return {"name": name, "saved_to": str(target), "text": content[:LIMIT]}


state = Sandbox()


async def locked(function, *args):
    async with state.lock:
        return await asyncio.to_thread(function, *args)


@asynccontextmanager
async def lifespan(app):
    try:
        yield {}
    finally:
        with anyio.CancelScope(shield=True):
            await locked(state.stop)


mcp = FastMCP("agentcore-code-interpreter", lifespan=lifespan,
              instructions="Run generated Python in the AWS sandbox, not on the local machine. "
                           "The sandbox has no internet access; use preinstalled libraries such as ortools, pulp and pandas. "
                           "Upload inputs with code_upload, write outputs to files and fetch them with code_download. "
                           "Variables and files persist until code_stop. Stop the session when finished.")


@mcp.tool()
async def code_start() -> dict:
    """Start one AWS Code Interpreter session (15 minutes). Returns the session ID."""
    return await locked(state.start)


@mcp.tool()
async def code_upload(name: str) -> dict:
    """Copy data/<name> from the local sample directory into the sandbox working directory."""
    return await locked(state.upload, name)


@mcp.tool()
async def code_run(code: str) -> dict:
    """Execute Python in the sandbox. Returns stdout, stderr and exit code. State persists between calls."""
    return await locked(state.run, code)


@mcp.tool()
async def code_shell(command: str) -> dict:
    """Run one shell command in the sandbox, e.g. to inspect files or installed packages."""
    return await locked(state.shell, command)


@mcp.tool()
async def code_download(name: str) -> dict:
    """Read a file from the sandbox working directory and save a local copy under results/."""
    return await locked(state.download, name)


@mcp.tool()
async def code_stop() -> dict:
    """Stop the AWS session now. Files and variables in the sandbox are discarded."""
    return await locked(state.stop)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8000, help="change when 8000 is used by another local MCP server")
    mcp.run(transport="http", host="127.0.0.1", port=parser.parse_args().port, path="/mcp")
