/**
 * 取引先360 コマンドセンター（LWC `account360`）用コントローラ。
 *
 * 1取引先について、KPI と 関連レコード（商談 / 連絡先 / ケース / 活動）をまとめて返す。
 * 商談タブのインライン編集（金額・完了予定日）は `updateOpportunities` で保存する。
 *
 * 設計メモ:
 *  - 読み取りは SOQL `WITH USER_MODE`、書き込みは `Database.update(rec, AccessLevel.USER_MODE)`
 *    （CRUD/FLS をユーザー権限で強制）。
 *  - 読み取り専用（@wire 用）は cacheable=true、保存（DML）は imperative 用。
 *  - 活動は Task と Event を1つの DTO（ActivityRow）に統合して返す。
 */
public with sharing class Account360Controller {
  /** KPI カード用の集計値（LWC へ返す DTO） */
  public class Kpis {
    @AuraEnabled
    public Decimal closedWonThisMonthAmount;
    @AuraEnabled
    public Integer openOppCount;
    @AuraEnabled
    public Decimal openOppAmount;
    @AuraEnabled
    public Integer openCaseCount;
    @AuraEnabled
    public Integer contactCount;
  }

  /** 活動タブ用に Task / Event を統合した1行 */
  public class ActivityRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String subject;
    @AuraEnabled
    public String type; // 'ToDo'（Task）/ '行動'（Event）
    @AuraEnabled
    public String status; // Task.Status（Event は '—'）
    @AuraEnabled
    public Date activityDate;

    public ActivityRow(
      Id id,
      String subject,
      String type,
      String status,
      Date activityDate
    ) {
      this.id = id;
      this.subject = subject;
      this.type = type;
      this.status = status;
      this.activityDate = activityDate;
    }
  }

  /** KPI（今月成立額 / 進行中商談 件数・額 / オープンケース数 / 連絡先数）。 */
  @AuraEnabled(cacheable=true)
  public static Kpis getKpis(Id accountId) {
    Kpis k = new Kpis();
    k.closedWonThisMonthAmount = 0;
    k.openOppCount = 0;
    k.openOppAmount = 0;

    for (AggregateResult ar : [
      SELECT SUM(Amount) s
      FROM Opportunity
      WHERE AccountId = :accountId AND IsWon = TRUE AND CloseDate = THIS_MONTH
      WITH USER_MODE
    ]) {
      Decimal s = (Decimal) ar.get('s');
      k.closedWonThisMonthAmount = s == null ? 0 : s;
    }

    for (AggregateResult ar : [
      SELECT COUNT(Id) c, SUM(Amount) s
      FROM Opportunity
      WHERE AccountId = :accountId AND IsClosed = FALSE
      WITH USER_MODE
    ]) {
      k.openOppCount = (Integer) ar.get('c');
      Decimal s = (Decimal) ar.get('s');
      k.openOppAmount = s == null ? 0 : s;
    }

    k.openCaseCount = [
      SELECT COUNT()
      FROM Case
      WHERE AccountId = :accountId AND IsClosed = FALSE
      WITH USER_MODE
    ];
    k.contactCount = [
      SELECT COUNT()
      FROM Contact
      WHERE AccountId = :accountId
      WITH USER_MODE
    ];
    return k;
  }

  /** 商談タブ（インライン編集対象）。 */
  @AuraEnabled(cacheable=true)
  public static List<Opportunity> getOpportunities(Id accountId) {
    return [
      SELECT Id, Name, StageName, Amount, CloseDate
      FROM Opportunity
      WHERE AccountId = :accountId
      WITH USER_MODE
      ORDER BY IsClosed ASC, CloseDate ASC, Amount DESC NULLS LAST
    ];
  }

  /** 連絡先タブ。 */
  @AuraEnabled(cacheable=true)
  public static List<Contact> getContacts(Id accountId) {
    return [
      SELECT Id, Name, Title, Email, Phone
      FROM Contact
      WHERE AccountId = :accountId
      WITH USER_MODE
      ORDER BY Name
    ];
  }

  /** ケースタブ。 */
  @AuraEnabled(cacheable=true)
  public static List<Case> getCases(Id accountId) {
    return [
      SELECT Id, CaseNumber, Subject, Status, Priority, IsClosed, CreatedDate
      FROM Case
      WHERE AccountId = :accountId
      WITH USER_MODE
      ORDER BY IsClosed ASC, CreatedDate DESC
    ];
  }

  /** 活動タブ（Task と Event を統合）。 */
  @AuraEnabled(cacheable=true)
  public static List<ActivityRow> getActivities(Id accountId) {
    List<ActivityRow> rows = new List<ActivityRow>();
    for (Task t : [
      SELECT Id, Subject, Status, ActivityDate
      FROM Task
      WHERE WhatId = :accountId
      WITH USER_MODE
      ORDER BY ActivityDate DESC NULLS LAST
    ]) {
      rows.add(
        new ActivityRow(t.Id, t.Subject, 'ToDo', t.Status, t.ActivityDate)
      );
    }
    for (Event e : [
      SELECT Id, Subject, ActivityDate
      FROM Event
      WHERE WhatId = :accountId
      WITH USER_MODE
      ORDER BY ActivityDate DESC NULLS LAST
    ]) {
      rows.add(new ActivityRow(e.Id, e.Subject, '行動', '—', e.ActivityDate));
    }
    return rows;
  }

  /**
   * 商談タブのインライン編集を保存（金額・完了予定日など）。
   * datatable の draftValues（Id ＋ 編集項目）をそのまま受け取り、USER_MODE で更新。
   */
  @AuraEnabled
  public static void updateOpportunities(List<Opportunity> opportunities) {
    if (opportunities == null || opportunities.isEmpty()) {
      return;
    }
    try {
      Database.update(opportunities, AccessLevel.USER_MODE);
    } catch (DmlException e) {
      String msg = e.getDmlMessage(0) != null
        ? e.getDmlMessage(0)
        : e.getMessage();
      AuraHandledException ex = new AuraHandledException(msg);
      ex.setMessage(msg);
      throw ex;
    }
  }
}
