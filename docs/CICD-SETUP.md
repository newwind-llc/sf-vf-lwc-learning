# CI/CD セットアップ手順（GitHub Actions → Salesforce / JWT 認証）

このリポジトリの CI/CD 構成（**案A**）と、動かすための一回限りのセットアップ手順。

## 全体像

```
PR → develop : 使い捨て scratch org を作成 → force-app を deploy → Apex テスト → scratch 破棄
push → main  : 本番扱いの DE org へ deploy（RunLocalTests）
```

- 1つの **Developer Edition(DE) org** を「**Dev Hub 兼 本番**」として使う。
- scratch org は Dev Hub 経由で自動認可されるため、**接続アプリ(JWT)は DE org に1つだけ**でよい。
- CI の無人ログインは **OAuth 2.0 JWT Bearer Flow**（ブラウザ不要）。

ワークフロー: `.github/workflows/pr-validate.yml` / `.github/workflows/deploy-prod.yml`

---

## 手順1: DE org で Dev Hub を有効化

設定 → クイック検索「Dev Hub」→ **Dev Hub** → 「有効化」。
（DE は同時に最大3つの scratch org を作成可。一度有効化すると無効化不可。）

## 手順2: 証明書と秘密鍵を生成（ローカル）

```bash
# 秘密鍵
openssl genrsa -out server.key 2048
# 自己署名証明書（接続アプリにアップロードする公開鍵側）
openssl req -new -x509 -nodes -sha256 -days 365 -key server.key -out server.crt \
  -subj "/CN=sf-vf-lwc-learning-ci"
```

> `server.key` / `server.crt` は **絶対にコミットしない**（`.gitignore` で除外済み）。

> **証明書ローテーション**: 上記は有効期限 365日（**2027-06-18 失効**）。失効すると JWT 認証が止まる。
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
   - 先に **権限セット**を1つ作成（例 `CI JWT Deploy`。中身の権限は空でも可、アプリ紐付け用）。
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

| Secret 名         | 値                                             |
| ----------------- | ---------------------------------------------- |
| `SF_JWT_KEY_B64`  | `server.key` を base64 1行化した文字列（下記） |
| `SF_CONSUMER_KEY` | 接続アプリの Consumer Key                      |
| `SF_USERNAME`     | DE org のログインユーザ名（連携ユーザ）        |

base64 1行化（macOS）:

```bash
cat server.key | base64 | tr -d '\n' | pbcopy   # クリップボードへ
```

> instance URL は DE/本番ともに `https://login.salesforce.com` 固定なのでワークフローに直書き（Secret 不要）。

### 追加シークレット: `DEVHUB_SFDX_URL`（pr-validate.yml の scratch 用）

**JWT は scratch org のログインに使えない**（新規 scratch に証明書が無く `invalid assertion`）。そのため **scratch を作る `pr-validate.yml` だけ SFDX Auth URL 認証**を使う（`deploy-prod.yml` は JWT のまま）。これは公式 lwc-recipes と同じ方式。値は web 認証済み org から取得してクリップボードへ:

```bash
sf org display --target-org de-web --verbose --json | python3 -c "import sys,json;print(json.load(sys.stdin)['result']['sfdxAuthUrl'])" | pbcopy
```

→ GitHub の `DEVHUB_SFDX_URL` シークレットに貼り付け（`force://...` で始まる文字列。**リフレッシュトークンを含むので扱い注意**）。

**シークレット用途の整理**:

- `SF_JWT_KEY_B64` / `SF_CONSUMER_KEY` / `SF_USERNAME` … **deploy-prod.yml（本番 deploy・JWT）用**
- `DEVHUB_SFDX_URL` … **pr-validate.yml（scratch 検証）用**

## 手順6: develop ブランチを作成して push

現在 `main` のみ。develop を作る（push はローカルマシンから）:

```bash
git switch -c develop
git push -u origin develop
```

GitHub のブランチ保護で「develop/main への直 push を禁止し PR 必須」にすると CI が効きやすい（任意）。

---

## 運用フロー

1. 機能ブランチを切る → develop へ PR → **pr-validate.yml** が scratch org で検証。
2. PR をマージ（develop）。リリース時に develop → main へ PR/マージ。
3. main にマージされると **deploy-prod.yml** が DE 本番へデプロイ。

## CI のワークフロー構成（.github/workflows/）

