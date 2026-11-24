"""Build Linux ARM64 code ZIPs from uv.lock without Docker."""
from pathlib import Path
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
FILES = {
    "worker": ["worker.py", "contracts.py", "prompts.json"],
    "pipeline": ["pipeline.py", "contracts.py"],
}


def main():
    build = ROOT / "build"
    build.mkdir(exist_ok=True)
    requirements = build / "requirements.txt"
    subprocess.run(["uv", "export", "--frozen", "--no-dev", "--no-emit-project", "--format", "requirements-txt",
                    "--output-file", str(requirements)], cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    with tempfile.TemporaryDirectory(dir=build) as staging:
        subprocess.run(["uv", "pip", "install", "--python-platform", "aarch64-manylinux2014", "--python-version", "3.14",
            "--only-binary=:all:", "--no-compile-bytecode", "--require-hashes", "--target", staging,
            "-r", str(requirements)], cwd=ROOT, check=True)
        stage = Path(staging)
        dependencies = [(p.relative_to(stage).as_posix(), p) for p in sorted(stage.rglob("*"))
                        if p.is_file() and "__pycache__" not in p.parts]
        for name, files in FILES.items():
            artifact = build / f"{name}.zip"
            with zipfile.ZipFile(artifact, "w", compression=zipfile.ZIP_DEFLATED) as archive:
                for relative, path in dependencies + [(f, ROOT / "app" / f) for f in files]:
                    info = zipfile.ZipInfo(relative, (2020, 1, 1, 0, 0, 0))
                    info.create_system = 3
                    info.external_attr = 0o100755 << 16
                    info.compress_type = zipfile.ZIP_DEFLATED
                    archive.writestr(info, path.read_bytes())
            print(f"Built {artifact.name}: {artifact.stat().st_size:,} bytes")


if __name__ == "__main__":
    main()
