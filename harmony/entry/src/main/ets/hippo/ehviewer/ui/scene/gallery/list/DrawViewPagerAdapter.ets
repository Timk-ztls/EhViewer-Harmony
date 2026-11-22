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
 * 移植自 app/src/main/java/com/hippo/ehviewer/ui/scene/gallery/list/DrawViewPagerAdapter.java（30 行）。
 *
 * ============================================================================
 * 一、上游做什么
 * ============================================================================
 * 一个 `PagerAdapter` 适配器，把**已创建好的 View 列表**逐页挂到容器上：
 *
 *   ```java
 *   instantiateItem(container, position)  → container.addView(mListView.get(position), 0); 返回该 View
 *   getCount()                            → mListView.size()
 *   isViewFromObject(view, object)        → view == object          ← 身份比较，不是内容比较
 *   destroyItem(container, position, obj) → container.removeView(mListView.get(position))
 *   ```
 *
 * 注意 `destroyItem` 用的是 **position 重新取一次**，而不是用传进来的 `object`
 * —— 语义上等价（列表在适配器生命周期内不变），但保留这个写法以免以后有人以为可以传任意对象。
 *
 * ============================================================================
 * 二、ArkTS 侧怎么对应
 * ============================================================================
 * ArkUI 没有 `PagerAdapter`：轮播/翻页用 `Swiper`，它按**数据数组**渲染，不接管 View 实例。
 * 所以这里保留的是**适配器语义本身**（页数 / 取页 / 身份判定 / 移除），不涉及 ArkUI 组件：
 *
 *   - `getCount()`   → `count()`（ArkTS 无 getXxx 属性式命名习惯，但**保留语义**）
 *   - `instantiateItem` → `itemAt(position)`：取页对象（调用方把它挂到自己的容器/Swiper 上）
 *   - `isViewFromObject` → `isSameItem(a, b)`：身份比较 `===`（**不是** deepEqual）
 *   - `destroyItem` → `positionOf(item)` 供调用方移除；上游按 position 移除，这里两样都给
 *
 * 为什么不做成 `Swiper` 的封装：`Swiper` 需要 `@Builder`，属 UI 组件层（ui-widget 的职责）；
 * 本文件只提供数据侧契约，避免把 UI 依赖引进一个纯适配器。
 */

/**
 * 页对象的通用形态。
 *
 * 上游是 `android.view.View`；ArkTS 侧调用方可能持有 `Component`/`Builder` 包装或纯数据快照，
 * 因此这里用 `Object` 承载，**只做身份比较与按位置取出**，不触碰任何字段。
 */
export class DrawViewPagerAdapter {
  /** 页对象列表（上游 `private List<View> mListView`；构造后不替换，元素可原地更新）。 */
  private readonly listView: Object[];

  constructor(listView: Object[]) {
    this.listView = listView;
  }

  /** 页数（上游 `getCount()`）。 */
  public count(): number {
    return this.listView.length;
  }

  /**
   * 取指定位置的页对象（上游 `instantiateItem(container, position)` 的**返回值**部分）。
   *
   * 上游同时做了 `container.addView(..., 0)`；ArkUI 里"挂载"由调用方的容器决定
   * （`Swiper` + `ForEach` 或自定义 Stack），所以这里只返回对象，不接管挂载。
   * 越界返回 `null`（上游会抛 `IndexOutOfBoundsException`，这里显式化，调用方须判空）。
   */
  public itemAt(position: number): Object | null {
    if (position < 0 || position >= this.listView.length) {
      return null;
    }
    return this.listView[position];
  }

  /**
   * 身份判定（上游 `isViewFromObject(view, object)`：`view == object`）。
   *
   * **必须是身份比较**：上游用 `==` 比引用，不是比内容 —— 换成内容比较会让
   * "两个内容相同但实例不同的页"被误判为同一页（Swiper 会因此复用错页）。
   */
  public isSameItem(a: Object | null, b: Object | null): boolean {
    return a === b;
  }

  /**
   * 页对象在列表中的位置（对应上游 `destroyItem` 里 `mListView.get(position)` 的取值）。
   *
   * 上游直接按 position 移除；ArkUI 侧调用方通常拿到的是对象本身（如 Swiper 的 onAnimationEnd），
   * 所以这里给 `indexOf`：找不到返回 `-1`（调用方据此跳过移除）。
   */
  public positionOf(item: Object | null): number {
    if (item === null) {
      return -1;
    }
    for (let i = 0; i < this.listView.length; i++) {
      if (this.listView[i] === item) {
        return i;
      }
    }
    return -1;
  }

  /** 原始列表（只读语义；上游字段 package-private，同包可直接读）。 */
  public items(): Object[] {
    return this.listView;
  }
}
