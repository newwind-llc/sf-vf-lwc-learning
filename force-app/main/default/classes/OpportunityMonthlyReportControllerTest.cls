/**
 * OpportunityMonthlyReportController のテスト。
 *
 * 目的:
 *  - 当月かつ成立(IsWon=true)の商談「だけ」が集計されることを検証する。
 *  - 合計金額(totalAmount)が成立分のみで計算されることを検証する。
 *  - CI（scratch org への deploy + RunLocalTests）で自動実行され、
 *    本番(DE)デプロイ時のカバレッジ要件(75%)も満たす土台になる。
 *
 * 注意: フェーズ API 値 'Closed Won' / 'Prospecting' は en_US 既定の OpportunityStage 値。
 *       本 scratch 定義は edition=Developer / 既定言語 en_US のため、これらの値が存在する。
 *       コントローラ側は文字列ではなく IsWon で判定しているため、'Closed Won'(=IsWon true)が拾われる。
 */
@isTest
private class OpportunityMonthlyReportControllerTest {
  private static final String ACCOUNT_NAME = 'CI Test 取引先';

  @TestSetup
  static void makeData() {
    Account acc = new Account(Name = ACCOUNT_NAME);
    insert acc;

    List<Opportunity> opps = new List<Opportunity>{
      // 当月・成立 → 集計対象
      new Opportunity(
        Name = '当月成立商談',
        AccountId = acc.Id,
        StageName = 'Closed Won',
        CloseDate = Date.today(),
        Amount = 100000
      ),
      // 当月だが未成立(オープン) → 除外されるべき
      new Opportunity(
        Name = '当月オープン商談',
        AccountId = acc.Id,
        StageName = 'Prospecting',
        CloseDate = Date.today(),
        Amount = 50000
      ),
      // 成立だが先月クローズ → THIS_MONTH 条件で除外されるべき
      new Opportunity(
        Name = '先月成立商談',
        AccountId = acc.Id,
        StageName = 'Closed Won',
        CloseDate = Date.today().addMonths(-1),
        Amount = 999999
      )
    };
    insert opps;
  }

  @isTest
  static void onlyThisMonthWonOpportunitiesAreCounted() {
    Account acc = [
      SELECT Id, Name
      FROM Account
      WHERE Name = :ACCOUNT_NAME
      LIMIT 1
    ];

    Test.startTest();
    ApexPages.StandardController std = new ApexPages.StandardController(acc);
    OpportunityMonthlyReportController ctrl = new OpportunityMonthlyReportController(
      std
    );
    Test.stopTest();

    System.assertEquals(
      1,
      ctrl.getRecordCount(),
      '当月成立商談のみ1件が対象になるはず（オープン・先月分は除外）'
    );
    System.assert(
      ctrl.totalAmount == 100000,
      '合計は当月成立分(100000)のみであるべき。実際: ' + ctrl.totalAmount
    );
    System.assertEquals(
      '当月成立商談',
      ctrl.opportunities[0].Name,
      '対象商談は当月成立商談であるべき'
    );
    System.assertNotEquals(
      null,
      ctrl.getTargetYearMonth(),
      '対象年月が生成されること'
    );

    // 請求書金額（Amount=税抜想定, 消費税10%・切り捨て）
    System.assert(ctrl.getSubtotal() == 100000, '小計(税抜)は100000');
    System.assert(ctrl.getTaxAmount() == 10000, '消費税(10%)は10000');
    System.assert(ctrl.getGrandTotal() == 110000, '合計(税込)は110000');
  }

  @isTest
  static void noWonOpportunitiesGivesEmptyAndZeroTotal() {
    // 成立商談を持たない取引先
    Account empty = new Account(Name = '成立なし取引先');
    insert empty;

    Test.startTest();
    ApexPages.StandardController std = new ApexPages.StandardController(empty);
    OpportunityMonthlyReportController ctrl = new OpportunityMonthlyReportController(
      std
    );
    Test.stopTest();

    System.assertEquals(0, ctrl.getRecordCount(), '対象0件のはず');
    System.assert(
      ctrl.totalAmount == 0,
      '合計は0であるべき。実際: ' + ctrl.totalAmount
    );
    System.assert(ctrl.getTaxAmount() == 0, '0件なら消費税0');
    System.assert(ctrl.getGrandTotal() == 0, '0件なら合計0');
  }

  @isTest
  static void invoiceFieldsArePopulated() {
    Account acc = [SELECT Id FROM Account WHERE Name = :ACCOUNT_NAME LIMIT 1];

    Test.startTest();
    OpportunityMonthlyReportController ctrl = new OpportunityMonthlyReportController(
      new ApexPages.StandardController(acc)
    );
    Test.stopTest();

    System.assertNotEquals(
      null,
      ctrl.getInvoiceNumber(),
      '請求書番号が生成される'
    );
    System.assertEquals(10, ctrl.getTaxRatePercent(), '適用税率は10%');
    System.assert(ctrl.getPaymentDueDate() > Date.today(), '支払期限は未来日');
    System.assertNotEquals(null, ctrl.getReportDate(), '発行日');
    System.assertNotEquals(null, ctrl.getIssuerName(), '発行元名');
    System.assertNotEquals(null, ctrl.getIssuerAddress(), '発行元住所');
    System.assertNotEquals(null, ctrl.getIssuerTel(), '発行元TEL');
    System.assertNotEquals(
      null,
      ctrl.getIssuerRegistrationNumber(),
      '登録番号'
    );
    System.assertNotEquals(null, ctrl.getBankInfo(), '振込先');
    System.assertEquals(
      25,
      ctrl.getRecordCount() + ctrl.getFillerRows().size(),
      '明細は実件数＋空行で固定25行になる'
    );
  }
}
