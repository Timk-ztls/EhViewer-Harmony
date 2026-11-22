/**
 * 迁移自 app/src/main/java/com/hippo/widget/SafeCoordinatorLayout.java（inventory S0540，上游 50 行）
 *
 * 上游全部逻辑只有两处 try/catch：
 *   onInterceptTouchEvent / onTouchEvent → super(...)，捕获 Throwable 后 throwIfFatal 再返回 false
 * 背景（上游注释未写，但从 import 与用法可确定）：这是给 Material `CoordinatorLayout` 的**触摸崩溃兜底**——
 *   某些机型/嵌套滚动组合下 Behavior 的触摸拦截会抛异常，用 try/catch 换"吞掉事件"避免崩溃。
 *
 * ArkUI 对位：
 *   1) ArkUI 没有 `CoordinatorLayout`（无 Behavior 体系），容器等价物是 `Stack`；
 *      触摸事件由框架派发，没有"拦截链"可抛异常，因此**没有需要兜底的位置**——
 *      这是"平台缺陷路径不存在"，不是"漏实现"。
 *   2) 为保持调用点 1:1，保留同名组件 + `@BuilderParam content`，行为 = 纯容器。
 *   3) 若 ui-scene 未来在容器上做手势联动（等价 Behavior），联动逻辑应放在独立的状态机类里，
 *      而不是塞回本容器（见 FabLayout 的 ScrollOffsetHost 模式）。
 *
 * 差异（已登记 MR）：上游的 try/catch 兜底在 ArkUI 无对位；组件本身等价于 `Stack`。
 */
@Component
export struct SafeCoordinatorLayout {
  @BuilderParam content: () => void = this.empty;
  /** 对齐方式（对位 CoordinatorLayout 的 layout_gravity 常用形态） */
  @Prop alignContent: Alignment = Alignment.TopStart;

  @Builder
  empty(): void {
  }

  build() {
    Stack({ alignContent: this.alignContent }) {
      this.content()
    }
    .width('100%')
    .height('100%')
  }
}
