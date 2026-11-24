"""Gatewayの認可を通った要求に、保存を伴わないデモの受付結果を返す。"""
from typing import Literal
from fastmcp import FastMCP

mcp = FastMCP("VIP presale")


@mcp.tool()
def reserve_product(product_id: Literal["A", "B", "C"]) -> dict:
    """VIP先行販売をデモ予約する。A:限定ミル、B:通常マグ、C:次回ケトル。予約は保存しない。"""
    print("demo_reservation_accepted", flush=True)
    return {"product_id": product_id, "status": "demo_accepted", "persisted": False}


if __name__ == "__main__":
    mcp.run(transport="http", host="0.0.0.0", port=8000, path="/mcp", stateless_http=True)
