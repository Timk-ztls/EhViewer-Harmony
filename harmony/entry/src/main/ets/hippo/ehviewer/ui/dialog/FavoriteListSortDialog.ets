/*
 * Copyright 2026 ehviewer-harmony contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/**
 * 移植自 app/src/main/java/com/hippo/ehviewer/ui/dialog/FavoriteListSortDialog.kt（60 行）。
 *
 * ============================================================================
 * 一、上游做什么（以及一个容易漏掉的分支）
 * ============================================================================
 *   ```kotlin
 *   fun showCloudSort(mResult: FavoritesParser.Result?) {
 *       if (null == mResult || null == mResult.favOrder) return          // ① 没数据就不弹
 *       checked = when (mResult.favOrder) {
 *           EhConfig.ORDER_BY_FAV_TIME -> 0
 *           EhConfig.ORDER_BY_PUB_TIME -> 1
 *           else -> return                                               // ② 未知排序值 → 也不弹
 *       }
 *       ... setSingleChoiceItems(fav_sort, checked) { i -> scene.updateSort(if (i==0) "inline_set=fs_f" else "inline_set=fs_p") }
 *   }
 *   fun showLocalSort(mResult: FavoritesParser.Result?) { }              // ③ 上游是**空方法**
 *   ```
 *
 * ② 那一行最容易在移植时被"合并"成 `else -> 0`（默认选中第一项）——  但上游的语义是
 * **不弹对话框**。触点：服务端返回了一个我们不认识的排序值（`favOrder` 是服务端给的字符串，
 * 可能是 `fs_f` / `fs_p` / 未来新增值），此时弹框会让用户以为可以改，改完又被服务端覆盖。
 *
 * ③ `showLocalSort` 是空方法：不是"还没实现"，而是**本地收藏排序用不到这个对话框**
 * （本地列表按本地时间排、无云端排序参数）。移植保留空实现 + 注释，避免后人以为是 TODO。
 *
 * ============================================================================
 * 二、ArkTS 侧怎么对应
 * ============================================================================
 * 对话框本体用 ArkUI 的 `promptAction.showDialog` / `UIContext.showAlertDialog`（组件层职责），
 * 本文件只保留**决策**（纯函数、可断言）：弹不弹、选中哪项、点了回传什么 sort 串。
 *
 * 依赖（都已 land）：
 *   - `EhConfig.ORDER_BY_FAV_TIME` = `'f'`、`ORDER_BY_PUB_TIME` = `'p'`（`client/EhConfig.ets:234-235`）
 *   - `FavoritesResult.favOrder: string`（`client/parser/FavoritesParser.ets:134`）
 *
 * 未依赖 `FavoritesScene.updateSort`：那个方法在 ArkTS 侧属于 FavoritesScene（ui-scene 尚未落地），
 * 所以本文件只产出**要回传的 sort 串**（`inline_set=fs_f` / `inline_set=fs_p`），由调用方喂给场景。
 */

import { EhConfig } from '../../client/EhConfig';
import { FavoritesResult } from '../../client/parser/FavoritesParser';

/** 对话框决策（纯数据）。 */
export interface FavoriteSortDialogPlan {
  /** 是否应弹出对话框（上游的两个 return 分支 → false）。 */
  show: boolean;
  /** 单选初始选中项：0 = 收藏时间，1 = 发布时间（仅 show = true 时有意义）。 */
  checked: number;
}

/**
 * 云收藏排序对话框的**决策 + 回传值**（对位上游 `FavoriteListSortDialog`）。
 */
export class FavoriteListSortDialogPlan {
  /** 「按收藏时间」在下拉里的下标（上游 `checked = 0`）。 */
  public static readonly INDEX_FAV_TIME: number = 0;
  /** 「按发布时间」在下拉里的下标（上游 `checked = 1`）。 */
  public static readonly INDEX_PUB_TIME: number = 1;

  /** 回传给场景的排序串：按收藏时间（上游 `inline_set=fs_f`）。 */
  public static readonly SORT_FAV_TIME: string = 'inline_set=fs_f';
  /** 回传给场景的排序串：按发布时间（上游 `inline_set=fs_p`）。 */
  public static readonly SORT_PUB_TIME: string = 'inline_set=fs_p';

  /**
   * 是否弹框 + 初始选中项。
   *
   * @param result 上游 `FavoritesResult`（上游 `FavoritesParser.Result`）；`null` 或 `favOrder` 为空 → 不弹
   */
  static plan(result: FavoritesResult | null): FavoriteSortDialogPlan {
    if (result === null || result.favOrder.length === 0) {
      return { show: false, checked: FavoriteListSortDialogPlan.INDEX_FAV_TIME };
    }
    if (result.favOrder === EhConfig.ORDER_BY_FAV_TIME) {
      return { show: true, checked: FavoriteListSortDialogPlan.INDEX_FAV_TIME };
    }
    if (result.favOrder === EhConfig.ORDER_BY_PUB_TIME) {
      return { show: true, checked: FavoriteListSortDialogPlan.INDEX_PUB_TIME };
    }
    // 未知排序值：上游直接 return，**不弹框**（不能默认成"选第一项"）
    return { show: false, checked: FavoriteListSortDialogPlan.INDEX_FAV_TIME };
  }

  /**
   * 用户点选后要回传的 sort 串（上游 `if (i == 0) "inline_set=fs_f" else "inline_set=fs_p"`）。
   *
   * 上游是 `if (i == 0) … else …`：**非 0 一律当发布时间**，不校验范围。
   * 逐字保留这个语义（下拉只有 2 项，越界不可能），避免"多加一个校验"改变行为。
   */
  static sortForIndex(index: number): string {
    return index === FavoriteListSortDialogPlan.INDEX_FAV_TIME
      ? FavoriteListSortDialogPlan.SORT_FAV_TIME
      : FavoriteListSortDialogPlan.SORT_PUB_TIME;
  }

  /**
   * 本地收藏排序（上游 `fun showLocalSort(mResult) { }` —— **空方法**）。
   *
   * 保留为空：本地列表没有云端排序参数，这个对话框对本地排序无意义。
   * 不是 TODO，不要往里加逻辑。
   */
  static showLocalSort(_result: FavoritesResult | null): void {
    // 上游同为空实现
  }
}
