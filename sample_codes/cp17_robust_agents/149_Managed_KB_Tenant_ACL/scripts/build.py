"""標準ライブラリだけを使うLambdaをZIPにする。"""
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED
from common import ROOT


def main():
    destination = ROOT / 'build'
    destination.mkdir(exist_ok=True)
    for name in ('pre_token', 'interceptor'):
        source = ROOT / 'app' / f'{name}.py'
        compile(source.read_text(encoding='utf-8'), str(source), 'exec')
        with ZipFile(destination / f'{name}.zip', 'w') as archive:
            info = ZipInfo(source.name, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = ZIP_DEFLATED
            archive.writestr(info, source.read_bytes())
        print(f'Built {name}.zip')


if __name__ == '__main__':
    main()
