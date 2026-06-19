import { createElement } from "lwc";
import Account360 from "c/account360";
import getKpis from "@salesforce/apex/Account360Controller.getKpis";
import getOpportunities from "@salesforce/apex/Account360Controller.getOpportunities";
import getContacts from "@salesforce/apex/Account360Controller.getContacts";
import getCases from "@salesforce/apex/Account360Controller.getCases";
import getActivities from "@salesforce/apex/Account360Controller.getActivities";
import updateOpportunities from "@salesforce/apex/Account360Controller.updateOpportunities";

jest.mock(
  "@salesforce/apex",
  () => ({ refreshApex: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

// @wire 用の Apex は createApexTestWireAdapter で wire アダプタ化（.emit が使える）。
// jest.mock は巻き上げ対象のため、パスをリテラルで個別に書く必要がある。
jest.mock(
  "@salesforce/apex/Account360Controller.getKpis",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/Account360Controller.getOpportunities",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/Account360Controller.getContacts",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/Account360Controller.getCases",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/Account360Controller.getActivities",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/Account360Controller.updateOpportunities",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const KPIS = {
  closedWonThisMonthAmount: 2000000,
  openOppCount: 7,
  openOppAmount: 6800000,
  openCaseCount: 2,
  contactCount: 3
};
const OPPS = [
  {
    Id: "006A",
    Name: "見積提示D",
    StageName: "Proposal/Price Quote",
    Amount: 3000000,
    CloseDate: "2026-06-29"
  },
  {
    Id: "006B",
    Name: "ニーズ分析B",
    StageName: "Needs Analysis",
    Amount: 1200000,
    CloseDate: "2026-07-14"
  }
];
const CONTACTS = [
  {
    Id: "003A",
    Name: "山田 太郎",
    Title: "営業部長",
    Email: "y@example.com",
    Phone: "03"
  }
];
const CASES = [
  {
    Id: "500A",
    CaseNumber: "00001",
    Subject: "ログイン",
    Status: "New",
    Priority: "High"
  }
];
const ACTIVITIES = [
  {
    id: "00TA",
    subject: "見積フォロー",
    type: "ToDo",
    status: "Not Started",
    activityDate: "2026-06-21"
  },
  {
    id: "00UA",
    subject: "定例MTG",
    type: "行動",
    status: "—",
    activityDate: "2026-06-22"
  }
];

function flushPromises() {
  return Promise.resolve();
}

describe("c-account360", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  async function createComponent() {
    const element = createElement("c-account360", { is: Account360 });
    document.body.appendChild(element);
    getKpis.emit(KPIS);
    getOpportunities.emit(OPPS);
    getContacts.emit(CONTACTS);
    getCases.emit(CASES);
    getActivities.emit(ACTIVITIES);
    await flushPromises();
    return element;
  }

  it("KPI カードを4枚、集計値つきで描画する", async () => {
    const element = await createComponent();
    const cards = element.shadowRoot.querySelectorAll("c-kpi-card");
    expect(cards.length).toBe(4);
    expect(cards[0].label).toBe("今月成立");
    expect(cards[0].value).toContain("2,000,000");
    expect(cards[1].label).toBe("進行中 7件");
    expect(cards[2].value).toBe("2");
    expect(cards[3].value).toBe("3");
  });

  it("4タブそれぞれに datatable を描画し、タブ見出しに件数を出す", async () => {
    const element = await createComponent();
    const tables = element.shadowRoot.querySelectorAll("lightning-datatable");
    expect(tables.length).toBe(4);
    expect(tables[0].data.length).toBe(OPPS.length);

    const tabs = element.shadowRoot.querySelectorAll("lightning-tab");
    const labels = Array.from(tabs).map((t) => t.label);
    expect(labels).toEqual([
      "商談 (2)",
      "連絡先 (1)",
      "ケース (1)",
      "活動 (2)"
    ]);
  });

  it("商談タブのインライン編集を保存すると updateOpportunities が呼ばれる", async () => {
    updateOpportunities.mockResolvedValue();
    const element = await createComponent();

    const oppTable = element.shadowRoot.querySelectorAll(
      "lightning-datatable"
    )[0];
    oppTable.dispatchEvent(
      new CustomEvent("save", {
        detail: { draftValues: [{ Id: "006A", Amount: 9999 }] }
      })
    );
    await flushPromises();
    await flushPromises();

    expect(updateOpportunities).toHaveBeenCalledTimes(1);
    expect(updateOpportunities).toHaveBeenCalledWith({
      opportunities: [{ Id: "006A", Amount: 9999 }]
    });
  });
});
