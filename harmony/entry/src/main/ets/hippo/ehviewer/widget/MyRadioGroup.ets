/**
 * 迁移自 app/src/main/java/com/hippo/ehviewer/widget/MyRadioGroup.java（inventory S0303，上游 115 行）
 *
 * ============================ 同源判断（先核差异，不预设结论） ============================
 * 上游 `MyRadioGroup extends RadioGroup` —— **注意父类不是 SimpleGridLayout，而是 AOSP 的 RadioGroup**。
 * 它只覆写了 `onMeasure` / `onLayout` 两个方法，把 RadioGroup 的**线性排列改成流式换行**；
 * **选择语义一个字都没改**（完全继承 AOSP RadioGroup）。
 *
 * ⇒ 判据结论：**子集 → 组合**（不是新实现）
 *   · 选择语义 = 已交付 `RadioGridGroup` 的状态机（`RadioGridGroupState`）
 *     （AOSP RadioGroup 的语义：点击已选项**保持选中不取消**；切换时只回调一次；clearCheck 不回调）
 *   · 布局语义 = 流式换行 = 已交付 `FlowLayout` 的同一种 `Flex({wrap: Wrap})`
 *   两者都已存在，故本文件**只做组合**，不重写任何选择逻辑（重写就是"同一个算法两处实现"）。
 *
 * ⚠ 与 `RadioGridGroup` 的唯一实质差异：**布局**（网格 `Flex wrap` + 子项宽度由调用方决定 vs 这里的流式换行）。
 *   上游 `RadioGridGroup`(hippo/widget) 继承 `SimpleGridLayout`（等宽列），`MyRadioGroup` 继承 `RadioGroup`（流式）。
 *   **两者的选择语义相同**，这一点用对照断言证明（见 MR 说明）。
 *
 * 上游 onMeasure 的流式算法细节（与 FlowLayout 略有不同）：
 *   `if (lineWidth + deltaX + paddingLeft + paddingRight > widthSize)` → 换行
 *   `maxWidth = Math.max(lineWidth, oldWidth)`（**换行时用 oldWidth，不含当前子项**）
 *   `totalHeight += oldHeight`（**累加的是上一行的高度**）
 *   宽度模式 EXACTLY → 用 widthSize；否则用 maxWidth
 *   ⇒ 这是"手写流式换行"的常见写法，与 `Flex({wrap: Wrap})` 的净效果一致（本移植不重写）。
 *
 * 差异（已登记 MR）：
 *   1) 上游 `RadioGroup` 的 `getChildAt` 遍历在 ArkUI 无对位 → 子项由调用方按 index 渲染，
 *      点击调 `state.onChildChecked(index, true)`
 *   2) 上游 `setOnCheckedChangeListener` 的 `(group, checkedId)` 二参 → 本实现沿用
 *      `RadioGridGroupState.listener`（同一接口）
 *   3) 上游 `check(id)` 的 id 是 View id；ArkTS 用数字 index（与 RadioGridGroup 一致）
 */
import { RadioGridGroupState, OnCheckedChangeListener } from '../../widget/RadioGridGroup';

export { RadioGridGroupState, OnCheckedChangeListener };

@Component
export struct MyRadioGroup {
  /** 复用 RadioGridGroup 的选择状态机（选择语义与 AOSP RadioGroup 一致：已选项不可取消） */
  state: RadioGridGroupState = new RadioGridGroupState();
  @Prop itemCount: number = 0;
  /** 子项渲染（流式换行：子项宽度由内容决定，与上游 measureChildren 的净效果一致） */
  @BuilderParam item: (index: number) => void = this.emptyItem;

  @Builder
  emptyItem(index: number): void {
  }

  private indices(): number[] {
    const arr: number[] = [];
    for (let i = 0; i < this.itemCount; i++) {
      arr.push(i);
    }
    return arr;
  }

  build() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
      ForEach(this.indices(), (index: number) => {
        Column() {
          this.item(index)
        }
        .onClick(() => {
          // 与 AOSP RadioGroup 一致：点击已选项保持选中（onChildChecked 内部会早退）
          this.state.onChildChecked(index, true);
        })
      }, (index: number) => `${index}`)
    }
    .width('100%')
  }
}
