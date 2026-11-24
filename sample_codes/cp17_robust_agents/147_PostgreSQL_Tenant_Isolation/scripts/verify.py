"""PostgreSQLの実アクセスでRLSとテナント別ビューを比較する。"""
from datetime import datetime, timezone
import json
from pathlib import Path

import psycopg
from psycopg import sql

PASSWORDS = {
    "rls_app": "local-rls-demo-only",
    "view_a": "local-view-a-demo-only",
    "view_b": "local-view-b-demo-only",
}
EXPECTED = {
    "tenant-a": [["tenant-a", "T001", "商品が届きません。"]],
    "tenant-b": [["tenant-b", "T001", "請求書の宛名を変更してください。"]],
}
RECORDS = []
SELECT_ALL = "SELECT tenant_id, ticket_id, body FROM rls_demo.inquiries ORDER BY ticket_id"


def check(case, actual, expected):
    matched = actual == expected
    RECORDS.append({"case": case, "actual": actual, "expected": expected, "matched": matched})
    print(f"{'PASS' if matched else 'FAIL'}: {case}")
    if not matched:
        raise AssertionError(f"Unexpected result: {case}")


def connect(user):
    # 管理者の認証情報は検証コンテナへ渡さない。
    return psycopg.connect(user=user, password=PASSWORDS[user], autocommit=True)


def rows(conn, query, params=None):
    return [list(row) for row in conn.execute(query, params).fetchall()]


def check_role(conn, user):
    role = conn.execute("SELECT current_user, rolsuper, rolbypassrls FROM pg_roles WHERE rolname = current_user").fetchone()
    check(f"{user}: restricted login role", list(role), [user, False, False])


def denied(conn, case, query, params=None):
    try:
        with conn.transaction():
            conn.execute(query, params).fetchall()
    except psycopg.errors.InsufficientPrivilege as exc:
        check(case, exc.sqlstate, "42501")
    else:
        check(case, "unexpectedly allowed", "42501")


def verify_rls():
    with connect("rls_app") as conn:
        check_role(conn, "rls_app")
        check("RLS: missing tenant returns no rows", rows(conn, SELECT_ALL), [])
        # 1本の接続をA→B→Aで再利用し、トランザクション終了後の残留も検証する。
        for number, tenant in enumerate(("tenant-a", "tenant-b", "tenant-a"), 1):
            other = "tenant-b" if tenant == "tenant-a" else "tenant-a"
            with conn.transaction():
                conn.execute("SELECT set_config('app.tenant_id', %s, true)", (tenant,))
                check(f"RLS {number}: {tenant} SELECT without tenant WHERE", rows(conn, SELECT_ALL), EXPECTED[tenant])
                check(f"RLS {number}: explicit foreign tenant returns no rows", rows(conn,
                      "SELECT tenant_id, ticket_id, body FROM rls_demo.inquiries WHERE tenant_id = %s", (other,)), [])
            check(f"RLS {number}: tenant cleared after commit", rows(conn, SELECT_ALL), [])
        try:
            with conn.transaction():
                conn.execute("SELECT set_config('app.tenant_id', %s, true)", ("tenant-a",))
                raise RuntimeError("intentional transaction rollback")
        except RuntimeError:
            pass
        check("RLS: tenant cleared after rollback", rows(conn, SELECT_ALL), [])
        with conn.transaction():
            conn.execute("SELECT set_config('app.tenant_id', %s, true)", ("unknown",))
            check("RLS: unknown tenant returns no rows", rows(conn, SELECT_ALL), [])
        denied(conn, "RLS: cannot disable RLS", "ALTER TABLE rls_demo.inquiries DISABLE ROW LEVEL SECURITY")
        denied(conn, "RLS: cannot become owner", "SET ROLE data_owner")
        denied(conn, "RLS: write denied", "DELETE FROM rls_demo.inquiries RETURNING ticket_id")


def verify_views():
    for suffix, tenant in (("a", "tenant-a"), ("b", "tenant-b")):
        other = "b" if suffix == "a" else "a"
        with connect(f"view_{suffix}") as conn:
            check_role(conn, f"view_{suffix}")
            query = sql.SQL("SELECT tenant_id, ticket_id, body FROM view_demo.{} ORDER BY ticket_id").format(
                sql.Identifier(f"tenant_{suffix}"))
            check(f"View {suffix}: own view without WHERE", rows(conn, query), EXPECTED[tenant])
            denied(conn, f"View {suffix}: other view denied",
                   sql.SQL("SELECT * FROM view_demo.{}").format(sql.Identifier(f"tenant_{other}")))
            denied(conn, f"View {suffix}: base table denied", "SELECT * FROM view_demo.inquiries")
            denied(conn, f"View {suffix}: cannot become other tenant", sql.SQL("SET ROLE {}").format(sql.Identifier(f"view_{other}")))
            # セッション変数でビューの固定条件・GRANTを変更できないことも確認する。
            with conn.transaction():
                conn.execute("SELECT set_config('app.tenant_id', %s, true)", (f"tenant-{other}",))
                check(f"View {suffix}: tenant setting cannot switch view", rows(conn, query), EXPECTED[tenant])


def main():
    failure = None
    try:
        verify_rls()
        verify_views()
    except Exception as exc:
        failure = {"type": type(exc).__name__, "message": str(exc)}
        raise
    finally:
        path = Path("results") / ("verification-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ") + ".json")
        path.parent.mkdir(exist_ok=True)
        path.write_text(json.dumps({"checks": RECORDS, "error": failure,
                        "all_matched": failure is None and bool(RECORDS) and all(r["matched"] for r in RECORDS)},
                        ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"記録: {path}")
    print("PASS: all expected results matched")


if __name__ == "__main__":
    main()
