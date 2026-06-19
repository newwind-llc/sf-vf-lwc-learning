/**
 * OpportunityKanbanController のテスト。
 *
 * 検証内容:
 *  - getStages: 有効ステージが SortOrder 順で返り、Closed Won が IsWon=true。
 *  - getOpportunities(accountId): 取引先配下の商談のみ返る。
 *  - getOpportunities(null): 未完了(open)の商談のみ返る。
 *  - updateStage: ステージが実際に更新される。
 *  - updateStage の異常系: 引数不正 / 不正ステージ値で AuraHandledException。
 *
 * 注: OpportunityStage は org 標準の構成（標準値セット）で、テストコンテキストでも参照可能。
 */
@IsTest
private class OpportunityKanbanControllerTest {
  private static Account makeAccount() {
    Account acc = new Account(Name = 'カンバンテスト商事');
    insert acc;
    return acc;
  }

  private static Opportunity makeOpp(
    Account acc,
    String name,
    String stage,
    Decimal amount
  ) {
    Opportunity opp = new Opportunity(
      Name = name,
      StageName = stage,
      CloseDate = Date.today().addDays(30),
      Amount = amount,
      AccountId = acc.Id
    );
    insert opp;
    return opp;
  }

  @IsTest
  static void getStages_returnsActiveStagesInOrder() {
    Test.startTest();
    List<OpportunityKanbanController.StageInfo> stages = OpportunityKanbanController.getStages();
    Test.stopTest();

    System.assert(!stages.isEmpty(), 'ステージが1件以上返るはず');

    // org 標準では最初の有効ステージは Prospecting（SortOrder=1）
    System.assertEquals(
      'Prospecting',
      stages[0].apiName,
      '先頭の apiName は SortOrder 最小の Prospecting のはず'
    );
    System.assertEquals(
      '見込み',
      stages[0].label,
      '表示ラベルは日本語化されるはず（Prospecting→見込み）'
    );

    // 成立ステージ（IsWon=true）が少なくとも1つ含まれる
    Boolean hasWon = false;
    for (OpportunityKanbanController.StageInfo s : stages) {
      if (s.isWon == true) {
        hasWon = true;
        System.assertEquals(
          true,
          s.isClosed,
          'IsWon の列は IsClosed でもあるはず'
        );
      }
    }
    System.assert(hasWon, 'IsWon=true のステージが含まれるはず');
  }

  @IsTest
  static void getOpportunities_byAccount_returnsOnlyThatAccount() {
    Account acc = makeAccount();
    makeOpp(acc, '案件A', 'Prospecting', 100000);
    makeOpp(acc, '案件B', 'Qualification', 200000);

    Account other = new Account(Name = '別商事');
    insert other;
    makeOpp(other, '別案件', 'Prospecting', 999999);

    Test.startTest();
    List<Opportunity> opps = OpportunityKanbanController.getOpportunities(
      acc.Id
    );
    Test.stopTest();

    System.assertEquals(2, opps.size(), '対象取引先の商談2件のみ返るはず');
    for (Opportunity o : opps) {
      System.assertEquals(acc.Id, o.AccountId, '別取引先の商談は含まれない');
    }
  }

  @IsTest
  static void getOpportunities_null_returnsOnlyOpen() {
    Account acc = makeAccount();
    makeOpp(acc, 'オープン案件', 'Prospecting', 100000);
    makeOpp(acc, '成立案件', 'Closed Won', 300000);

    Test.startTest();
    List<Opportunity> opps = OpportunityKanbanController.getOpportunities(null);
    Test.stopTest();

    System.assertEquals(1, opps.size(), '未完了(open)の商談のみ返るはず');
    System.assertEquals('オープン案件', opps[0].Name);
  }

  @IsTest
  static void updateStage_movesOpportunity() {
    Account acc = makeAccount();
    Opportunity opp = makeOpp(acc, '移動案件', 'Prospecting', 100000);

    Test.startTest();
    Opportunity returned = OpportunityKanbanController.updateStage(
      opp.Id,
      'Qualification'
    );
    Test.stopTest();

    System.assertEquals(
      'Qualification',
      returned.StageName,
      '戻り値のステージが更新後の値のはず'
    );
    Opportunity reloaded = [
      SELECT StageName
      FROM Opportunity
      WHERE Id = :opp.Id
    ];
    System.assertEquals(
      'Qualification',
      reloaded.StageName,
      'DB 上もステージが更新されているはず'
    );
  }

  @IsTest
  static void updateStage_invalidArgs_throws() {
    Boolean threw = false;
    Test.startTest();
    try {
      OpportunityKanbanController.updateStage(null, 'Qualification');
    } catch (AuraHandledException e) {
      threw = true;
    }
    Test.stopTest();
    System.assert(
      threw,
      '商談Id が null なら AuraHandledException が発生するはず'
    );
  }

  @IsTest
  static void updateStage_blankStage_throws() {
    Account acc = makeAccount();
    Opportunity opp = makeOpp(acc, '空ステージ案件', 'Prospecting', 100000);

    Boolean threw = false;
    Test.startTest();
    try {
      OpportunityKanbanController.updateStage(opp.Id, '');
    } catch (AuraHandledException e) {
      threw = true;
    }
    Test.stopTest();
    System.assert(
      threw,
      'ステージ名が空なら AuraHandledException が発生するはず'
    );
  }

  @IsTest
  static void updateStage_deletedRecord_throws() {
    // 削除済みレコードの更新で DmlException を確実に発生させ、catch 経路を検証する。
    // （不正なステージ値が弾かれるかは org の picklist 設定に依存するため、ここでは使わない）
    Account acc = makeAccount();
    Opportunity opp = makeOpp(acc, '削除済み案件', 'Prospecting', 100000);
    Id deletedId = opp.Id;
    delete opp;

    Boolean threw = false;
    Test.startTest();
    try {
      OpportunityKanbanController.updateStage(deletedId, 'Qualification');
    } catch (AuraHandledException e) {
      threw = true;
    }
    Test.stopTest();
    System.assert(
      threw,
      '存在しない（削除済み）商談の更新は DmlException 経由で AuraHandledException になるはず'
    );
  }
}
