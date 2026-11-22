/**
 * 迁移自 app/src/main/java/com/hippo/widget/OffsetLayout.java（inventory S0534，上游 126 行）
 *
 * 上游：`FrameLayout` 的自定义子布局——按子项 gravity 摆放后**再叠加 offsetX/offsetY**。
 *   layoutChildrenEx(left, top, right, bottom, forceLeftGravity)：
 *     parentLeft = paddingLeft; parentRight = (right-left) - paddingRight
 *     parentTop = paddingTop;   parentBottom = (bottom-top) - paddingBottom
 *     水平：CENTER_HORIZONTAL → parentLeft + (parentRight-parentLeft-width)/2 + leftMargin - rightMargin
 *           RIGHT             → parentRight - width - rightMargin（**forceLeftGravity 时降级为 LEFT**）
 *           LEFT/default      → parentLeft + leftMargin
 *     垂直：TOP → parentTop + topMargin
 *           CENTER_VERTICAL → parentTop + (parentBottom-parentTop-height)/2 + topMargin - bottomMargin
 *           BOTTOM → parentBottom - height - bottomMargin
 *           default → parentTop + topMargin
 *     **最终 child.layout(childLeft + offsetX, childTop + offsetY, ...)** —— 纯加法叠加
 *
 * ============================ Lead 提的三个边界，一手答案 ============================
 * ① **偏移超过自身尺寸 → 上游完全不钳制**：`childLeft + lp.offsetX` 直接相加，没有 clamp。
 *    ⇒ 子项可以被完全推出父容器（显示上被 `clipChildren`（默认 true）裁掉，但**布局坐标确实是移出的**）。
 *    **本移植不加 clamp** —— 加了就偏离上游，而且会破坏"用 OffsetLayout 做视差/滑出动效"的用法。
 * ② **父容器尺寸为 0 → 不存在除零**：除法只有 `/2`（常量除数），不是除以尺寸。
 *    真正会出问题的是 `(parentRight-parentLeft-width)/2` 变成负数 → 坐标为负，**但不崩**。
 *    ⚠ 若在这里自作聪明写 `clamp(x, 0, parentWidth - childWidth)`，`parentWidth=0` 时上界为负，
 *    `max(0, 负)` 会静默变成 0 —— **那才是引入 bug**。上游没有 clamp，故本实现也不写。
 * ③ **负偏移与正偏移完全对称**：`+ offsetX` 是纯加法，没有符号分支。断言覆盖正/负/零。
 *
 * 另一个容易漏的细节：**整数除法向零截断**
 *   Java `(parentRight-parentLeft-width)/2` 在差值非偶时向下取整（正数）→ CENTER 偏向 parentLeft。
 *   ArkTS 的 `Math.trunc(a/2)` 与之等价；直接写 `Math.round` 会让奇数差值的居中位置差 1px。
 *
 * 差异（已登记 MR）：
 *   1) `LayoutParams.gravity/offsetX/offsetY/margins` 在 ArkUI 无对应物 → 由调用方按 index 提供
 *      `ChildLayoutSpec`（具名类，ArkTS 禁止无类型对象字面量）。
 *   2) `forceLeftGravity`（RTL 降级）保留在数学函数里；ArkUI 侧由 `isRtl` 传入。
 *   3) 上游 `GONE` 子项跳过 → ArkUI 由调用方只传入可见项（或传 visible=false 跳过）。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'HippoWidget.OffsetLayout';

/** 对位 android.view.Gravity 中本类用到的位（数值与 Android 一致） */
export class Gravity {
  static readonly LEFT: number = 0x03;
  static readonly RIGHT: number = 0x05;
  static readonly CENTER_HORIZONTAL: number = 0x01;
  static readonly TOP: number = 0x30;
  static readonly BOTTOM: number = 0x50;
  static readonly CENTER_VERTICAL: number = 0x10;
  static readonly HORIZONTAL_GRAVITY_MASK: number = 0x07;
  static readonly VERTICAL_GRAVITY_MASK: number = 0x70;
  /** 上游：gravity == -1 时默认 TOP|LEFT */
  static readonly DEFAULT_GRAVITY: number = 0x33;
}

/** 子项的布局参数（对位 LayoutParams 里本类读取的字段） */
export class ChildLayoutSpec {
  gravity: number = Gravity.DEFAULT_GRAVITY;
  offsetX: number = 0;
  offsetY: number = 0;
  leftMargin: number = 0;
  topMargin: number = 0;
  rightMargin: number = 0;
  bottomMargin: number = 0;
  width: number = 0;
  height: number = 0;
  visible: boolean = true;
}

export class LayoutBox {
  left: number = 0;
  top: number = 0;

