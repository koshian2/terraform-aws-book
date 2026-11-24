-- すべて架空。非公開列が元データに存在していてもMCPから返さない。
CREATE TABLE purchases (
    purchase_id TEXT PRIMARY KEY,
    purchased_on TEXT NOT NULL,
    product_name TEXT NOT NULL,
    amount_yen INTEGER NOT NULL,
    email TEXT NOT NULL DEFAULT 'fictional@example.invalid',
    shipping_address TEXT NOT NULL DEFAULT '架空県サンプル市 PRIVATE_ADDRESS',
    internal_note TEXT NOT NULL DEFAULT 'PRIVATE_NOTE: 社内確認用'
);
CREATE INDEX purchases_date ON purchases(purchased_on);
INSERT INTO purchases (purchase_id, purchased_on, product_name, amount_yen) VALUES
('P001', '2026-10-01', 'コーヒーミル', 4800),
('P002', '2026-10-02', 'マグカップ', 1200),
('P003', '2026-10-03', 'ペーパーフィルター', 400),
('P004', '2026-10-04', 'コーヒー豆', 1500),
('P005', '2026-10-05', '保存容器', 900),
('P006', '2026-10-06', 'ドリッパー', 1800),
('P007', '2026-10-07', '計量スプーン', 500),
('P008', '2026-10-08', '電気ケトル', 6200),
('P009', '2026-10-09', 'コースター', 600),
('P010', '2026-10-10', 'キッチンクロス', 700),
('P011', '2026-10-11', 'トレー', 2100),
('P012', '2026-10-12', 'コーヒー豆', 1600),
('P013', '2026-10-13', 'Maker''s マグ', 1900),
('P014', '2026-10-14', 'タンブラー', 2500),
('P015', '2026-10-15', 'コーヒーミル用ブラシ', 800);
