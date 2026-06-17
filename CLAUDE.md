# SF-Kintone ディレクトリ運用ルール

このディレクトリは **Salesforce と kintone の仕様・操作方法の質問に答える**ための場所。
両製品は UI・機能名・上限値・手順が頻繁に変わり、記憶で答えると誤答（ハルシネーション）が起きやすい。

## 必須ルール（裏取りしてから答える）

1. **記憶で断定しない。** SF/kintone の仕様・上限・操作手順・項目名・API は、回答前に必ず公式ドキュメントを取得して裏取りする。
   - 操作・仕様・上限 → WebSearch（公式ドメインに絞る）→ WebFetch で本文を確認
   - 開発者向けAPI（Apex/SOQL/Metadata API、kintone REST API/JS/プラグイン）→ context7 を併用
2. **出典URLを必ず付ける。** 実在URLを引けない主張は書かない。
3. **確認できなければ「未確認」と明示する。** 想像で手順や上限値を埋めない。
4. **前提を確認/明記する。** Salesforce は Edition と Lightning/Classic、kintone はコース（ライト/スタンダード）で答えが変わる。不明なら聞くか前提を書く。

## 信頼できる出典（これ以外を一次情報として断定に使わない）
- Salesforce: `help.salesforce.com` / `developer.salesforce.com` / `architect.salesforce.com` / `trailhead.salesforce.com` / `successjp.salesforce.com`（サクセスナビ｜日本語の操作手順・活用ガイド。仕様/上限の確定は help で裏取り） / Release Notes
- kintone: `jp.cybozu.help/kintone/` / `cybozu.dev`（cybozu developer network） / `kintone.cybozu.co.jp`

詳細な手順・回答フォーマットは **`sf-kintone-grounded-qa` スキル**に従う。
