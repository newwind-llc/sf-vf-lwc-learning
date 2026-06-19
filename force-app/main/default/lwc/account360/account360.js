import { LightningElement, api, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getKpis from "@salesforce/apex/Account360Controller.getKpis";
import getOpportunities from "@salesforce/apex/Account360Controller.getOpportunities";
import getContacts from "@salesforce/apex/Account360Controller.getContacts";
import getCases from "@salesforce/apex/Account360Controller.getCases";
import getActivities from "@salesforce/apex/Account360Controller.getActivities";
import updateOpportunities from "@salesforce/apex/Account360Controller.updateOpportunities";

const OPP_COLUMNS = [
  {
    label: "商談名",
    fieldName: "link",
    type: "url",
    typeAttributes: { label: { fieldName: "Name" }, target: "_self" }
  },
  { label: "ステージ", fieldName: "StageName" },
  {
    label: "金額",
    fieldName: "Amount",
    type: "currency",
    typeAttributes: { currencyCode: "JPY" },
    editable: true
  },
  {
    label: "完了予定日",
    fieldName: "CloseDate",
    type: "date-local",
    editable: true
  }
];

const CONTACT_COLUMNS = [
  {
    label: "名前",
    fieldName: "link",
    type: "url",
    typeAttributes: { label: { fieldName: "Name" }, target: "_self" }
  },
  { label: "役職", fieldName: "Title" },
  { label: "メール", fieldName: "Email", type: "email" },
  { label: "電話", fieldName: "Phone", type: "phone" }
];

const CASE_COLUMNS = [
  {
    label: "番号",
    fieldName: "link",
    type: "url",
    typeAttributes: { label: { fieldName: "CaseNumber" }, target: "_self" }
  },
  { label: "件名", fieldName: "Subject" },
  { label: "状況", fieldName: "Status" },
  { label: "優先度", fieldName: "Priority" }
];

const ACTIVITY_COLUMNS = [
  { label: "種別", fieldName: "type", fixedWidth: 80 },
  {
    label: "件名",
    fieldName: "link",
    type: "url",
    typeAttributes: { label: { fieldName: "subject" }, target: "_self" }
  },
  { label: "状況", fieldName: "status" },
  { label: "日付", fieldName: "activityDate", type: "date-local" }
];

/**
 * 取引先360 コマンドセンター。
 * 取引先レコードページに置き、KPI＋関連レコード（商談/連絡先/ケース/活動）を集約表示する。
 * 商談タブは金額・完了予定日をインライン編集して保存できる。
 */
export default class Account360 extends LightningElement {
  /** 取引先レコードページで自動注入される取引先Id。 */
  @api recordId;

  oppColumns = OPP_COLUMNS;
  contactColumns = CONTACT_COLUMNS;
  caseColumns = CASE_COLUMNS;
  activityColumns = ACTIVITY_COLUMNS;

  oppDraftValues = [];
  isLoading = false;
  error;

  _wiredKpis;
  _kpis;
  _wiredOpps;
  _opps = [];
  _wiredContacts;
  _contacts = [];
  _wiredCases;
  _cases = [];
  _wiredActivities;
  _activities = [];

  @wire(getKpis, { accountId: "$recordId" })
  wiredKpis(result) {
    this._wiredKpis = result;
    if (result.data) {
      this._kpis = result.data;
      this.error = undefined;
    } else if (result.error) {
      this.error = this.reduceError(result.error);
    }
  }

  @wire(getOpportunities, { accountId: "$recordId" })
  wiredOpps(result) {
    this._wiredOpps = result;
    if (result.data) {
      this._opps = result.data;
    } else if (result.error) {
      this.error = this.reduceError(result.error);
    }
  }

  @wire(getContacts, { accountId: "$recordId" })
  wiredContacts(result) {
    this._wiredContacts = result;
    if (result.data) {
      this._contacts = result.data;
    }
  }

  @wire(getCases, { accountId: "$recordId" })
  wiredCases(result) {
    this._wiredCases = result;
    if (result.data) {
      this._cases = result.data;
    }
  }

  @wire(getActivities, { accountId: "$recordId" })
  wiredActivities(result) {
    this._wiredActivities = result;
    if (result.data) {
      this._activities = result.data;
    }
  }

  /** KPI カード（子 c-kpi-card へ渡す配列） */
  get kpiCards() {
    const k = this._kpis;
    if (!k) {
      return [];
    }
    return [
      {
        key: "won",
        label: "今月成立",
        value: this.formatCurrency(k.closedWonThisMonthAmount),
        iconName: "utility:success"
      },
      {
        key: "open",
        label: `進行中 ${k.openOppCount}件`,
        value: this.formatCurrency(k.openOppAmount),
        iconName: "utility:opportunity"
      },
      {
        key: "case",
        label: "オープンケース",
        value: String(k.openCaseCount),
        iconName: "utility:case"
      },
      {
        key: "contact",
        label: "連絡先",
        value: String(k.contactCount),
        iconName: "utility:contact"
      }
    ];
  }

  // datatable 用に、各行へレコードへのリンク(link)を付与する
  get opportunities() {
    return this._opps.map((o) => ({ ...o, link: `/lightning/r/${o.Id}/view` }));
  }
  get contacts() {
    return this._contacts.map((c) => ({
      ...c,
      link: `/lightning/r/${c.Id}/view`
    }));
  }
  get cases() {
    return this._cases.map((c) => ({
      ...c,
      link: `/lightning/r/${c.Id}/view`
    }));
  }
  get activities() {
    return this._activities.map((a) => ({
      ...a,
      link: `/lightning/r/${a.id}/view`
    }));
  }

  get oppTabLabel() {
    return `商談 (${this._opps.length})`;
  }
  get contactTabLabel() {
    return `連絡先 (${this._contacts.length})`;
  }
  get caseTabLabel() {
    return `ケース (${this._cases.length})`;
  }
  get activityTabLabel() {
    return `活動 (${this._activities.length})`;
  }

  get hasError() {
    return !!this.error;
  }

  /** 商談タブのインライン編集を保存 */
  async handleOppSave(event) {
    const drafts = event.detail.draftValues;
    this.isLoading = true;
    try {
      await updateOpportunities({ opportunities: drafts });
      this.dispatchEvent(
        new ShowToastEvent({
          title: "保存しました",
          message: `${drafts.length}件の商談を更新しました`,
          variant: "success"
        })
      );
      this.oppDraftValues = [];
      // 商談と、商談に依存する KPI を再取得
      await refreshApex(this._wiredOpps);
      await refreshApex(this._wiredKpis);
    } catch (e) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "保存に失敗しました",
          message: this.reduceError(e),
          variant: "error"
        })
      );
    } finally {
      this.isLoading = false;
    }
  }

  async handleRefresh() {
    this.isLoading = true;
    try {
      await Promise.all([
        refreshApex(this._wiredKpis),
        refreshApex(this._wiredOpps),
        refreshApex(this._wiredContacts),
        refreshApex(this._wiredCases),
        refreshApex(this._wiredActivities)
      ]);
    } finally {
      this.isLoading = false;
    }
  }

  formatCurrency(value) {
    return new Intl.NumberFormat("ja-JP", {
      style: "currency",
      currency: "JPY",
      maximumFractionDigits: 0
    }).format(value || 0);
  }

  reduceError(error) {
    if (Array.isArray(error && error.body)) {
      return error.body.map((e) => e.message).join(", ");
    }
    if (error && error.body && error.body.message) {
      return error.body.message;
    }
    if (error && typeof error.message === "string") {
      return error.message;
    }
    return "不明なエラーが発生しました。";
  }
}