  constructor(left: number, top: number) {
    this.left = left;
    this.top = top;
  }
}

/** 布局数学（纯函数，可单测；逐式对位上游，**不做任何 clamp**） */
export class OffsetLayoutMath {
  /** Java 整数除法：向零截断（负值也向零） */
  static intDiv(a: number, b: number): number {
    return Math.trunc(a / b);
  }

  static childLeft(spec: ChildLayoutSpec, parentLeft: number, parentRight: number, rtl: boolean): number {
    const g: number = spec.gravity === -1 ? Gravity.DEFAULT_GRAVITY : spec.gravity;
    switch (g & Gravity.HORIZONTAL_GRAVITY_MASK) {
      case Gravity.CENTER_HORIZONTAL:
        return parentLeft + OffsetLayoutMath.intDiv(parentRight - parentLeft - spec.width, 2)
          + spec.leftMargin - spec.rightMargin;
      case Gravity.RIGHT:
        if (!rtl) {
          return parentRight - spec.width - spec.rightMargin;
        }
        return parentLeft + spec.leftMargin;
      case Gravity.LEFT:
      default:
        return parentLeft + spec.leftMargin;
    }
  }

  static childTop(spec: ChildLayoutSpec, parentTop: number, parentBottom: number): number {
    const g: number = spec.gravity === -1 ? Gravity.DEFAULT_GRAVITY : spec.gravity;
    switch (g & Gravity.VERTICAL_GRAVITY_MASK) {
      case Gravity.TOP:
        return parentTop + spec.topMargin;
      case Gravity.CENTER_VERTICAL:
        return parentTop + OffsetLayoutMath.intDiv(parentBottom - parentTop - spec.height, 2)
          + spec.topMargin - spec.bottomMargin;
      case Gravity.BOTTOM:
        return parentBottom - spec.height - spec.bottomMargin;
      default:
        return parentTop + spec.topMargin;
    }
  }

  /** 上游 child.layout(childLeft + offsetX, childTop + offsetY, …)：**纯加法，不 clamp** */
  static applyOffset(base: number, offset: number): number {
    return base + offset;
  }

  /** 计算最终位置（对位一次 layoutChildrenEx 的子项处理） */
  static layout(spec: ChildLayoutSpec, parentLeft: number, parentRight: number,
                parentTop: number, parentBottom: number, rtl: boolean): LayoutBox {
    const left: number = OffsetLayoutMath.applyOffset(
      OffsetLayoutMath.childLeft(spec, parentLeft, parentRight, rtl), spec.offsetX);
    const top: number = OffsetLayoutMath.applyOffset(
      OffsetLayoutMath.childTop(spec, parentTop, parentBottom), spec.offsetY);
    return new LayoutBox(left, top);
  }
}

@Component
export struct OffsetLayout {
  specs: ChildLayoutSpec[] = [];
  @Prop paddingLeftValue: number = 0;
  @Prop paddingTopValue: number = 0;
  @Prop paddingRightValue: number = 0;
  @Prop paddingBottomValue: number = 0;
  /** 对位上游 forceLeftGravity（RTL 时 RIGHT 降级为 LEFT） */
  @Prop isRtl: boolean = false;
  @BuilderParam item: (index: number) => void = this.emptyItem;
  /** 容器实测尺寸（onAreaChange 写入），用于把 padding 转成父边界 */
  @State boxW: number = 0;
  @State boxH: number = 0;

  /** 对位一次 layoutChildrenEx：parentRight = boxW - paddingRight，parentBottom = boxH - paddingBottom */
  private boxAt(index: number): LayoutBox {
    return OffsetLayoutMath.layout(this.specs[index], this.paddingLeftValue,
      this.boxW - this.paddingRightValue, this.paddingTopValue, this.boxH - this.paddingBottomValue, this.isRtl);
  }

  @Builder
  emptyItem(index: number): void {
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      ForEach(this.specs, (spec: ChildLayoutSpec, index: number) => {
        if (spec.visible) {
          Column() {
            this.item(index)
          }
          .position({
            // 上游 parentRight = (right-left) - paddingRight；parentBottom = (bottom-top) - paddingBottom。
            // 修前把 **padding 数值本身**当成了父边界 ⇒ CENTER_HORIZONTAL / RIGHT / BOTTOM 三支算到屏幕外。
            x: this.boxAt(index).left,
            y: this.boxAt(index).top
          })
        }
      }, (spec: ChildLayoutSpec, index: number) => `${index}`)
    }
    .width('100%')
    .height('100%')
    .onAreaChange((oldValue: Area, newValue: Area) => {
      this.boxW = newValue.width as number;
      this.boxH = newValue.height as number;
    })
  }
}
