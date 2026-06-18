# sf-vf-lwc-learning

Salesforce の **VisualForce / Apex / LWC** を、実装しながら学ぶプロジェクト。
取引先（Account）を題材に、**帳票（VF）** と **リッチ UI（LWC）** の2系統を、**CI/CD（GitHub Actions）** 込みで構築します。

## 目次

### 🧾 VisualForce — 月次売上締め請求書（実装済み）

取引先詳細のボタンから、当月に成立（Closed Won）した商談を集計し、**日本の請求書レイアウトの帳票（プレビュー & A4 PDF）** を出力します。

➡ **スクリーンショット付き解説：[docs/VF_SHOWCASE.md](./docs/VF_SHOWCASE.md)**

- VF 2ページ（プレビュー HTML / `renderAs="pdf"`）＋ Apex 拡張コントローラ（`WITH USER_MODE`）
- 取引先カスタムボタン（**ページレイアウトもコード管理**）
- 消費税計算・明細固定行・インボイス制度の記載項目に準拠

### ⚡ Apex + LWC — リッチ UI（予定）

`@AuraEnabled` Apex ＋ Lightning Web Components によるリッチ UI ページ。**今後実装予定。**（CI の ESLint / Jest がここで本領を発揮します）

## CI/CD

GitHub Actions による自動化：

- **PR（`develop`）** → 使い捨て scratch org で検証＋Apex テスト（カバレッジ）
- **PR** → 各種チェック（TruffleHog / Prettier / ESLint / Jest / Salesforce Code Analyzer）
- **`main` マージ** → Developer Edition 本番へ自動デプロイ（JWT Bearer）
- セットアップ手順：[docs/CICD-SETUP.md](./docs/CICD-SETUP.md)

## ドキュメント

| ドキュメント                                 | 内容                                                 |
| -------------------------------------------- | ---------------------------------------------------- |
| [docs/VF_SHOWCASE.md](./docs/VF_SHOWCASE.md) | VF 帳票（請求書）のショーケース（スクショ付き）      |
| [docs/CICD-SETUP.md](./docs/CICD-SETUP.md)   | CI/CD（GitHub Actions + Salesforce）セットアップ手順 |
