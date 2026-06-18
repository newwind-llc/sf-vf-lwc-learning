# sf-vf-lwc-learning プロジェクト運用ルール

この repo は **Salesforce の VisualForce / Apex / LWC を実装しながら学ぶ開発プロジェクト**。
作る成果物は **A: VisualForce で帳票(PDF)を出力するページ** と **B: Apex + LWC のリッチ UI ページ**（順序は A → B）。
あわせて **GitHub Actions による CI/CD**（PR→develop で scratch org 検証 / main で Developer Edition 本番へデプロイ、JWT 認証）も本 repo で構築する。

> 親ディレクトリ `../SF-Kintone/` は SF/kintone の仕様 Q&A 用の素の作業フォルダ。本 repo はそこから独立した git リポジトリ＝1 SFDX プロジェクトとして自己完結させる方針。

## このプロジェクトの Serena メモリ

Serena のアクティブ化はグローバル `~/.claude/CLAUDE.md` の「Serena MCP 利用時の共通ルール」に従う（cwd のプロジェクトをアクティブ化）。アクティブ化後、Serena メモリ `project_overview_and_handoff` を読んで、これまでの経緯・成果物(A/B)の前提・CI/CD 構成を把握してから着手する。

## 必須ルール（SF 仕様は裏取りしてから答える／実装する）

Salesforce は UI・機能名・上限値・手順・API が頻繁に変わり、記憶で断定すると誤り（ハルシネーション）が起きやすい。実装・回答の前に必ず裏取りする。

1. **記憶で断定しない。** SF の仕様・上限・操作手順・項目名・API（Apex/SOQL/Metadata/VF/LWC/sf CLI/OAuth 等）は、回答・実装前に必ず公式ドキュメントで裏取りする。
   - 操作・仕様・上限 → WebSearch（公式ドメインに絞る）→ WebFetch で本文確認
   - 開発者向け API（Apex/SOQL/Metadata API、LWC、sf CLI 等）→ context7 を併用
2. **出典 URL を必ず付ける。** 実在 URL を引けない主張は書かない。
3. **確認できなければ「未確認」と明示する。** 想像で手順・上限値・コマンドを埋めない。
4. **前提を確認/明記する。** Salesforce は Edition（本プロジェクトは **Developer Edition**）と Lightning/Classic、org 設定で挙動が変わる。不明なら聞くか前提を書く。
   - 注意: `developer.salesforce.com` の atlas 系・`help.salesforce.com` は JavaScript 描画で WebFetch 不可 → Trailhead / 公式 GitHub README / context7（`forcedotcom/sf-skills` 等）で裏取りする。

## 信頼できる出典（これ以外を一次情報として断定に使わない）

- `help.salesforce.com` / `developer.salesforce.com` / `architect.salesforce.com` / `trailhead.salesforce.com` / `successjp.salesforce.com`（サクセスナビ｜日本語の操作手順・活用ガイド。仕様/上限の確定は help で裏取り） / Release Notes
- 公式 GitHub: `github.com/forcedotcom` / `github.com/trailheadapps`（学習用サンプル。デプロイ前にコード確認）

SF 仕様の質問に答えるときの手順・回答フォーマットは **`sf-kintone-grounded-qa` スキル**に従う。
