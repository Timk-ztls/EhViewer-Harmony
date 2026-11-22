/**
 * 迁移自 app/src/main/java/com/hippo/ehviewer/widget/EhStageLayout.java（inventory S0292，上游 46 行）
 *
 * 上游：`StageLayout`（自定义舞台布局，负责"页面层 + 抽屉层"的堆叠）的子类，实现 DrawerLayoutChild：
 *   onGetWindowPadding(top,bottom) 记录
 *   getAdditionalTopMargin()    = mWindowPaddingTop     ← 注意与 EhNavigationView **不同**（这里顶部要留白）
 *   getAdditionalBottomMargin() = mWindowPaddingBottom
 *
 * 为什么顶部行为不同：舞台布局的内容（列表/阅读器）直接从窗口顶部开始，必须让出状态栏高度；
 * 而 EhNavigationView 用 SCRIM 遮罩盖住状态栏区域，不再额外留白。
 *
 * ArkUI 对位：`StageLayout` 是外部库 `com.hippo.easyrecyclerview`/`StageLayout`（不在 app 源码树，
 *   与 FastScroller 同一批不移植，见 D-022）→ 本文件只保留**契约部分**（DrawerLayoutChild + 两个 margin），
 *   渲染由 ui-scene 用 `Stack` 组装页面层与抽屉层后，按 controller 的两个 margin 加 `.padding(...)`。
 *
 * 差异（已登记 MR）：上游继承 StageLayout 的具体布局算法（页面滑入/抽屉遮罩）未移植；
 *   本控件只保证"窗口内边距 → 外边距"的数值交换契约 1:1，布局表现由 ui-scene 的 Stack 组合决定。
 */
import { DrawerLayoutChild } from './DrawerLayoutChild';

export class EhStageLayoutController implements DrawerLayoutChild {
  windowPaddingTop: number = 0;
  windowPaddingBottom: number = 0;

  onGetWindowPadding(top: number, bottom: number): void {
    this.windowPaddingTop = top;
    this.windowPaddingBottom = bottom;
  }

  /** 与 EhNavigationView 的差别：顶部返回 paddingTop（内容从窗口顶部开始，需要留白） */
  getAdditionalTopMargin(): number {
    return this.windowPaddingTop;
  }

  getAdditionalBottomMargin(): number {
    return this.windowPaddingBottom;
  }
}

@Component
export struct EhStageLayout {
  controller: EhStageLayoutController = new EhStageLayoutController();
  @BuilderParam content: () => void = this.empty;

  @Builder
  empty(): void {
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .height('100%')
    .padding({
      top: this.controller.getAdditionalTopMargin(),
      bottom: this.controller.getAdditionalBottomMargin()
    })
  }
}
