/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/scene/gallery/list/SubscriptionItemAdapter.java
 *       （inventory S0246，56 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/scene/gallery/list/SubscriptionItemAdapter.ets
 *
 * 背景：订阅（关注标签）列表的 adapter。条目布局 `subscripition_list_item`（**上游拼写如此**，少一个 t）
 * 由我在此之前移植（S0672）。
 *
 * ── 上游行为逐条对照 ────────────────────────────────────────────────────────
 * `SubscriptionItemAdapter(Context, UserTagList userTagList, EhTagDatabase ehTags)`
 *   字段：userTagList / inflater / ehTags
 *   构造：`this.ehTags = (ehTags == null) ? EhTagDatabase.getInstance(context) : ehTags`  → 见 1
 *   `getCount()`  → `userTagList.userTags.size()`                    → `getCount()`
 *   `getItem(pos)`→ `userTagList.userTags.get(pos)`（**返回 UserTag**）→ `getItem(pos)`
 *   `getItemId(pos)` → `Long.decode(getItem(pos).userTagId.substring(8))`
 *                     → `getItemId(pos)`（见 2：与 `UserTag.getId()` 同一实现，直接复用）
 *   `getView(pos, convertView, parent)`:
 *     `inflater.inflate(R.layout.subscripition_list_item, null)`
 *                       → ArkUI 由 `subscripition_list_item.ets` 渲染（无 convertView，**不复用**，见 3）
 *     `ImageView subscription_state`:
 *         `userTag.hidden`  → `R.drawable.ic_baseline_visibility_off_24`
 *         `userTag.watched` → `R.drawable.ic_baseline_visibility_24`
 *         （**注意上游是两个独立 if**：hidden 与 watched 可同时为真 → watched 的图标覆盖 hidden 的，见 4）
 *     `TextView label` → `textView.setText(userTag.getName(ehTags))`  → `getName()`（见 5）
 *
 * ── 平台差异 / 判断 ─────────────────────────────────────────────────────────
 * 1. 上游 `ehTags == null` 时用 `EhTagDatabase.getInstance(context)`。ArkTS 侧**不隐藏单例入口**：
 *    由调用方传入 `EhTagDatabase`（本仓库的 `EhTagDatabase` 是显式实例，没有 `getInstance` 语义）。
 *    若传入 null → 语义等价于"不翻译"（`UserTagConfig.getShowTagTranslations()` 默认 false），
 *    与上游"拿不到数据库时退回原名"的效果一致。
 * 2. `getItemId` 与 `UserTag.getId()` **完全同一算式**（`substring(8)` 去掉 `usertag_` 前缀）——
 *    直接调用 `userTag.getId()`，不重复实现（避免两处漂移）。
 * 3. **`convertView` 复用不存在于 ArkUI**：`List`/`LazyForEach` 按数据渲染，没有"转换视图"。
 *    故本类退化为**数据源**：count / 逐项 UserTag / 状态图标名。
 * 4. 上游用**两个独立 if** 而不是 else-if：`hidden=true, watched=true` 时最终显示 **watched 图标**
 *    （后一个 setImageResource 覆盖前一个）。本实现**逐字保留该顺序**（`resolveStateIconName()`）。
 * 5. `getName(ehTags)` 在本仓库签名是 `getName(config: UserTagConfig, ehTags: Object | null)`
 *    （翻译能力用 `UserTagConfig` 注入）→ 本类同样接收可选的 config，默认不翻译。
 *
 * ── 关联 ────────────────────────────────────────────────────────────────────
 * - 布局：`subscripition_list_item.ets`（S0672，已移植）
 * - 数据：`UserTag` / `UserTagList`（S0065/S0067，已移植，含 `getName` / `getId`）
 * - 图标：`ic_baseline_visibility_24` / `ic_baseline_visibility_off_24`
 *   → 存**资源名**，由渲染方查 `hippo/ui/drawable/` 组件表（本仓库 drawable 已迁成组件，无 media）
 */

import { UserTag, UserTagList, UserTagConfig } from '../../../../client/data/UserTag';

/** 订阅状态图标（上游 R.drawable.*，见文件头 4/5） */
export const ICON_VISIBILITY: string = 'ic_baseline_visibility_24';
export const ICON_VISIBILITY_OFF: string = 'ic_baseline_visibility_off_24';

export class SubscriptionItemAdapter {
  private userTagList: UserTagList;
  private ehTags: Object | null;
  private config: UserTagConfig;

  /**
   * @param userTagList 订阅标签列表（上游 `UserTagList`）
   * @param ehTags 标签库（上游 null 时取单例；这里 null = 不翻译，见文件头 1）
   * @param config 翻译能力注入（对应本仓库 `UserTag.getName(config, ehTags)` 的签名）
   */
  constructor(userTagList: UserTagList, ehTags: Object | null, config?: UserTagConfig) {
    this.userTagList = userTagList;
    this.ehTags = ehTags;
    this.config = config !== undefined ? config : new UserTagConfig();
  }

  /** 上游 `getCount()`：`userTagList.userTags.size()` */
  getCount(): number {
    return this.userTagList.userTags.length;
  }

  /** 上游 `getItem(position)`：返回 UserTag（越界抛错，不静默返回 null） */
  getItem(position: number): UserTag {
    if (position < 0 || position >= this.userTagList.userTags.length) {
      throw new Error(`Index ${position} out of bounds for length ${this.userTagList.userTags.length}`);
    }
    return this.userTagList.userTags[position];
  }

  /** 上游 `getItemId(position)`：`Long.decode(userTagId.substring(8))` = `UserTag.getId()`（见文件头 2） */
  getItemId(position: number): number {
    return this.getItem(position).getId();
  }

  /**
   * 上游 `getView()` 里 `subscription_state` 的图标：
   * **两个独立 if**（不是 else-if）—— hidden 先设、watched 后设并覆盖（见文件头 4）。
   * 返回 null 表示两者都不显示（上游没设图标 = 保持布局默认）。
   */
  resolveStateIconName(position: number): string | null {
    const userTag: UserTag = this.getItem(position);
    let icon: string | null = null;
    if (userTag.hidden) {
      icon = ICON_VISIBILITY_OFF;
    }
    if (userTag.watched) {
      icon = ICON_VISIBILITY;
    }
    return icon;
  }

  /** 上游 `textView.setText(userTag.getName(ehTags))` */
  getLabel(position: number): string {
    return this.getItem(position).getName(this.config, this.ehTags);
  }
}
