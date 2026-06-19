# CI/CD セットアップ手順（GitHub Actions → Salesforce / JWT 認証）

このリポジトリの CI/CD 構成と、動かすための一回限りのセットアップ手順。
**VF 帳票（成果物A）** と **LWC 商談カンバン（成果物B）** を、同じパイプラインで検証・デプロイする。

## 全体像

```
PR → develop      : 【現在=モードB】DE org へ check-only の deploy validate
                    （force-app をコンパイル/構成検証＋Apexテスト。DE は変更しない）
PR → develop/main : quality.yml（org 不要：TruffleHog / Prettier / ESLint / Jest / Code Analyzer）
push → main       : DE org へ deploy（RunLocalTests）＝本番反映
```

- 1 つの **Developer Edition(DE) org** を「**Dev Hub 兼 本番**」として使う（案A の scratch も同じ DE の Dev Hub から作る）。
- CI の無人ログインは **OAuth 2.0 JWT Bearer Flow**（ブラウザ不要）。本番 deploy と現行 PR 検証はどちらも JWT。
- **PR 検証は 2 モードを切替可能**（`pr-validate.yml` 冒頭にコメントで両方温存）:
  - **モードB（現在有効）**: DE へ `sf project deploy validate`（check-only）。無料 DE は **scratch 作成が「1 日 6 個」上限**で、LWC 開発中は PR を多く回すため scratch を消費しないこの方式にしている。
  - **モードA（scratch・温存）**: 使い捨て scratch org を作って隔離検証 → 破棄。`pr-validate.yml` の手順で各行頭の `# ` を外せば復活する。scratch 作成だけ **SFDX Auth URL 認証**（JWT は新規 scratch にログインできないため）。
- **なぜ案B が既定か**: 標準オブジェクト（Account）のレイアウト/ページは **org 固有メタ（カスタム項目・リンク）に密結合**で、まっさらな scratch に丸ごとは乗りにくい。DE への check-only validate なら実 org 構成のまま検証でき、scratch 上限も消費しない。LWC が一段落したらモードA（scratch 隔離検証）に戻す想定。

ワークフロー: `.github/workflows/pr-validate.yml` / `.github/workflows/quality.yml` / `.github/workflows/deploy-prod.yml`

---

## 手順1: DE org で Dev Hub を有効化（モードA = scratch 用）

設定 → クイック検索「Dev Hub」→ **Dev Hub** → 「有効化」。
（DE は同時に最大 3 つ・1 日 6 つまで scratch org を作成可。一度有効化すると無効化不可。）

> 現在の既定はモードB（scratch を作らない）なので Dev Hub は必須ではないが、モードA に戻す時に必要。**本リポジトリでは有効化済み**。

## 手順2: 証明書と秘密鍵を生成（ローカル）

```bash
# 秘密鍵
openssl genrsa -out server.key 2048
# 自己署名証明書（接続アプリにアップロードする公開鍵側）
openssl req -new -x509 -nodes -sha256 -days 365 -key server.key -out server.crt \
  -subj "/CN=sf-vf-lwc-learning-ci"
```

> `server.key` / `server.crt` は **絶対にコミットしない**（`.gitignore` で除外済み）。

> **証明書ローテーション**: 上記は有効期限 365 日（**2027-06-18 失効**）。失効すると JWT 認証が止まる。
> 失効前に、同じ秘密鍵のまま証明書だけ作り直して ECA に再アップロードする:
> `openssl req -new -x509 -nodes -sha256 -days 365 -key server.key -out server.crt -subj "/CN=sf-vf-lwc-learning-ci"`
> （秘密鍵は不変なので `SF_JWT_KEY_B64` の更新は不要。`server.crt` の差し替えのみ。）
> なお JWT は refresh token を使わないため、ECA の「更新トークンの有効期間」設定は CI に無関係。

## 手順3: 外部クライアントアプリ(ECA)を作成して JWT を有効化

> 注: **Spring '26 で新規 Connected App の作成は無効化**された。現行は **External Client App (ECA)** を使う。
> ECA は JWT Bearer Flow に対応しており、`sf org login jwt --client-id` には **ECA の Consumer Key** を渡せる（CLI 側の手順は Connected App と同じ）。

