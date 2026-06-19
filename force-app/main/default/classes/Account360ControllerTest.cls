/**
 * Account360Controller のテスト。
 *  - getKpis: 今月成立額 / 進行中件数・額 / オープンケース / 連絡先数 の集計。
 *  - get各リスト: 関連レコードを返す（活動は Task+Event 統合）。
 *  - updateOpportunities: ドラフト保存 / 空入力 no-op / 異常系。
 */
@IsTest
private class Account360ControllerTest {
  private static Account makeAccount() {
    Account a = new Account(Name = '360テスト商事');
    insert a;
    return a;
  }

  @IsTest
  static void getKpis_aggregates() {
    Account a = makeAccount();
    insert new List<Opportunity>{
      new Opportunity(
        Name = '成立1',
        StageName = 'Closed Won',
        CloseDate = Date.today(),
        Amount = 100000,
        AccountId = a.Id
      ),
      new Opportunity(
        Name = '成立2',
        StageName = 'Closed Won',
        CloseDate = Date.today(),
        Amount = 200000,
        AccountId = a.Id
      ),
      new Opportunity(
        Name = '進行1',
        StageName = 'Prospecting',
        CloseDate = Date.today().addDays(30),
        Amount = 300000,
        AccountId = a.Id
      ),
      new Opportunity(
        Name = '進行2',
        StageName = 'Qualification',
        CloseDate = Date.today().addDays(20),
        Amount = 400000,
        AccountId = a.Id
      )
    };
    insert new List<Contact>{
      new Contact(LastName = '連絡先1', AccountId = a.Id),
      new Contact(LastName = '連絡先2', AccountId = a.Id)
    };
    insert new List<Case>{
      new Case(Subject = 'open', Status = 'New', AccountId = a.Id),
      new Case(Subject = 'closed', Status = 'Closed', AccountId = a.Id)
    };

    Test.startTest();
    Account360Controller.Kpis k = Account360Controller.getKpis(a.Id);
    Test.stopTest();

    System.assertEquals(300000, k.closedWonThisMonthAmount, '今月成立額');
    System.assertEquals(2, k.openOppCount, '進行中件数');
    System.assertEquals(700000, k.openOppAmount, '進行中合計');
    System.assertEquals(1, k.openCaseCount, 'オープンケース数');
    System.assertEquals(2, k.contactCount, '連絡先数');
  }

  @IsTest
  static void getLists_returnRelated() {
    Account a = makeAccount();
    insert new Opportunity(
      Name = '商談',
      StageName = 'Prospecting',
      CloseDate = Date.today().addDays(10),
      Amount = 1000,
      AccountId = a.Id
    );
    insert new Contact(
      LastName = '連絡先',
      Title = '部長',
      Email = 'x@example.com',
      Phone = '000',
      AccountId = a.Id
    );
    insert new Case(
      Subject = 'ケース',
      Status = 'New',
      Priority = 'High',
      Origin = 'Phone',
      AccountId = a.Id
    );
    insert new Task(
      Subject = 'タスク',
      Status = 'Not Started',
      ActivityDate = Date.today(),
      WhatId = a.Id
    );
    Datetime st = Datetime.now().addDays(1);
    insert new Event(
      Subject = '行動',
      StartDateTime = st,
      EndDateTime = st.addHours(1),
      WhatId = a.Id
    );

    Test.startTest();
    System.assertEquals(
      1,
      Account360Controller.getOpportunities(a.Id).size(),
      '商談1件'
    );
    System.assertEquals(
      1,
      Account360Controller.getContacts(a.Id).size(),
      '連絡先1件'
    );
    System.assertEquals(
      1,
      Account360Controller.getCases(a.Id).size(),
      'ケース1件'
    );
    List<Account360Controller.ActivityRow> acts = Account360Controller.getActivities(
      a.Id
    );
    Test.stopTest();

    System.assertEquals(2, acts.size(), 'Task+Event で2件');
    Boolean hasToDo = false, hasEvent = false;
    for (Account360Controller.ActivityRow r : acts) {
      if (r.type == 'ToDo') {
        hasToDo = true;
      }
      if (r.type == '行動') {
        hasEvent = true;
      }
    }
    System.assert(hasToDo && hasEvent, 'ToDo と 行動 の両方を含む');
  }

  @IsTest
  static void updateOpportunities_savesDrafts() {
    Account a = makeAccount();
    Opportunity o = new Opportunity(
      Name = '編集対象',
      StageName = 'Prospecting',
      CloseDate = Date.today().addDays(10),
      Amount = 1000,
      AccountId = a.Id
    );
    insert o;

    Test.startTest();
    Account360Controller.updateOpportunities(
      new List<Opportunity>{ new Opportunity(Id = o.Id, Amount = 5000) }
    );
    Test.stopTest();

    System.assertEquals(
      5000,
      [SELECT Amount FROM Opportunity WHERE Id = :o.Id].Amount,
      '金額が更新されている'
    );
  }

  @IsTest
  static void updateOpportunities_empty_noop() {
    Test.startTest();
    Account360Controller.updateOpportunities(null);
    Account360Controller.updateOpportunities(new List<Opportunity>());
    Test.stopTest();
    System.assert(true, '空入力は例外なく何もしない');
  }

  @IsTest
  static void updateOpportunities_invalid_throws() {
    Account a = makeAccount();
    Opportunity o = new Opportunity(
      Name = '削除予定',
      StageName = 'Prospecting',
      CloseDate = Date.today().addDays(10),
      Amount = 1000,
      AccountId = a.Id
    );
    insert o;
    Id delId = o.Id;
    delete o;

    Boolean threw = false;
    Test.startTest();
    try {
      Account360Controller.updateOpportunities(
        new List<Opportunity>{ new Opportunity(Id = delId, Amount = 999) }
      );
    } catch (AuraHandledException e) {
      threw = true;
    }
    Test.stopTest();
    System.assert(threw, '削除済みレコードの更新は AuraHandledException');
  }
}
