import { createElement } from "lwc";
import OpportunityKanban from "c/opportunityKanban";
import getStages from "@salesforce/apex/OpportunityKanbanController.getStages";
import getOpportunities from "@salesforce/apex/OpportunityKanbanController.getOpportunities";
import updateStage from "@salesforce/apex/OpportunityKanbanController.updateStage";

// refreshApex はドロップ後に呼ばれることを確認できるようモックする
jest.mock(
  "@salesforce/apex",
  () => ({ refreshApex: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

// @wire 用の Apex メソッドは createApexTestWireAdapter で wire アダプタ化（.emit が使える）
jest.mock(
  "@salesforce/apex/OpportunityKanbanController.getStages",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OpportunityKanbanController.getOpportunities",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

// 商談更新（imperative）のモック
jest.mock(
  "@salesforce/apex/OpportunityKanbanController.updateStage",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const STAGES = [
  { apiName: "Prospecting", label: "見込み", isWon: false, isClosed: false },
  {
    apiName: "Qualification",
    label: "条件確認",
    isWon: false,
    isClosed: false
  },
  { apiName: "Closed Won", label: "成立（受注）", isWon: true, isClosed: true }
];

const OPPS = [
  {
    Id: "006000000000001",
    Name: "案件A",
    StageName: "Prospecting",
    Amount: 100000,
    CloseDate: "2026-06-30",
    AccountId: "001000000000001",
    Owner: { Name: "山田" }
  },
  {
    Id: "006000000000002",
    Name: "案件B",
    StageName: "Qualification",
    Amount: 250000,
    CloseDate: "2026-07-15",
    AccountId: "001000000000001",
    Owner: { Name: "佐藤" }
  }
];

function flushPromises() {
  return Promise.resolve();
}

describe("c-opportunity-kanban", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  async function createComponent() {
    const element = createElement("c-opportunity-kanban", {
      is: OpportunityKanban
    });
    document.body.appendChild(element);
    getStages.emit(STAGES);
    getOpportunities.emit(OPPS);
    await flushPromises();
    return element;
  }

  it("ステージごとに列を描画し、各カードを正しい列に置く", async () => {
    const element = await createComponent();

    const columns = element.shadowRoot.querySelectorAll(".kanban-column");
    expect(columns.length).toBe(STAGES.length);

    const cards = element.shadowRoot.querySelectorAll(".kanban-card");
    expect(cards.length).toBe(OPPS.length);

    const names = Array.from(
      element.shadowRoot.querySelectorAll(".kanban-card__name")
    ).map((el) => el.textContent);
    expect(names).toEqual(["案件A", "案件B"]);

    // 列見出しは日本語ラベルで表示される（apiName ではなく label）
    const titles = Array.from(
      element.shadowRoot.querySelectorAll(".kanban-column__title")
    ).map((el) => el.textContent);
    expect(titles).toEqual(["見込み", "条件確認", "成立（受注）"]);
  });

  it("列ヘッダーに件数と金額合計を表示する", async () => {
    const element = await createComponent();
    const metas = Array.from(
      element.shadowRoot.querySelectorAll(".kanban-column__meta")
    ).map((el) => el.textContent);
    // Prospecting: 1件 / ￥100,000
    expect(metas[0]).toContain("1件");
    expect(metas[0]).toContain("100,000");
    // Closed Won: 0件
    expect(metas[2]).toContain("0件");
  });

  it("カードを別の列にドロップすると updateStage が呼ばれる", async () => {
    updateStage.mockResolvedValue({ ...OPPS[0], StageName: "Qualification" });
    const element = await createComponent();

    const firstCard = element.shadowRoot.querySelector(".kanban-card");
    firstCard.dispatchEvent(new CustomEvent("dragstart"));

    // 2列目（Qualification）にドロップ
    const columns = element.shadowRoot.querySelectorAll(".kanban-column");
    columns[1].dispatchEvent(new CustomEvent("drop"));
    await flushPromises();
    await flushPromises();

    expect(updateStage).toHaveBeenCalledTimes(1);
    expect(updateStage).toHaveBeenCalledWith({
      opportunityId: "006000000000001",
      stageName: "Qualification"
    });
  });

  it("同じ列にドロップした場合は updateStage を呼ばない", async () => {
    const element = await createComponent();

    const firstCard = element.shadowRoot.querySelector(".kanban-card");
    firstCard.dispatchEvent(new CustomEvent("dragstart"));

    // 1列目（Prospecting＝元の列）にドロップ
    const columns = element.shadowRoot.querySelectorAll(".kanban-column");
    columns[0].dispatchEvent(new CustomEvent("drop"));
    await flushPromises();

    expect(updateStage).not.toHaveBeenCalled();
  });

  it("商談が無いときは空メッセージを表示する", async () => {
    const element = createElement("c-opportunity-kanban", {
      is: OpportunityKanban
    });
    document.body.appendChild(element);
    getStages.emit(STAGES);
    getOpportunities.emit([]);
    await flushPromises();

    const empty = element.shadowRoot.querySelector(".slds-text-color_weak");
    expect(empty).not.toBeNull();
    expect(empty.textContent).toContain("表示できる商談がありません");
  });
});