| ファイル          | トリガー          | 内容                                                                             | org          |
| ----------------- | ----------------- | -------------------------------------------------------------------------------- | ------------ |
| `pr-validate.yml` | PR → develop      | scratch org 作成 → deploy → Apex テスト → 破棄                                   | 要(scratch)  |
| `quality.yml`     | PR → develop/main | ①Secret 検出(TruffleHog) ②Prettier 整形 + ESLint ③Code Analyzer(PMD/JS/RetireJS) | 不要(static) |
| `deploy-prod.yml` | push → main       | DE 本番へ deploy（RunLocalTests）                                                | 要(本番)     |

### quality.yml の前提・運用

- **一度だけ整形**: 既存コードを Prettier 整形してからでないと `prettier:verify` が落ちる。初回に `npm install && npm run prettier` を実行 → 整形差分をコミット。
- **Code Analyzer はまずレポートのみ**（成果物 `code-analyzer-results.html` を artifact 出力）。ゲート化するなら `sf code-analyzer run ... --severity-threshold 3`（Moderate 以上で失敗）。PMD の CRUD/FLS 系ルールは `WITH USER_MODE` を解さず誤検知し得るので、必要なら `code-analyzer.yml` で調整（CRUD/FLS の厳密検査は Graph Engine が担当）。
- **TruffleHog** は PR 差分をスキャン（組織 repo でもライセンス不要）。代わりに `gitleaks` を使うなら、組織 repo では無料ライセンス（`GITLEAKS_LICENSE` secret）取得が必要。
- **供給網対策（任意）**: GitHub Actions をコミット SHA で固定 + Dependabot を有効化。private repo は GitHub ネイティブの Secret Scanning / CodeQL に GitHub Advanced Security（有償）が要るため、無料で賄うなら本構成（TruffleHog + Code Analyzer）が現実的。

## 既知の注意点

- **Apex カバレッジ**: 本番(main)デプロイは `RunLocalTests`。`OpportunityMonthlyReportControllerTest` がカバレッジを担保する。
- **レイアウトへのボタン配置**: WebLink(ボタン定義)はデプロイされるが、取引先ページレイアウトへの**配置**は org 側設定。必要なら Layout メタデータを別途管理する（現状は手動配置）。
- **scratch org のフェーズ値**: 既定 en_US のため `Closed Won` 等の英語 API 値が存在する前提（テストもこれに準拠）。DE 本番が日本語ロケールでも、コントローラは `IsWon` 判定なので動作は不変。
- **検証 = scratch / 本番 = 同一 DE**: 案A は本番と Dev Hub が同一 org。完全に分離したい場合は将来 EE/Sandbox or 2つ目の DE に拡張。
- **IP 制限と JWT（重要な落とし穴）**: JWT/SAML bearer フローは **ECA(接続アプリ)側の「IP 制限の緩和」設定を無視し、常に IP 制限を強制**する。実際に効くのは**連携ユーザのプロファイルの「ログイン IP 範囲」**。GitHub runner は動的 IP なので、この範囲は**空**にしておく（DE のシステム管理者プロファイルは既定で空）。`restricted IP`/`INVALID_LOGIN` で失敗したらここを疑う。
  - 事前承認: ECA Policies で「管理者が承認したユーザーは事前承認済み」を選び、対象ユーザーの**プロファイル/権限セットを ECA に割り当てる**（割当が無いと事前承認が効かない）。
  - 更新トークンの有効期間設定は JWT には無関係（JWT は refresh token を発行しない）。
  - 出典: [Connected App IP Relaxation and Continuous IP Enforcement](https://help.salesforce.com/s/articleView?id=sf.connected_app_continuous_ip.htm&type=5) / [OAuth 2.0 JWT Bearer Flow](https://help.salesforce.com/s/articleView?id=sf.remoteaccess_oauth_jwt_flow.htm&type=5) / [Restrict Login IP Addresses in Profiles](https://help.salesforce.com/s/articleView?id=platform.login_ip_ranges.htm&type=5)

## 出典

- OAuth 2.0 JWT Bearer Flow: https://help.salesforce.com/s/articleView?id=sf.remoteaccess_oauth_jwt_flow.htm&type=5
- Authorize an Org Using the JWT Flow (SFDX Dev Guide): https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_auth_jwt_flow.htm
- Configure a Connected App to Issue JWT-Based Access Tokens: https://help.salesforce.com/s/articleView?id=sf.jwt_connectedapp_enable.htm&type=5
- Select and Enable a Dev Hub Org: https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_setup_enable_devhub.htm
- Scratch Orgs: https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_scratch_orgs.htm
- Salesforce CLI README (org login jwt / project deploy start / org create scratch): https://github.com/salesforcecli/cli/blob/main/README.md
