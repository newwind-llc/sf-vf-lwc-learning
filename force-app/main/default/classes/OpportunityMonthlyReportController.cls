/**
 * 取引先の「月次締め帳票（請求書スタイル）」用 拡張コントローラ。
 *
 * 取引先詳細画面のカスタムボタンから起動され、当月に成立(Closed Won)した
 * 関連商談を取得し、日本の請求書レイアウト（プレビュー / PDF）に渡す。
 *
 * 設計メモ:
 *  - standardController="Account" の拡張。コンストラクタで Account の Id を受け取る。
 *  - SOQL は WITH USER_MODE（CRUD/FLS を尊重。API 59.0 以上が必要。本プロジェクトは 66.0）。
 *  - 「完了」= 成立(IsWon=true)。「当月」= SOQL 日付リテラル THIS_MONTH。
 *  - 金額(Amount)は「税抜」とみなし、消費税は標準税率10%で算出（軽減税率8%は非対応）。
 *  - 発行元情報・振込先・登録番号・請求書番号は仮置き（本番は Custom Metadata / Custom Label 等へ）。
 */
public with sharing class OpportunityMonthlyReportController {
  /** 消費税率（標準税率10%想定。軽減税率は非対応） */
  private static final Decimal TAX_RATE = 0.1;

  /** 明細表の固定行数（実データ＋空行でこの行数に揃え、A4で体裁を一定にする） */
  private static final Integer FIXED_DETAIL_ROWS = 25;

  /** 帳票に表示する当月成立商談（コンストラクタで必ず初期化されるため null にならない） */
  public List<Opportunity> opportunities { get; private set; }

  /** 金額(Amount)の合計。税抜の小計とみなす。null の Amount は 0 として扱う。 */
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

  /** 件名等に使う対象年月（例: 2026年6月） */
  public String getTargetYearMonth() {
    Date today = Date.today();
    return today.year() + '年' + today.month() + '月';
  }

  /** 発行日（今日） */
  public Date getReportDate() {
    return Date.today();
  }

  /** 明細件数 */
  public Integer getRecordCount() {
    return opportunities.size();
  }

  /** 明細を固定行数に揃えるための空行リスト（FIXED_DETAIL_ROWS − 実件数, 最小0） */
  public List<Integer> getFillerRows() {
    List<Integer> rows = new List<Integer>();
    Integer n = FIXED_DETAIL_ROWS - opportunities.size();
    for (Integer i = 0; i < n; i++) {
      rows.add(i);
    }
    return rows;
  }

  // ───────── 請求書用の値 ─────────

  /** 請求書番号（仮置き。例 2026-0601）。本番は採番ルールに置き換える。 */
  public String getInvoiceNumber() {
    Date d = Date.today();
    String mm = (d.month() < 10 ? '0' : '') + String.valueOf(d.month());
    return d.year() + '-' + mm + '01';
  }

  /** 小計（税抜）＝Amount 合計を税抜とみなす */
  public Decimal getSubtotal() {
    return totalAmount;
  }

  /** 消費税額（税率ごとに1回端数処理。今回は10%・切り捨て） */
  public Decimal getTaxAmount() {
    return (totalAmount * TAX_RATE).setScale(0, System.RoundingMode.DOWN);
  }

  /** 合計（税込） */
  public Decimal getGrandTotal() {
    return getSubtotal() + getTaxAmount();
  }

  /** 適用税率(%)の表示用（例: 10） */
  public Integer getTaxRatePercent() {
    return (TAX_RATE * 100).intValue();
  }

  /** 支払期限（仮置き：翌月末日） */
  public Date getPaymentDueDate() {
    Date n = Date.today().addMonths(1);
    return Date.newInstance(
      n.year(),
      n.month(),
      Date.daysInMonth(n.year(), n.month())
    );
  }

  // ── 発行元情報（仮置き。本番は Custom Metadata / Custom Label 等へ移す） ──
  public String getIssuerName() {
    return '合同会社NEWWIND';
  }

  public String getIssuerAddress() {
    return '〒000-0000 埼玉県（要設定）';
  }

  public String getIssuerTel() {
    return 'TEL 000-0000-0000（要設定）';
  }

  public String getIssuerRegistrationNumber() {
    return 'T0000000000000（要設定）';
  }

  public String getBankInfo() {
    return '◯◯銀行 ◯◯支店 普通 1234567 ゴウドウガイシャニューウインド（要設定）';
  }
}
