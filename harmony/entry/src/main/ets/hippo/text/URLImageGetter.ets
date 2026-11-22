/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0464   上游: com/hippo/text/URLImageGetter.java（36 行）
 * 目标   : harmony/entry/src/main/ets/hippo/text/URLImageGetter.ets
 *
 * 【D-033 拆分】上游实现 `Html.ImageGetter`，`getDrawable(source)` 做两件事：
 *   1. `new UnikeryDrawable(mTextView, mConaco)` —— **UI 对象**（Drawable 回调到 View 重绘）→ ui-widget
 *   2. `drawable.load(source)` —— **发起 Conaco 加载** → 本文件
 * 故本文件只保留第 2 步的**编排契约**：创建 unikery → 触发 load → 交回给调用方。
 *
 * 平台差异：
 *  1. `Drawable` → `UnikeryLike` 接口（`load(url)` + 可选的 `setUrl`），由 ui-widget 的
 *     ArkUI 组件（Image + 自定义 loader）实现。
 *  2. `Conaco<Image>` → 已落地的 `hippo/conaco/Conaco`，但**这里不直接持有**：
 *     加载动作由 `createUnikery` 的返回值完成（上游 `drawable.load()` 内部才碰 conaco）。
 *     这样 `URLImageGetter` 不依赖 Conaco 的泛型参数 `Image`（那是 ui-widget 的图片类型）。
 *  3. **`source` 为 null 的处理**：上游 `drawable.load(null)` 会走到 ConacoTask 的 URL 校验并失败，
 *     没有显式判空。这里保持"不判空、直接传下去"——判空会改变上游的失败路径（应报错的地方变成静默）。
 */

/** ui-widget 提供的 Drawable 等价物：只需能"按 URL 加载" */
export interface UnikeryLike {
  load(url: string): void;
}

export class URLImageGetter {
  private readonly createUnikery: () => UnikeryLike;

  /**
   * @param createUnikery 对应上游 `new UnikeryDrawable(mTextView, mConaco)` ——
   *                      UI 侧提供"造一个能加载图片的 Drawable"的工厂
   */
  constructor(createUnikery: () => UnikeryLike) {
    this.createUnikery = createUnikery;
  }

  /**
   * 对应上游 `getDrawable(String source)`：
   * **先建 unikery，再 load**（顺序不能反：load 内部会把结果回调给 unikery）。
   */
  getDrawable(source: string): UnikeryLike {
    const unikery: UnikeryLike = this.createUnikery();
    unikery.load(source);
    return unikery;
  }
}