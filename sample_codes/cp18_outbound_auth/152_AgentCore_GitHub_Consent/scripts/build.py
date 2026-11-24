"""Bundle the pinned SDK so Lambda supports the September 2026 portal APIs."""
from pathlib import Path
import importlib
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    (ROOT / 'build').mkdir(exist_ok=True)
    path = ROOT / 'build/portal-manager.zip'
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as out:
        out.write(ROOT / 'app/portal_handler.py', 'portal_handler.py')
        for name in ['boto3', 'botocore', 's3transfer', 'jmespath', 'dateutil', 'urllib3', 'six']:
            module = importlib.import_module(name)
            source = Path(module.__file__)
            if source.name != '__init__.py':
                out.write(source, source.name)
                continue
            for file in sorted(source.parent.rglob('*')):
                if file.is_file() and '__pycache__' not in file.parts and file.suffix != '.pyc':
                    out.write(file, str(file.relative_to(source.parent.parent)))
    print(f'Built {path.name}: {path.stat().st_size} bytes')


if __name__ == '__main__':
    import argparse
    argparse.ArgumentParser(description=__doc__).parse_args()
    main()
