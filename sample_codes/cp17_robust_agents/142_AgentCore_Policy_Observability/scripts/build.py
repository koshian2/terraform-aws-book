"""ロック済みの依存からLinux ARM64 / Python 3.14用ZIPを作ります。"""

from pathlib import Path
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    build = ROOT / "build"
    build.mkdir(exist_ok=True)
    requirements = build / "requirements.txt"
    subprocess.run(
        ["uv", "export", "--frozen", "--no-dev", "--no-emit-project",
         "--format", "requirements-txt", "--output-file", str(requirements)],
        cwd=ROOT, check=True, stdout=subprocess.DEVNULL,
    )
    with tempfile.TemporaryDirectory(dir=build) as staging:
        subprocess.run(
            ["uv", "pip", "install", "--python-platform", "aarch64-manylinux2014",
             "--python-version", "3.14", "--only-binary=:all:", "--no-compile-bytecode",
             "--require-hashes", "--target", staging, "-r", str(requirements)],
            cwd=ROOT, check=True,
        )
        stage = Path(staging)
        (stage / "server.py").write_bytes((ROOT / "app/server.py").read_bytes())
        artifact = build / "runtime.zip"
        with zipfile.ZipFile(artifact, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for path in sorted(stage.rglob("*")):
                if path.is_file() and "__pycache__" not in path.parts:
                    info = zipfile.ZipInfo(path.relative_to(stage).as_posix(), (2020, 1, 1, 0, 0, 0))
                    info.create_system = 3
                    info.external_attr = 0o100755 << 16
                    info.compress_type = zipfile.ZIP_DEFLATED
                    archive.writestr(info, path.read_bytes())
        print(f"Built {artifact} ({artifact.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
