/**
 * 取引先の「月次締め帳票」用 拡張コントローラ。
 *
 * 取引先詳細画面のカスタムボタンから起動され、当月に成立(Closed Won)した
 * 関連商談を取得して、プレビュー画面 / PDF 帳票（同じデータ）に渡す。
 *
 * 設計メモ:
 *  - standardController="Account" の「拡張(extension)」として動作する。
 *    そのためコンストラクタ引数は ApexPages.StandardController で、
 *    そこから対象 Account の Id を受け取る。
 *  - SOQL は WITH USER_MODE で実行し、実行ユーザの CRUD/FLS・項目アクセスを尊重する
 *    （WITH USER_MODE は API 59.0 以上が必要。本プロジェクトは 66.0）。
 *  - 「完了」の定義 = 成立(Closed Won)。フェーズ名(StageName)は組織でラベルを
 *    カスタムされうるため、文字列直書きではなく標準ブール項目 IsWon = true で判定する。
 *  - 「当月」 = SOQL 日付リテラル THIS_MONTH（実行時点の暦上の当月）。
 */
public with sharing class OpportunityMonthlyReportController {
  /** 帳票に表示する当月成立商談（コンストラクタで必ず初期化されるため null にならない） */
  public List<Opportunity> opportunities { get; private set; }

  /** 金額(Amount)の合計。null の Amount は 0 として扱う。 */
  public Decimal totalAmount { get; private set; }

  public OpportunityMonthlyReportController(
    ApexPages.StandardController stdController
  ) {
    Id accountId = stdController.getId();
    loadOpportunities(accountId);
  }

  private void loadOpportunities(Id accountId) {
    opportunities = [
      SELECT Id, Name, StageName, CloseDate, Amount, Owner.Name
      FROM Opportunity
      WHERE AccountId = :accountId AND IsWon = TRUE AND CloseDate = THIS_MONTH
      WITH USER_MODE
      ORDER BY CloseDate ASC, Amount DESC NULLS LAST
    ];

    Decimal sum = 0;
    for (Opportunity opp : opportunities) {
      if (opp.Amount != null) {
        sum += opp.Amount;
      }
    }
    totalAmount = sum;
  }

  /** 帳票見出し用の対象年月（例: 2026年6月） */
  public String getTargetYearMonth() {
    Date today = Date.today();
    return today.year() + '年' + today.month() + '月';
  }

  /** 出力日（例: 2026/06/18） */
  public Date getReportDate() {
    return Date.today();
  }

  /** 表示件数 */
  public Integer getRecordCount() {
    return opportunities.size();
  }
}
