import os
import json
import random
import logging
from pathlib import Path
from typing import Optional, Dict, Any
from urllib.parse import urlencode

from locust import HttpUser, task, between, tag, events, LoadTestShape

# =========================================
# Logger
# =========================================
logger = logging.getLogger("locust")

# =========================================
# locustfile のディレクトリ（相対パス解決用）
# =========================================
_LOCUSTFILE_DIR = Path(__file__).resolve().parent

# =========================================================
# 可変パラメータ（環境変数で調整）
# =========================================================
CPU_ITERS   = int(os.getenv("CPU_ITERS", "200000"))
CPU_ROUNDS  = int(os.getenv("CPU_ROUNDS", "4"))

MEM_MB      = int(os.getenv("MEM_MB", "64"))
MEM_MS      = int(os.getenv("MEM_MS", "500"))

JSON_KB     = int(os.getenv("JSON_KB", "256"))

IO_KB       = int(os.getenv("IO_KB", "512"))

MIX_ITERS   = int(os.getenv("MIX_ITERS", "150000"))
MIX_KB      = int(os.getenv("MIX_KB", "128"))
MIX_SLEEPMS = int(os.getenv("MIX_SLEEPMS", "50"))

WAIT_MIN_S  = float(os.getenv("WAIT_MIN_S", "0.05"))
WAIT_MAX_S  = float(os.getenv("WAIT_MAX_S", "0.2"))

CONNECT_TIMEOUT = float(os.getenv("CONNECT_TIMEOUT", "3.0"))
READ_TIMEOUT    = float(os.getenv("READ_TIMEOUT", "30.0"))

# =========================================
# CLI 引数追加（--stages-file）
# =========================================
@events.init_command_line_parser.add_listener
def _add_cli_args(parser):
    parser.add_argument(
        "--stages-file",
        dest="stages_file",
        type=str,
        default=None,
        help="Path to stages JSON (relative path is resolved from locustfile directory)"
    )

# =========================================
# CLI 引数を受けて shape を差し替える
# =========================================
@events.init.add_listener
def _capture_cli_and_set_shape(environment, **kwargs):
    # 1) 受け取った値（未指定なら "stages.json"）
    raw = getattr(environment.parsed_options, "stages_file", None) or "stages.json"
    raw_path = Path(raw).expanduser()

    # 2) 相対なら locustfile.py の場所基準で解決
    resolved = raw_path if raw_path.is_absolute() else (_LOCUSTFILE_DIR / raw_path).resolve()

    # 3) shape を明示的にインスタンス化して差し替え
    environment.shape_class = StepLoadShape(resolved)
    logger.info(f"[Locust Init] stages path resolved to: {resolved}")

# =========================================================
# ユーザー挙動（各エンドポイント用タスク）
# =========================================================
class AppUser(HttpUser):
    """
    各エンドポイントを叩く一般ユーザー。
    タグで特定エンドポイントのみ実行可能（例: --tags cpu）
    """
    wait_time = between(WAIT_MIN_S, WAIT_MAX_S)

    def _get(self, path: str, name: Optional[str] = None, params: Optional[Dict[str, Any]] = None):
        qs = f"?{urlencode(params)}" if params else ""
        return self.client.get(
            f"{path}{qs}",
            name=name or path,
            timeout=(CONNECT_TIMEOUT, READ_TIMEOUT),
            catch_response=True,  # 失敗判定を呼び出し側で行う
        )

    def on_start(self):
        # 簡易ウォームアップ
        with self._get("/", name="GET / (warmup)") as r:
            if r.status_code != 200:
                r.failure(f"HTTP {r.status_code}")
            else:
                r.success()

    @task(2)  # ルートは軽めの多頻度
    @tag("root")
    def root(self):
        with self._get("/", name="GET /") as r:
            if r.status_code != 200:
                r.failure(f"HTTP {r.status_code}")
            else:
                r.success()

    @task(1)
    @tag("cpu")
    def cpu(self):
        iters  = max(10000, int(CPU_ITERS * random.uniform(0.8, 1.2)))
        rounds = max(1, int(CPU_ROUNDS * random.uniform(0.8, 1.2)))
        with self._get("/cpu", name="GET /cpu", params={"iters": iters, "rounds": rounds}) as r:
            if r.status_code != 200:
                r.failure(f"HTTP {r.status_code}")
                return
            try:
                data = r.json()
                if data.get("kind") != "cpu":
                    r.failure(f'kind mismatch: expected "cpu", got "{data.get("kind")}"')
                else:
                    r.success()
            except Exception as e:
                r.failure(f"JSON parse error: {e}")

    @task(1)
    @tag("mem")
    def mem(self):
        mb = max(1, int(MEM_MB * random.uniform(0.8, 1.2)))
        ms = max(1, int(MEM_MS * random.uniform(0.8, 1.2)))
        with self._get("/mem", name="GET /mem", params={"mb": mb, "ms": ms}) as r:
            if r.status_code != 200:
                r.failure(f"HTTP {r.status_code}")
                return
            try:
                data = r.json()
                if data.get("kind") != "mem":
                    r.failure(f'kind mismatch: expected "mem", got "{data.get("kind")}"')
                else:
                    r.success()
            except Exception as e:
                r.failure(f"JSON parse error: {e}")

    @task(1)
    @tag("json")
    def big_json(self):
        kb = max(1, int(JSON_KB * random.uniform(0.8, 1.2)))
        with self._get("/json", name="GET /json", params={"kb": kb}) as r:
            if r.status_code != 200:
                r.failure(f"HTTP {r.status_code}")
                return
            # 形式検証が必要ならここで r.json() を見る
            r.success()

    @task(1)
    @tag("io")
    def io(self):
        kb = max(1, int(IO_KB * random.uniform(0.8, 1.2)))
        with self._get("/io", name="GET /io", params={"kb": kb}) as r:
            if r.status_code != 200:
                r.failure(f"HTTP {r.status_code}")
                return
            try:
                data = r.json()
                if data.get("kind") != "io":
                    r.failure(f'kind mismatch: expected "io", got "{data.get("kind")}"')
                else:
                    r.success()
            except Exception as e:
                r.failure(f"JSON parse error: {e}")

    @task(1)
    @tag("mix")
    def mix(self):
        iters   = max(10000, int(MIX_ITERS * random.uniform(0.8, 1.2)))
        kb      = max(1, int(MIX_KB * random.uniform(0.8, 1.2)))
        sleepms = max(0, int(MIX_SLEEPMS * random.uniform(0.8, 1.2)))
        with self._get("/mix", name="GET /mix",
                       params={"iters": iters, "kb": kb, "sleep_ms": sleepms}) as r:
            if r.status_code != 200:
                r.failure(f"HTTP {r.status_code}")
                return
            try:
                data = r.json()
                if data.get("kind") != "mix":
                    r.failure(f'kind mismatch: expected "mix", got "{data.get("kind")}"')
                else:
                    r.success()
            except Exception as e:
                r.failure(f"JSON parse error: {e}")

