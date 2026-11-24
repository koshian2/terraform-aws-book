# 出力仕様

`artifacts/expenses.csv`をUTF-8で作る。画像1枚につき1行、同じ画像名を重複させない。

列は `source_file,receipt_id,date,merchant,amount_yen,category,status,duplicate_of,reason`。
日付はYYYY-MM-DD、金額は整数円。読み取れない値は空欄にして確認する。duplicate_ofは原本のsource_file、該当しなければ空欄。
statusは confirmed / needs_confirmation / duplicate_pending / duplicate / excluded のいずれか。
confirmedだけを計上する。他の状態は金額が読めても集計対象外。

`questions.json`は配列。未解決の質問を `{"source_file":"...","question":"..."}` として列挙する。解決した質問は取り除き、すべて解決したら空配列とする。
`summary.json`は `{"image_count":整数,"confirmed_count":整数,"confirmed_total_yen":整数,"pending_count":整数,"duplicate_count":整数}`。pending_countはneeds_confirmationとduplicate_pendingの合計、duplicate_countはduplicateのみ。
`notes.md`には処理の根拠と確認回答を日本語で残す。計算・出力に生成コードを使った場合はそのソースもartifacts/に保存する。
