/**
 * 迁移自 app/src/main/java/com/hippo/ehviewer/widget/EhDrawerView.java（inventory S0290，上游 45 行）
 *
 * 上游：`DrawerView`（本模块已移植，onMeasure 里用 maxWidth 截断）的子类 + DrawerLayoutChild：
 *   getAdditionalTopMargin()    = mWindowPaddingTop
 *   getAdditionalBottomMargin() = mWindowPaddingBottom
 *
 * ArkUI 对位：复用已移植的 `DrawerView`（maxWidth 截断；DEFAULT_MAX_WIDTH=280）+
 *   `EhDrawerViewController implements DrawerLayoutChild` 提供两个 margin，
 *   渲染时把 margin 作为 padding 施加到抽屉内容上。
 *
 * 差异：无行为差异；上游 `DrawerView` 的 onMeasure 三分支已由 `constraintSize({maxWidth})` 表达（见 DrawerView.ets）。
 */
import { DrawerLayoutChild } from './DrawerLayoutChild';
import { DrawerView } from '../../widget/DrawerView';

export class EhDrawerViewController implements DrawerLayoutChild {
  windowPaddingTop: number = 0;
  windowPaddingBottom: number = 0;

  onGetWindowPadding(top: number, bottom: number): void {
    this.windowPaddingTop = top;
    this.windowPaddingBottom = bottom;
  }

  getAdditionalTopMargin(): number {
    return this.windowPaddingTop;
  }

  getAdditionalBottomMargin(): number {
    return this.windowPaddingBottom;
  }
}

@Component
export struct EhDrawerView {
  controller: EhDrawerViewController = new EhDrawerViewController();
  /** 上游 DEFAULT_MAX_WIDTH = 280dp（透传给 DrawerView） */
  @Prop maxWidth: number = 280;
  @BuilderParam content: () => void = this.empty;

  @Builder
  empty(): void {
  }

  build() {
    DrawerView({ maxWidth: this.maxWidth }) {
      Column() {
        this.content()
      }
      .width('100%')
      .padding({
        top: this.controller.getAdditionalTopMargin(),
        bottom: this.controller.getAdditionalBottomMargin()
      })
    }
  }
}
