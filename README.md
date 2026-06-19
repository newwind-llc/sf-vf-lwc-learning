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

### ⚡ Apex + LWC — 商談カンバン（パイプライン）ボード（実装済み）

取引先レコードページ上で、関連商談をステージ別のカンバンに並べ、**カードをドラッグ&ドロップしてステージを更新**。列ごとの金額合計はその場でライブ再計算されます。

➡ **スクリーンショット / GIF 付き解説：[docs/LWC_OPPORTUNITY_KANBAN_SHOWCASE.md](./docs/LWC_OPPORTUNITY_KANBAN_SHOWCASE.md)**

- LWC `opportunityKanban` ＋ `@AuraEnabled` Apex（読み取り `WITH USER_MODE` / 更新 `AccessLevel.USER_MODE`）
- `@wire` ＋ HTML5 ドラッグ&ドロップ ＋ `refreshApex`、ステージ見出しは日本語表示
- 配置（FlexiPage・Sales アプリのページ割り当て）まで**メタデータでコード管理**
- ここで **ESLint / Jest** が本領を発揮（LWC Jest 5 ケース）

## CI/CD

GitHub Actions による自動化。ブランチ戦略は **feature → PR → `develop` →（リリース）→ `main`**。VF 帳票・LWC カンバンとも同じパイプラインで検証・デプロイされます。

### ワークフロー（3 本）

| ワークフロー      | トリガー                   | 内容                                                                                                                                                                 | 認証       |
| ----------------- | -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| `pr-validate.yml` | `develop` への PR          | **現在：DE 組織へ `sf project deploy validate`（check-only ＋ `RunLocalTests`）**＝コンパイル/構成検証＋Apex テスト（DE は変更しない）。scratch 方式もコメントで温存 | JWT Bearer |
| `quality.yml`     | `develop` / `main` への PR | 静的解析・整形・セキュリティの各種チェック（下表）。org 不要で高速                                                                                                   | 不要       |
| `deploy-prod.yml` | `main` への push（マージ） | **Developer Edition 本番へ自動デプロイ**（`force-app` を `RunLocalTests` 付きで）。Apex/LWC に加え FlexiPage・アプリ割り当ても反映                                   | JWT Bearer |

> 無料 DE は scratch 作成が「1 日 6 個」上限のため、PR 検証は現在 scratch を作らず DE へ check-only validate にしている（`pr-validate.yml` 冒頭の手順で scratch 方式に戻せる）。JWT は新規 scratch にログインできないため、scratch 作成時は SFDX Auth URL を使う。

### `quality.yml` の各種チェッカー

| チェック         | ツール                                            | 見るもの                                                          |
| ---------------- | ------------------------------------------------- | ----------------------------------------------------------------- |
| シークレット検出 | **TruffleHog**                                    | ハードコードされた鍵・トークン・秘密鍵（誤コミット防止）          |
| コード整形       | **Prettier**                                      | Apex/VF/XML/JS/MD 等のフォーマット統一（`prettier:verify`）       |
| JS 静的解析      | **ESLint**                                        | LWC/Aura JavaScript のバグ・アンチパターン                        |
| LWC 単体テスト   | **Jest**（`sfdx-lwc-jest`）                       | LWC コンポーネントのテスト                                        |
| Apex/JS 静的解析 | **Salesforce Code Analyzer**（PMD / RetireJS 等） | Apex のベストプラクティス・セキュリティ、脆弱な JS ライブラリ検出 |

### 品質の担保

- **Apex テスト**：VF 帳票はカバレッジ 100%、LWC カンバンは 98%（本番デプロイの 75% 要件を満たす）。
- PR のチェックが全て緑でないとマージできないゲートとして機能（ブランチ保護を想定）。
- ローカルでも **husky の pre-commit** で Prettier / ESLint / Jest が走り、コミット前にも弾く二重チェック。
- ボタン配置・ページ割り当てなど**宣言的設定もメタデータでコード管理**し、手動 UI 設定をなくして再現性を確保。

セットアップ手順：[docs/CICD-SETUP.md](./docs/CICD-SETUP.md)

## ドキュメント

| ドキュメント                                                                         | 内容                                                                   |
| ------------------------------------------------------------------------------------ | ---------------------------------------------------------------------- |
| [docs/VF_SHOWCASE.md](./docs/VF_SHOWCASE.md)                                         | VF 帳票（請求書）のショーケース（スクショ付き）                        |
| [docs/LWC_OPPORTUNITY_KANBAN_SHOWCASE.md](./docs/LWC_OPPORTUNITY_KANBAN_SHOWCASE.md) | LWC 商談カンバン（D&D・ライブ集計）のショーケース（スクショ/GIF 付き） |
| [docs/CICD-SETUP.md](./docs/CICD-SETUP.md)                                           | CI/CD（GitHub Actions + Salesforce）セットアップ手順                   |
