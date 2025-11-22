from flask import Flask, request, jsonify, Response
import time, json, hashlib, secrets, mmap
import socket, urllib.request, urllib.error

app = Flask(__name__)

# --- IMDSv2でprivate DNS/IPを取得（失敗時はソケットでフォールバック） ---
_IMDS_BASE = "http://169.254.169.254/latest"
_cached_meta = {}

def _get_imds_token(timeout=0.2):
    req = urllib.request.Request(
        f"{_IMDS_BASE}/api/token",
        method="PUT",
        headers={"X-aws-ec2-metadata-token-ttl-seconds": "60"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read().decode("utf-8")

def _get_imds(path, token, timeout=0.2):
    req = urllib.request.Request(
        f"{_IMDS_BASE}/meta-data/{path}",
        headers={"X-aws-ec2-metadata-token": token},
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read().decode("utf-8")

def get_private_identity():
    """(private_dns, private_ip) を返す。最初の呼び出し時だけIMDSに当ててキャッシュ。"""
    global _cached_meta
    if _cached_meta:
        return _cached_meta["dns"], _cached_meta["ip"]

    # まずIMDSv2
    try:
        token = _get_imds_token()
        priv_ip  = _get_imds("local-ipv4", token)
        priv_dns = _get_imds("local-hostname", token)
        _cached_meta = {"dns": priv_dns, "ip": priv_ip}
        return priv_dns, priv_ip
    except Exception:
        # フォールバック: ソケット解決（DNSはホスト名、IPはプライベートIP）
        try:
            hn = socket.gethostname()
            ip = socket.gethostbyname(hn)
            _cached_meta = {"dns": hn, "ip": ip}
            return hn, ip
        except Exception:
            # 最後の最後の保険
            return "unknown.local", "127.0.0.1"

def to_int(q, name, default, lo=None, hi=None):
    try:
        v = int(q.get(name, default))
        if lo is not None and v < lo: v = lo
        if hi is not None and v > hi: v = hi
        return v
    except Exception:
        return default
    
@app.get("/")
def root():
    priv_dns, priv_ip = get_private_identity()
    body = f"Hello from {priv_dns} ({priv_ip})\n"
    return body, 200, {"Content-Type": "text/plain"}

@app.get("/health")
def health():
    return "ok", 200, {"Content-Type": "text/plain"}

@app.get("/cpu")
def cpu():
    iters  = to_int(request.args, "iters", 200_000, 10_000, 2_000_000)
    rounds = to_int(request.args, "rounds", 4, 1, 64)
    t0 = time.perf_counter()
    pw = b"p"*64; dig = None
    for _ in range(rounds):
        dig = hashlib.pbkdf2_hmac("sha256", pw, secrets.token_bytes(16), iters, dklen=32)
    return jsonify(kind="cpu", iters=iters, rounds=rounds,
                   seconds=time.perf_counter()-t0, hex=dig.hex())

@app.get("/mem")
def mem():
    mb = to_int(request.args, "mb", 64, 1, 1024)
    ms = to_int(request.args, "ms", 500, 1, 60_000)
    t0 = time.perf_counter()
    buf = bytearray(mb*1024*1024)
    for i in range(0, len(buf), 4096): buf[i] = (i//4096) & 0xFF
    time.sleep(ms/1000.0)
    res = jsonify(kind="mem", mb=mb, ms=ms, seconds=time.perf_counter()-t0, sample=int(buf[0]))
    del buf
    return res

@app.get("/json")
def big_json():
    kb = to_int(request.args, "kb", 256, 1, 8192)
    s  = "x" * (kb*1024)
    t0 = time.perf_counter()
    body = json.dumps({"size_kb": kb, "data": s})
    return Response(body, mimetype="application/json",
                    headers={"X-Serialize-Seconds": f"{time.perf_counter()-t0:.6f}"})

@app.get("/io")
def io():
    kb   = to_int(request.args, "kb", 512, 1, 16384)
    path = "/opt/app/blob.bin"
    t0 = time.perf_counter()
    h = hashlib.sha256(); read_bytes = 0
    with open(path, "rb") as f:
        mm = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
        bs = kb*1024; pos = 0
        while read_bytes < bs:
            chunk = mm[pos:min(pos+65536, mm.size())]
            if not chunk: pos = 0; continue
            h.update(chunk); read_bytes += len(chunk); pos += len(chunk)
        mm.close()
    return jsonify(kind="io", kb=kb, seconds=time.perf_counter()-t0, sha256=h.hexdigest())

@app.get("/mix")
def mix():
    iters  = to_int(request.args, "iters", 150_000, 10_000, 2_000_000)
    kb     = to_int(request.args, "kb", 128, 1, 4096)
    sleepm = to_int(request.args, "sleep_ms", 50, 0, 5000)
    t0 = time.perf_counter()
    d1 = hashlib.pbkdf2_hmac("sha256", b"p"*64, b"salt", iters, dklen=32)
    s  = json.dumps({"blob": "y"*(kb*1024)})
    time.sleep(sleepm/1000)
    return jsonify(kind="mix", iters=iters, kb=kb, sleep_ms=sleepm,
                   seconds=time.perf_counter()-t0, hex=d1.hex(), json_len=len(s))

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
