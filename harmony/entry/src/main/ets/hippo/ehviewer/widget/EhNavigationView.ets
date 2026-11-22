/**
 * 迁移自 app/src/main/java/com/hippo/ehviewer/widget/EhNavigationView.java（inventory S0291，上游 45 行）
 *
 * 上游：
 *   LinearLayout + 实现 DrawerLayoutChild
 *   SCRIM_COLOR = 0x44000000；DRAW_SCRIM = SDK >= 21
 *   draw()：super.draw() 之后，若 mWindowPaddingTop > 0，用 SCRIM_COLOR 填 (0,0,w,mWindowPaddingTop)
 *           —— 在状态栏区域盖一层 26% 黑，避免抽屉内容延伸到状态栏时出现亮色断层
 *   onGetWindowPadding(top,bottom) 记录；getAdditionalTopMargin()=0；getAdditionalBottomMargin()=paddingBottom
 *
 * ArkUI 对位：
 *   宿主 → `Column`（LinearLayout 垂直的等价物）
 *   状态栏遮罩 → `.overlay(this.scrimBuilder(), { align: Alignment.TopStart })`，
 *                高度 = windowPaddingTop，颜色 = SCRIM_COLOR
 *   DrawerLayoutChild 三个方法 → 保留在 `EhNavigationController`（组件无法 implements 接口），
 *                由 EhDrawerLayout 在布局时调用 controller.onGetWindowPadding(...) 并读取两个 margin
 *
 * 差异：上游 getAdditionalTopMargin 恒 0（顶部由遮罩处理），本实现一致；若 ui-scene 需要顶部也留白，
 *      走 controller.setAdditionalTopMargin(...)（默认 0，不改变上游行为）。
 */
import { DrawerLayoutChild } from './DrawerLayoutChild';

/** 抽屉子视图的状态（实现 DrawerLayoutChild） */
export class EhNavigationController implements DrawerLayoutChild {
  static readonly SCRIM_COLOR: string = '#44000000';
  windowPaddingTop: number = 0;
  windowPaddingBottom: number = 0;
  /** 上游恒为 0；保留可写入口但不改变默认行为 */
  additionalTopMargin: number = 0;

  onGetWindowPadding(top: number, bottom: number): void {
    this.windowPaddingTop = top;
    this.windowPaddingBottom = bottom;
  }

  getAdditionalTopMargin(): number {
    return this.additionalTopMargin;
  }

  getAdditionalBottomMargin(): number {
    return this.windowPaddingBottom;
  }
}

@Component
export struct EhNavigationView {
  controller: EhNavigationController = new EhNavigationController();
  @BuilderParam content: () => void = this.empty;

  @Builder
  empty(): void {
  }

  @Builder
  scrim(): void {
    Column()
      .width('100%')
      .height(this.controller.windowPaddingTop)
      .backgroundColor(EhNavigationController.SCRIM_COLOR)
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .height('100%')
    .overlay(this.scrim(), { align: Alignment.TopStart })
  }
}