設定 → **アプリケーションマネージャ** → 「**新規外部クライアントアプリケーション**」:

1. **基本情報**: 名前 / API 参照名 / 連絡先メール、Distribution State = **Local**。
2. **API (OAuth 設定)** を有効化:
   - **コールバック URL**: `http://localhost:1717/OauthRedirect`（**この値にする**。`sf org create scratch` が scratch org 認可にこの CLI 既定リダイレクトを使うため、別 URL だと `指定されたコールバック URL は無効です` で scratch 作成が失敗する。JWT ログイン自体は callback を使わないので、JWT 検証が通っていても scratch 作成だけ落ちる罠）
   - **OAuth スコープ**: `api`（Manage user data via APIs）, `refresh_token, offline_access`（Perform requests at any time）
3. **JWT を有効化**: OAuth 設定内の **Enable JWT Bearer Flow** を ON → 手順2の `server.crt` をアップロード。
4. **連携ユーザを事前承認（ECA は App Policies に権限セットを追加する点が Connected App と違う）**:
   - 先に **権限セット**を 1 つ作成（例 `CI JWT Deploy`。中身の権限は空でも可、アプリ紐付け用）。
   - ECA の **ポリシー(Policies)** を編集 → **OAuth ポリシー**：許可されるユーザー = **「管理者が承認したユーザーは事前承認済み」** → **アプリケーションポリシー(App Policies)** の **選択された権限セット(Selected Permission Sets)** に上記権限セットを追加。
   - その権限セットを連携ユーザーに割り当て（設定 → 権限セット → 割り当ての管理）。
   - 未実施だと JWT が `user is not admin approved to access this app` / `External client app is not installed in this org` で失敗する（管理者は "Approve Uninstalled Connected Apps" 権限を既定保有）。
   - 参考: [Preauthorize User App Access Through External Client App Policies](https://help.salesforce.com/s/articleView?id=xcloud.preauth_user_app_access_through_eca.htm&type=5)
5. **Consumer Key** を取得: ECA の **Settings → OAuth Settings → Consumer Key and Secret** から控える（反映に数分かかることあり）。

> ECA は UI の項目配置が Connected App と異なるため、正確なラベル/配置は公式ページに従う:
>
> - [Configure an External Client App to Issue JWT-Based Access Tokens](https://help.salesforce.com/s/articleView?id=sf.jwt_eca_configuration.htm&type=5)
> - [Configure OAuth 2.0 JWT Bearer Flow for External Client Apps](https://help.salesforce.com/s/articleView?id=sf.meta_configure_oauth_jwt_flow_external_client_apps.htm&type=5)

## 手順4: ローカルで JWT ログインを検証（任意だが推奨）

```bash
sf org login jwt \
  --username <あなたのDEユーザ名> \
  --jwt-key-file server.key \
  --client-id <Consumer Key> \
  --instance-url https://login.salesforce.com \
  --alias de-prod
```

成功すれば CI でも通る。失敗時の典型: ユーザ未承認 / スコープ不足 / 反映待ち。

## 手順5: GitHub Secrets を登録

リポジトリ → Settings → Secrets and variables → Actions → **New repository secret**:

| Secret 名         | 値                                               | 用途                                     |
| ----------------- | ------------------------------------------------ | ---------------------------------------- |
| `SF_JWT_KEY_B64`  | `server.key` を base64 1 行化した文字列（下記）  | deploy-prod.yml ＋ 現行 pr-validate（B） |
| `SF_CONSUMER_KEY` | ECA の Consumer Key                              | 同上                                     |
| `SF_USERNAME`     | DE org のログインユーザ名（連携ユーザ）          | 同上                                     |
| `DEVHUB_SFDX_URL` | web 認証済み org の SFDX Auth URL（`force://…`） | **モードA（scratch）専用・現在は未使用** |

base64 1 行化（macOS）:

```bash
cat server.key | base64 | tr -d '\n' | pbcopy   # クリップボードへ
```

> instance URL は DE/本番ともに `https://login.salesforce.com` 固定なのでワークフローに直書き（Secret 不要）。

### `DEVHUB_SFDX_URL` について（モードA 復活時のみ）

**JWT は scratch org のログインに使えない**（新規 scratch に証明書が無く `invalid assertion`）。そのため scratch を作るモードA だけ **SFDX Auth URL 認証**を使う（deploy / 現行 pr-validate は JWT のまま）。値は web 認証済み org から取得:

```bash
sf org display --target-org de-web --verbose --json | python3 -c "import sys,json;print(json.load(sys.stdin)['result']['sfdxAuthUrl'])" | pbcopy
```

→ GitHub の `DEVHUB_SFDX_URL` シークレットに貼り付け（**リフレッシュトークンを含むので扱い注意**）。**現在はモードB のため未使用**だが、登録しておけばモードA 復活時にそのまま効く。

## 手順6: ブランチ（develop / main）

ブランチ戦略は **feature → PR → `develop` →（リリース）→ `main`**。`develop` / `main` は**作成済み**。
GitHub のブランチ保護で「develop/main への直 push を禁止し PR 必須」にすると CI がゲートとして効く（任意・推奨）。

> エージェントは push 不可（SSH 鍵なし）・トークン書込権限なし。**push / PR / merge / Secret 登録はユーザー操作**で行う（[CLAUDE.md](../CLAUDE.md) のガードレール参照）。

---

## 運用フロー

1. 機能ブランチを切る → `develop` へ PR → **pr-validate.yml**（現在＝DE へ check-only validate）＋ **quality.yml** が走る。
2. PR をマージ（develop）。リリース時に `develop` → `main` へ PR/マージ。
3. `main` にマージされると **deploy-prod.yml** が DE 本番へデプロイ（Apex/LWC に加え **FlexiPage・アプリ割り当ても反映**）。

## CI のワークフロー構成（.github/workflows/）

| ファイル          | トリガー          | 内容                                                                                                      | org / 認証                      |
| ----------------- | ----------------- | --------------------------------------------------------------------------------------------------------- | ------------------------------- |
| `pr-validate.yml` | PR → develop      | 【B=現在】DE へ `deploy validate`（check-only＋RunLocalTests、DE 不変）／【A=温存】scratch 作成→検証→破棄 | DE/JWT（A は scratch/Auth URL） |
| `quality.yml`     | PR → develop/main | TruffleHog(秘密検出) / Prettier(`prettier:verify`) / ESLint / Jest(`sfdx-lwc-jest`) / Code Analyzer       | 不要(static)                    |
| `deploy-prod.yml` | push → main       | DE 本番へ `deploy start --source-dir force-app`（RunLocalTests）                                          | DE 本番/JWT                     |

### quality.yml の前提・運用

- **LWC 追加で ESLint・Jest が本領発揮**: 以前は LWC が無く空回りだったが、`opportunityKanban` 追加で実際に検証が効く（LWC Jest 5 ケース）。**husky の pre-commit** でもローカルで Prettier / ESLint / Jest を実行（コミット前の二重チェック）。
- **一度だけ整形**: 既存コードを Prettier 整形してからでないと `prettier:verify` が落ちる。初回に `npm install && npm run prettier` を実行 → 整形差分をコミット。
- **Code Analyzer（v5）はまずレポートのみ**（`sf plugins install code-analyzer` → `sf code-analyzer run`）。ゲート化するなら `--severity-threshold` を付ける。PMD の CRUD/FLS 系ルールは `WITH USER_MODE` を解さず誤検知し得るので、必要なら設定で調整（CRUD/FLS の厳密検査は Graph Engine が担当）。
- **TruffleHog** は PR 差分をスキャン（組織 repo でもライセンス不要）。
- **供給網対策（任意）**: GitHub Actions をコミット SHA で固定 + Dependabot。private repo の Secret Scanning / CodeQL は GitHub Advanced Security（有償）が要るため、無料なら本構成（TruffleHog + Code Analyzer）が現実的。

## 既知の注意点

- **Apex カバレッジ**: 本番(main)デプロイは `RunLocalTests`。`OpportunityMonthlyReportControllerTest`（VF・カバレッジ 100%）と `OpportunityKanbanControllerTest`（LWC バックエンド・98%）が担保（本番デプロイの 75% 要件を満たす）。
- **配置（宣言的設定）もコード管理**:
  - VF: 取引先カスタムボタン（WebLink）＋ページレイアウト（`Account-Account Layout.layout-meta.xml`）。
  - LWC: 取引先レコードページ（`Account_Opportunity_Kanban.flexipage`）＋ **Sales アプリのページ割り当て**（`standard__LightningSales.app` の `actionOverrides`）。
  - App Builder（GUI）で行った有効化も `sf project retrieve` で `CustomApplication` として取り込み、**手動 UI 設定をなくして再現性を確保**（repo = source of truth。[CLAUDE.md](../CLAUDE.md) のガードレール）。
- **⚠️ 標準アプリの上書き**: repo に `applications/standard__LightningSales.app-meta.xml` を含むため、main デプロイ時に **標準セールスアプリのページ割り当て・ナビ構成をこのファイル内容で上書き**する。意図しない上書きを避けたい場合は、このファイルを repo から外す。
- **標準オブジェクトのメタ密結合**: 標準オブジェクトのレイアウト/ページは org 固有メタ（カスタム項目・リンク）に依存しがちで、空 scratch に乗らないことがある（モードB を既定にする理由）。DE テンプレート由来の不要な Account カスタム項目は除去済（一部は参照により削除できず残置、管理パッケージ名前空間の項目は不可侵）。
- **デプロイ単位**: `--metadata "A,B"` のカンマ指定は失敗することがある → `--source-dir`（`force-app` 一括やディレクトリ指定）が安定。ワークフローも `--source-dir force-app`。
- **ステージ値（フェーズ）**: scratch/DE とも `OpportunityStage` は既定 en_US の英語 API 値（`Closed Won` 等）。LWC カンバンは表示だけ日本語化し、`StageName` の API 値は英語のまま更新に使う（テストも英語 API 値準拠）。
- **検証 = （モードA時）scratch / 本番 = 同一 DE**: 本構成は本番と Dev Hub が同一 org。完全分離したい場合は将来 EE/Sandbox or 2 つ目の DE に拡張。
- **DE 本番にはテストデータが無い**: 表示確認用のテストデータ（取引先「視覚確認テスト商事」＋商談）は **scratch 専用**。本番 DE で確認するには取引先＋商談を別途用意する。
- **IP 制限と JWT（重要な落とし穴）**: JWT/SAML bearer フローは **ECA(接続アプリ)側の「IP 制限の緩和」設定を無視し、常に IP 制限を強制**する。実際に効くのは**連携ユーザのプロファイルの「ログイン IP 範囲」**。GitHub runner は動的 IP なので、この範囲は**空**にしておく（DE のシステム管理者プロファイルは既定で空）。`restricted IP`/`INVALID_LOGIN` で失敗したらここを疑う。
  - 事前承認: ECA Policies で「管理者が承認したユーザーは事前承認済み」を選び、対象ユーザーの**プロファイル/権限セットを ECA に割り当てる**（割当が無いと事前承認が効かない）。
  - 更新トークンの有効期間設定は JWT には無関係（JWT は refresh token を発行しない）。
  - 出典: [Connected App IP Relaxation and Continuous IP Enforcement](https://help.salesforce.com/s/articleView?id=sf.connected_app_continuous_ip.htm&type=5) / [OAuth 2.0 JWT Bearer Flow](https://help.salesforce.com/s/articleView?id=sf.remoteaccess_oauth_jwt_flow.htm&type=5) / [Restrict Login IP Addresses in Profiles](https://help.salesforce.com/s/articleView?id=platform.login_ip_ranges.htm&type=5)

## 出典

- OAuth 2.0 JWT Bearer Flow: https://help.salesforce.com/s/articleView?id=sf.remoteaccess_oauth_jwt_flow.htm&type=5
- Authorize an Org Using the JWT Flow (SFDX Dev Guide): https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_auth_jwt_flow.htm
- Configure an External Client App to Issue JWT-Based Access Tokens: https://help.salesforce.com/s/articleView?id=sf.jwt_eca_configuration.htm&type=5
- Select and Enable a Dev Hub Org: https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_setup_enable_devhub.htm
- Scratch Orgs: https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_scratch_orgs.htm
- Salesforce CLI README (org login jwt / project deploy start|validate / org create scratch): https://github.com/salesforcecli/cli/blob/main/README.md
