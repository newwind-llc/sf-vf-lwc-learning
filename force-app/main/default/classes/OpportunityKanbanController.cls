/**
 * 商談カンバン（パイプライン）ボード用コントローラ。
 *
 * LWC `opportunityKanban` から呼ばれ、商談をステージ別に並べる「列」と、
 * 各列に並ぶ商談カードのデータを返す。カードをドラッグ&ドロップした際は
 * `updateStage` で StageName を更新する。
 *
 * 設計メモ:
 *  - CRUD/FLS 担保: 読み取りは SOQL `WITH USER_MODE`、書き込みは
 *    `Database.update(rec, AccessLevel.USER_MODE)`（ユーザーモード実行）。
 *    （Apex Security: developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_classes_perms_enforcing.htm）
 *  - 列は OpportunityStage（有効なもの）を SortOrder 順に取得し、org のステージ構成に追従する。
 *  - `@AuraEnabled` はオーバーロード禁止のため、公開メソッドはそれぞれ別名。
 *  - 読み取り専用（@wire 用）は cacheable=true、DML を伴う更新は imperative 用に非 cacheable。
 */
public with sharing class OpportunityKanbanController {
  /** カンバンの1列を表すステージ情報（LWC へ返す DTO） */
  public class StageInfo {
    @AuraEnabled
    public String apiName; // StageName に格納される値（= OpportunityStage.MasterLabel）。照合・更新に使う
    @AuraEnabled
    public String label; // 画面表示用ラベル（日本語）。表示にのみ使う
    @AuraEnabled
    public Boolean isWon;
    @AuraEnabled
    public Boolean isClosed;

    public StageInfo(
      String apiName,
      String label,
      Boolean isWon,
      Boolean isClosed
    ) {
      this.apiName = apiName;
      this.label = label;
      this.isWon = isWon;
      this.isClosed = isClosed;
    }
  }

  /**
   * 標準商談ステージの表示用日本語ラベル（API値 → 表示名）。
   * StageName の API 値（英語）はデータとしてそのまま保持し、画面表示だけ日本語にする。
   * （本格的な多言語化は 翻訳ワークベンチ/Translation Workbench で行うのが定石。
   *   このマップに無いステージは英語のAPI値をそのまま表示する＝フォールバック）
   */
  private static final Map<String, String> STAGE_LABELS_JA = new Map<String, String>{
    'Prospecting' => '見込み',
    'Qualification' => '条件確認',
    'Needs Analysis' => 'ニーズ分析',
    'Value Proposition' => '価値提案',
    'Id. Decision Makers' => '意思決定者の特定',
    'Perception Analysis' => '認識分析',
    'Proposal/Price Quote' => '提案・見積',
    'Negotiation/Review' => '交渉・調整',
    'Closed Won' => '成立（受注）',
    'Closed Lost' => '不成立（失注）'
  };

  /**
   * カンバンの列（ステージ）一覧。
   * 有効な OpportunityStage を SortOrder 順に返すので、org のステージ構成に追従する。
   * apiName は StageName の値（英語）、label は表示用の日本語。
   */
  @AuraEnabled(cacheable=true)
  public static List<StageInfo> getStages() {
    List<StageInfo> stages = new List<StageInfo>();
    for (OpportunityStage s : [
      SELECT MasterLabel, IsWon, IsClosed
      FROM OpportunityStage
      WHERE IsActive = TRUE
      WITH USER_MODE
      ORDER BY SortOrder
    ]) {
      String jaLabel = STAGE_LABELS_JA.containsKey(s.MasterLabel)
        ? STAGE_LABELS_JA.get(s.MasterLabel)
        : s.MasterLabel;
      stages.add(new StageInfo(s.MasterLabel, jaLabel, s.IsWon, s.IsClosed));
    }
    return stages;
  }

  /**
   * カンバンに表示する商談を取得する。
   *  - accountId 指定時: その取引先配下の商談すべて（取引先レコードページ用）。
   *  - null（アプリ/ホームページ用）: 未完了(open)の商談を上限つきで返す。
   */
  @AuraEnabled(cacheable=true)
  public static List<Opportunity> getOpportunities(Id accountId) {
    if (accountId != null) {
      return [
        SELECT
          Id,
          Name,
          StageName,
          Amount,
          CloseDate,
          AccountId,
          Account.Name,
          Owner.Name
        FROM Opportunity
        WHERE AccountId = :accountId
        WITH USER_MODE
        ORDER BY CloseDate ASC, Amount DESC NULLS LAST
      ];
    }
    return [
      SELECT
        Id,
        Name,
        StageName,
        Amount,
        CloseDate,
        AccountId,
        Account.Name,
        Owner.Name
      FROM Opportunity
      WHERE IsClosed = FALSE
      WITH USER_MODE
      ORDER BY CloseDate ASC, Amount DESC NULLS LAST
      LIMIT 200
    ];
  }

  /**
   * 商談のステージを更新する（カードのドラッグ&ドロップで呼ばれる）。
   * 書き込みは AccessLevel.USER_MODE で CRUD/FLS を担保。更新後の商談を返す。
   *
   * @param opportunityId 対象商談の Id
   * @param stageName 新しいステージ（OpportunityStage.MasterLabel と一致する値）
   * @return 更新後の商談（カード再描画用）
   */
  @AuraEnabled
  public static Opportunity updateStage(Id opportunityId, String stageName) {
    if (opportunityId == null || String.isBlank(stageName)) {
      throw makeError('商談IDとステージ名は必須です。');
    }
    Opportunity opp = new Opportunity(
      Id = opportunityId,
      StageName = stageName
    );
    try {
      Database.update(opp, AccessLevel.USER_MODE);
    } catch (DmlException e) {
      // 不正なステージ値・FLS 違反などをユーザー向けメッセージに変換
      throw makeError(
        e.getDmlMessage(0) != null ? e.getDmlMessage(0) : e.getMessage()
      );
    }
    List<Opportunity> updated = [
      SELECT
        Id,
        Name,
        StageName,
        Amount,
        CloseDate,
        AccountId,
        Account.Name,
        Owner.Name
      FROM Opportunity
      WHERE Id = :opportunityId
      WITH USER_MODE
    ];
    return updated.isEmpty() ? null : updated[0];
  }

  /**
   * LWC 側で `error.body.message` として読めるよう、メッセージ付きの
   * AuraHandledException を生成する（setMessage しないと汎用文言になるため）。
   */
  private static AuraHandledException makeError(String message) {
    AuraHandledException e = new AuraHandledException(message);
    e.setMessage(message);
    return e;
  }
}
