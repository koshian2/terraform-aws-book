\set ON_ERROR_STOP on
BEGIN;
REVOKE ALL ON DATABASE tenant_demo FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

-- 教材専用の固定パスワード。コンテナ内ネットワークだけで使用する。
CREATE ROLE data_owner NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE rls_app LOGIN PASSWORD 'local-rls-demo-only'
    NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE;
CREATE ROLE view_a LOGIN PASSWORD 'local-view-a-demo-only'
    NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE;
CREATE ROLE view_b LOGIN PASSWORD 'local-view-b-demo-only'
    NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE;
GRANT CONNECT ON DATABASE tenant_demo TO rls_app, view_a, view_b;

CREATE SCHEMA rls_demo AUTHORIZATION data_owner;
CREATE SCHEMA view_demo AUTHORIZATION data_owner;
SET ROLE data_owner;

-- RLSとビューを独立して比較するため、同じデータを別テーブルに入れる。
CREATE TABLE rls_demo.inquiries (
    tenant_id text NOT NULL,
    ticket_id text NOT NULL,
    body text NOT NULL,
    PRIMARY KEY (tenant_id, ticket_id)
);
INSERT INTO rls_demo.inquiries VALUES
    ('tenant-a', 'T001', '商品が届きません。'),
    ('tenant-b', 'T001', '請求書の宛名を変更してください。');
CREATE TABLE view_demo.inquiries (LIKE rls_demo.inquiries INCLUDING ALL);
INSERT INTO view_demo.inquiries SELECT * FROM rls_demo.inquiries;

ALTER TABLE rls_demo.inquiries ENABLE ROW LEVEL SECURITY;
ALTER TABLE rls_demo.inquiries FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_read ON rls_demo.inquiries
    FOR SELECT TO rls_app
    USING (tenant_id = NULLIF(current_setting('app.tenant_id', true), ''));
GRANT USAGE ON SCHEMA rls_demo TO rls_app;
GRANT SELECT ON rls_demo.inquiries TO rls_app;

-- ビュー所有者の権限で元テーブルを読み、利用者にはビューのみを許可する。
CREATE VIEW view_demo.tenant_a WITH (security_barrier = true) AS
    SELECT tenant_id, ticket_id, body FROM view_demo.inquiries
    WHERE tenant_id = 'tenant-a';
CREATE VIEW view_demo.tenant_b WITH (security_barrier = true) AS
    SELECT tenant_id, ticket_id, body FROM view_demo.inquiries
    WHERE tenant_id = 'tenant-b';
GRANT USAGE ON SCHEMA view_demo TO view_a, view_b;
GRANT SELECT ON view_demo.tenant_a TO view_a;
GRANT SELECT ON view_demo.tenant_b TO view_b;
RESET ROLE;
COMMIT;
