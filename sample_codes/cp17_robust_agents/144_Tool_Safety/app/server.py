"""購入履歴の検索だけを公開するローカルHTTP MCP。"""

import sqlite3
from datetime import date
from typing import Annotated

from fastmcp import FastMCP
from fastmcp.exceptions import ToolError
from fastmcp.tools import Tool
from pydantic import Field

from storage import initialize_database, search_purchases

mcp = FastMCP("Purchase History", strict_input_validation=True, mask_error_details=True)


def get_purchase_history(
    start_date: Annotated[str, Field(pattern=r"^\d{4}-\d{2}-\d{2}$")],
    end_date: Annotated[str, Field(pattern=r"^\d{4}-\d{2}-\d{2}$")],
    product: Annotated[str, Field(max_length=100)] = "",
    limit: Annotated[int, Field(strict=True, ge=1, le=10)] = 10,
) -> dict:
    """架空の購入履歴を日付の新しい順に取得する。期間は両端を含む。

    日付はYYYY-MM-DD。productは商品名の部分一致（空なら全商品）。
    1回1〜10件。返却項目は購入ID・購入日・商品名・金額のみ。
    SQL実行、変更操作、個人情報・社内メモの取得は提供しない。
    """
    try:
        starts, ends = date.fromisoformat(start_date), date.fromisoformat(end_date)
    except ValueError:
        raise ToolError("invalid_date: 実在する日付をYYYY-MM-DDで指定してください。") from None
    if starts > ends:
        raise ToolError("invalid_period: 開始日は終了日以前にしてください。")
    try:
        purchases = search_purchases(start_date, end_date, product, limit)
    except sqlite3.Error:
        raise ToolError("storage_error: 購入履歴を取得できませんでした。") from None
    return {"count": len(purchases), "purchases": purchases}


# 説明文だけでなく、サーバーが実行時にスキーマを検証する。
tool = Tool.from_function(get_purchase_history)
tool.parameters["additionalProperties"] = False
mcp.add_tool(tool)

if __name__ == "__main__":
    initialize_database()
    mcp.run(transport="http", host="127.0.0.1", port=8000, path="/mcp")
