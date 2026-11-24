"""架空の1人分の購入履歴。初期化と検索の接続を分ける。"""

import sqlite3
from contextlib import closing
from pathlib import Path

DATA = Path(__file__).resolve().parents[1] / "data"
DATABASE = DATA / "purchases.db"


def initialize_database() -> None:
    if not DATABASE.exists():
        with closing(sqlite3.connect(DATABASE)) as connection:
            with connection:
                connection.executescript((DATA / "seed.sql").read_text(encoding="utf-8"))


def search_purchases(start_date: str, end_date: str, product: str, limit: int) -> list[dict]:
    # 操作、テーブル、返却列、並び順はコード側で固定する。
    sql = """
        SELECT purchase_id, purchased_on, product_name, amount_yen
        FROM purchases
        WHERE purchased_on BETWEEN ? AND ?
          AND instr(product_name, ?) > 0
        ORDER BY purchased_on DESC, purchase_id DESC
        LIMIT ?
    """
    # mode=roはこの接続からの書き込みを禁止する。認証・行単位の認可ではない。
    with closing(sqlite3.connect(DATABASE.as_uri() + "?mode=ro", uri=True)) as connection:
        connection.row_factory = sqlite3.Row
        rows = connection.execute(sql, (start_date, end_date, product, limit)).fetchall()
        return [dict(row) for row in rows]
