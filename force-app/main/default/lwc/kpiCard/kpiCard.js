import { LightningElement, api } from "lwc";

/**
 * KPI を1枚表示する小さな再利用コンポーネント（`account360` の子）。
 * 親から `label` / `value` / `icon-name` を `@api` で受け取って表示するだけ。
 */
export default class KpiCard extends LightningElement {
  @api label;
  @api value;
  @api iconName;
}