# =========================================================
# ステップロード形状
# =========================================================
_DEFAULT_STAGES = [
    {"duration": 60,  "users": 100, "spawn_rate": 50},
    {"duration": 120, "users": 200, "spawn_rate": 50},
    {"duration": 180, "users": 400, "spawn_rate": 100},
]

def _load_stages_json(path: Path):
    """
    path で指定された JSON を読み込む。スキーマ:
      [{"duration": <sec>, "users": <int>, "spawn_rate": <float>}, ...]
    戻り値: (stages or None, メッセージ)
    """
    if not path.exists():
        return None, f'no stages json found: "{path}"'
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(data, list):
            return None, "stages json must be a list"
        for i, s in enumerate(data):
            if not isinstance(s, dict):
                return None, f"stage[{i}] must be an object"
            for k in ("duration", "users", "spawn_rate"):
                if k not in s:
                    return None, f"stage[{i}] missing key: {k}"
        return data, f'loaded "{path}"'
    except Exception as e:
        return None, f'failed to load "{path}": {e}'

class StepLoadShape(LoadTestShape):
    """
    形状はコンストラクタで渡された JSON を優先。
    見つからない/不正なら _DEFAULT_STAGES にフォールバック。
    Web UI（非 headless）でも LoadTestShape が優先される。
    """
    def __init__(self, stages_path: Optional[Path] = None):
        self._stages_path = stages_path

        if stages_path is None:
            # Locust の自動インスタンス化（引数なし）に対応：一旦デフォルト
            self.stages = _DEFAULT_STAGES
            self._source = "deferred: no stages path yet -> using _DEFAULT_STAGES"
        else:
            stages, msg = _load_stages_json(stages_path)
            self.stages = stages if stages else _DEFAULT_STAGES
            self._source = msg if stages is not None else f"{msg} -> fallback to _DEFAULT_STAGES"

        total = 0
        self.timeline = []
        for s in self.stages:
            total += int(s["duration"])
            self.timeline.append((total, int(s["users"]), float(s["spawn_rate"])))

    def tick(self):
        run_time = self.get_run_time()
        for cutoff, users, spawn in self.timeline:
            if run_time <= cutoff:
                return users, spawn
        return None  # 全ステージ終了 → テスト停止

# =========================================================
# ログ：開始時に設定を出力
# =========================================================
@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    src = getattr(environment.shape_class, "_source", "default")
    logger.info(
        "[Locust Test Start] "
        f"stage source: {src} | "
        f"CPU_ITERS={CPU_ITERS}, CPU_ROUNDS={CPU_ROUNDS}, "
        f"MEM_MB={MEM_MB}, MEM_MS={MEM_MS}, JSON_KB={JSON_KB}, IO_KB={IO_KB}, "
        f"MIX_ITERS={MIX_ITERS}, MIX_KB={MIX_KB}, MIX_SLEEPMS={MIX_SLEEPMS}, "
        f"WAIT=({WAIT_MIN_S},{WAIT_MAX_S}), TIMEOUT=({CONNECT_TIMEOUT},{READ_TIMEOUT})"
    )
