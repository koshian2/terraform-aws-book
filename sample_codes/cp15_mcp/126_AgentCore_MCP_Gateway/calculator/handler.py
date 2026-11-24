"""Gatewayが渡すツール引数を受け取る、MCPライブラリ不要のLambda。"""
import math


def handler(event, context):
    # この関数で公開するツールはaddだけ。引数はeventの直下に入る。
    values = [event["a"], event["b"]]
    if any(type(value) not in (int, float) or not math.isfinite(value) for value in values):
        raise ValueError("aとbには有限の数値を指定してください。")
    result = values[0] + values[1]
    if not math.isfinite(result):
        raise ValueError("計算結果が数値の範囲を超えました。")
    return {"result": result}
