import { LightningElement, api, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getStages from "@salesforce/apex/OpportunityKanbanController.getStages";
import getOpportunities from "@salesforce/apex/OpportunityKanbanController.getOpportunities";
import updateStage from "@salesforce/apex/OpportunityKanbanController.updateStage";

/**
 * 商談カンバン（パイプライン）ボード。
 *
 * 商談を OpportunityStage ごとの列に並べ、カードをドラッグ&ドロップで別の列へ
 * 移すと StageName を更新する。列ヘッダーには件数と金額合計をライブ表示する。
 *
 * 配置:
 *  - 取引先レコードページ … `recordId`（取引先Id）が自動注入され、その取引先の商談を表示。
 *  - アプリ/ホームページ … `recordId` は undefined。未完了(open)の商談を表示。
 */
export default class OpportunityKanban extends LightningElement {
  /** 取引先レコードページでは取引先Idが自動注入される（他ページでは undefined）。 */
  @api recordId;

  stages = [];
  error;
  isLoading = false;

  _draggedOppId;
  _wiredOpps; // refreshApex 用に wire 結果を保持
  _opportunities = [];

  @wire(getStages)
  wiredStages({ data, error }) {
    if (data) {
      this.stages = data;
      this.error = undefined;
    } else if (error) {
      this.error = this.reduceError(error);
    }
  }

  @wire(getOpportunities, { accountId: "$recordId" })
  wiredOpportunities(result) {
    this._wiredOpps = result;
    if (result.data) {
      this._opportunities = result.data;
      this.error = undefined;
    } else if (result.error) {
      this.error = this.reduceError(result.error);
    }
  }

  /** ステージごとに商談をまとめ、金額合計を計算した列の配列を返す。 */
  get columns() {
    const byStage = {};
    for (const s of this.stages) {
      // 列のキー/照合は apiName（StageName の英語値）、表示は label（日本語）
      byStage[s.apiName] = {
        key: s.apiName,
        apiName: s.apiName,
        label: s.label,
        cards: [],
        total: 0,
        cssClass: this.columnClass(s)
      };
    }
    for (const opp of this._opportunities) {
      const col = byStage[opp.StageName];
      if (!col) {
        continue; // 有効でないステージの商談は表示しない
      }
      col.cards.push({
        id: opp.Id,
        name: opp.Name,
        formattedAmount: this.formatCurrency(opp.Amount),
        closeDate: opp.CloseDate,
        owner: opp.Owner ? opp.Owner.Name : ""
      });
      col.total += opp.Amount || 0;
    }
    return this.stages.map((s) => {
      const col = byStage[s.apiName];
      return {
        ...col,
        count: col.cards.length,
        formattedTotal: this.formatCurrency(col.total)
      };
    });
  }

  get hasError() {
    return !!this.error;
  }

  get isEmpty() {
    return !this.error && this._opportunities.length === 0;
  }

  // ───────── ドラッグ & ドロップ ─────────

  handleDragStart(event) {
    this._draggedOppId = event.currentTarget.dataset.id;
    // jsdom など dataTransfer が無い環境でも落ちないようガード
    if (event.dataTransfer) {
      event.dataTransfer.effectAllowed = "move";
    }
  }

  handleDragOver(event) {
    event.preventDefault();
    if (event.dataTransfer) {
      event.dataTransfer.dropEffect = "move";
    }
  }

  async handleDrop(event) {
    event.preventDefault();
    const newStage = event.currentTarget.dataset.stage;
    const oppId = this._draggedOppId;
    this._draggedOppId = undefined;
    if (!oppId || !newStage) {
      return;
    }
    const current = this._opportunities.find((o) => o.Id === oppId);
    if (!current || current.StageName === newStage) {
      return; // 元と同じ列にドロップしたら何もしない
    }

    // Toast 表示用に、移動先ステージの日本語ラベルを引く（無ければ API 値）
    const targetStage = this.stages.find((s) => s.apiName === newStage);
    const targetLabel = targetStage ? targetStage.label : newStage;

    this.isLoading = true;
    try {
      await updateStage({ opportunityId: oppId, stageName: newStage });
      this.dispatchEvent(
        new ShowToastEvent({
          title: "更新しました",
          message: `「${current.Name}」を ${targetLabel} に移動しました`,
          variant: "success"
        })
      );
      await refreshApex(this._wiredOpps);
    } catch (e) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "更新に失敗しました",
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
      await refreshApex(this._wiredOpps);
    } finally {
      this.isLoading = false;
    }
  }

  // ───────── ヘルパー ─────────

  formatCurrency(value) {
    const amount = value || 0;
    return new Intl.NumberFormat("ja-JP", {
      style: "currency",
      currency: "JPY",
      maximumFractionDigits: 0
    }).format(amount);
  }

  columnClass(stage) {
    if (stage.isWon) {
      return "kanban-column kanban-column_won";
    }
    if (stage.isClosed) {
      return "kanban-column kanban-column_lost";
    }
    return "kanban-column";
  }

  /** Apex / wire のエラーを表示用の文字列に整える。 */
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
