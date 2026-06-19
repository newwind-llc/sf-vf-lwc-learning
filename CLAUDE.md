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

## デプロイ／検証の運用ガードレール（厳守）

学習・開発時の事故と無料枠の浪費を防ぐためのハードルール。**ユーザーが明示的に指示しない限り、エージェントは以下を破らない。**

1. **本番（Developer Edition 本番 org）への直接デプロイ禁止。** `sf project deploy start`（push 型の実デプロイ）で DE 本番へ直接書き込まない。本番反映は必ず **`main` への push → GitHub Actions `deploy-prod.yml`（JWT）経由**で行う。エージェントが DE 本番に対して実行してよいのは **check-only の `sf project deploy validate`（無変更の検証）まで**。実デプロイ（変更の書き込み）・push・PR・merge はユーザー操作に委ねる。
2. **検証時に新規 scratch org を作らない。** `sf org create scratch` を勝手に実行しない。無料 DE DevHub の scratch は「**同時 3 / 1 日 6**」上限があり、使い切ると CI まで詰む。検証は **既存の有効な scratch（例: `rep-test`）を再利用**するか、**DE への check-only validate** で行う。既存 scratch が失効・不足して新規作成が必要になったら、**作る前に必ずユーザーへ確認**する。
3. **GUI（宣言的）変更は必ず source tracking で repo に取り込む。repo を source of truth に保つ。** 作業開始前に `sf project retrieve preview -o <org>` で「org 側だけにある変更」を確認し、必要なものは `sf project retrieve start` で取り込んでからコミットする。検証中に GUI で設定を変えたら（例: Lightning ページの有効化＝`CustomApplication` の `actionOverrides`）、その差分も同様に retrieve して反映し、**GUI のみ・repo 外の状態を残さない**。ただし Metadata API 非対応の設定（例: プロファイル/権限セットの割り当て等）はソース管理できないため、**手作業として手順化**する（対応可否は Metadata Coverage Report で確認）。

> 背景: CI（`pr-validate.yml`）も同じ DE DevHub の scratch 上限を消費するため、現在は上限回避で「DE へ check-only validate」モード（B）に切替中。ローカル検証で scratch を量産すると CI が回らなくなる。

## 信頼できる出典（これ以外を一次情報として断定に使わない）

- `help.salesforce.com` / `developer.salesforce.com` / `architect.salesforce.com` / `trailhead.salesforce.com` / `successjp.salesforce.com`（サクセスナビ｜日本語の操作手順・活用ガイド。仕様/上限の確定は help で裏取り） / Release Notes
- 公式 GitHub: `github.com/forcedotcom` / `github.com/trailheadapps`（学習用サンプル。デプロイ前にコード確認）

SF 仕様の質問に答えるときの手順・回答フォーマットは **`sf-kintone-grounded-qa` スキル**に従う。
