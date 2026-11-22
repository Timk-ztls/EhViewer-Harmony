/*
 * 移植自 app/src/main/java/com/hippo/ehviewer/ui/scene/gallery/list/QuickSearchScene.java
 * （清单 S0244 记 226 行，实际 279 行）。
 *
 * ============================================================================
 * 上游是什么（快速搜索管理页：删除 + 拖拽排序 + 空态切换）
 * ============================================================================
 *   ```java
 *   holder.onClick → 确认弹窗(title=delete_quick_search_title, message=delete_quick_search_message(name))
 *                    OK:      EhDB.deleteQuickSearch(item) + list.remove(position)
 *                    Dismiss: notifyDataSetChanged() + updateView()
 *   onMoveItem(from, to):
 *        if (from == to) return;                      ← **必须提前返回**
 *        EhDB.moveQuickSearch(from, to);              ← **先落库**
 *        item = list.remove(from); list.add(to, item) ← **再改内存**
 *   onCheckCanDrop → return true                       ← 恒真
 *   updateView → list != null && list.size() > 0 ? 显示列表(0) : 显示空态(1)
 *   onNavigationClick → onBackPressed()
 *   ```
 *
 * 逐行对照时最容易写错的**四条**（本文件逐条断言）：
 *   1. `onMoveItem` 的 `from == to` 要**提前 return** —— 否则 `remove` + `add` 会先把元素
 *      从 `from` 取出再插回 `to`，当两者相等时**位置不变但数组实例被换**（列表会闪一下），
 *      而在"跨位置"时如果漏了这层判断，UIKit 侧的动画会算错；
 *   2. **先落库后改内存**（`moveQuickSearch` 在数组变更之前）；
 *   3. 删除后的刷新在 **onDismiss**（不是 OK），所以"点了取消"也会刷新；
 *   4. `updateView` 判的是 `size() > 0`，`null` 与空数组都算空态。
 *
 * 不属于本文件：`EhDB` 落库、`QuickSearch` 实体、`DraggableItemAdapter` 手势 —— 全部通过注入。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;

/** 一条快速搜索记录（对位上游 `QuickSearch` 实体；storage-db 侧已有同名类）。 */
export interface QuickSearchItem {
  name: string;
  /** 上游 `QuickSearch.mode` / `tags` / `keyword` 等字段由 storage-db 承担，这里只保留排序/删除需要的 */
}

/** 落库能力（生产实现包 `EhDB.deleteQuickSearch` / `moveQuickSearch` / `listQuickSearch`）。 */
export interface QuickSearchStore {
  deleteQuickSearch(item: QuickSearchItem): void;
  moveQuickSearch(from: number, to: number): void;
  listQuickSearch(): QuickSearchItem[];
}

/** 页面要显示哪个视图（上游 `mViewTransition.showView(0/1)`）。 */
export enum QuickSearchView {
  /** 列表（0） */
  LIST = 0,
  /** 空态（1） */
  EMPTY = 1
}

export class QuickSearchScene {
  /** 删除确认弹窗标题（上游 `delete_quick_search_title`）。 */
  static readonly DELETE_TITLE_RES: string = 'delete_quick_search_title';
  /** 删除确认弹窗正文（上游 `delete_quick_search_message`，含 `%s` = 名称）。 */
  static readonly DELETE_MESSAGE_RES: string = 'delete_quick_search_message';
  /** 空态文案（上游布局 `scene_quick_search` 的空态视图）。 */
  static readonly EMPTY_RES: string = 'scene_quick_search_empty';

  /**
   * 视图选择（上游 `updateView`）：`size() > 0` → 列表，否则空态。
   *
   * `null`（尚未加载）与空数组**都算空态**。
   */
  static viewFor(items: QuickSearchItem[] | null): QuickSearchView {
    return items !== null && items.length > 0 ? QuickSearchView.LIST : QuickSearchView.EMPTY;
  }

  /** 删除确认正文的插值参数（上游 `getString(res, quickSearch.name)` 传的是**名称**）。 */
  static deleteMessageArgOf(item: QuickSearchItem): string {
    return item.name;
  }

  /**
   * 删除一项（上游 OK 分支）：**先删库，再删内存**。
   *
   * 顺序有意义：`deleteQuickSearch` 抛异常时内存不该变（否则界面与库不一致）。
   * 越界返回**原数组**（上游靠 `getAdapterPosition()` 判 `NO_POSITION` 提前返回）。
   */
  static applyDelete(items: QuickSearchItem[], position: number,
    store: QuickSearchStore): QuickSearchItem[] {
    if (position < 0 || position >= items.length) {
      return items;
    }
    store.deleteQuickSearch(items[position]);
    const next: QuickSearchItem[] = [];
    for (let i = 0; i < items.length; i++) {
      if (i !== position) {
        next.push(items[i]);
      }
    }
    return next;
  }

  /**
   * 拖拽排序（上游 `onMoveItem`）。
   *
   * 四条约束：
   *   ① `from === to` **立即返回原数组**（不落库、不换实例）；
   *   ② 越界返回原数组；
   *   ③ **先** `store.moveQuickSearch(from, to)`（库记的是逻辑位置）；
   *   ④ **再** 内存 `splice(from,1)` + `splice(to,0,moved)`。
   */
  static applyMove(items: QuickSearchItem[], from: number, to: number,
    store: QuickSearchStore): QuickSearchItem[] {
    if (from === to) {
      return items;
    }
    if (items === null || items === undefined) {
      return items;
    }
    if (from < 0 || from >= items.length || to < 0 || to >= items.length) {
      return items;
    }
    store.moveQuickSearch(from, to);
    const next: QuickSearchItem[] = items.slice();
    const moved: QuickSearchItem[] = next.splice(from, 1);
    next.splice(to, 0, moved[0]);
    return next;
  }

  /** 拖拽是否允许放下（上游 `onCheckCanDrop` **恒为 true**）。 */
  static canDrop(draggingPosition: number, dropPosition: number): boolean {
    return true;
  }

  /** 顶栏返回（上游 `onNavigationClick` → `onBackPressed`）。 */
  static readonly NAVIGATION_CLICKS_BACK: boolean = true;
}

/** 测试/占位用的 store（生产实现包 `EhDB`）。 */
export class NoopQuickSearchStore implements QuickSearchStore {
  deleted: string[] = [];
  moved: string[] = [];

  deleteQuickSearch(item: QuickSearchItem): void {
    this.deleted.push(item.name);
  }

  moveQuickSearch(from: number, to: number): void {
    this.moved.push(`${from}->${to}`);
  }

  listQuickSearch(): QuickSearchItem[] {
    hilog.info(DOMAIN, 'QuickSearchScene', 'listQuickSearch: 生产实现由 EhDB 提供');
    return [];
  }
}
