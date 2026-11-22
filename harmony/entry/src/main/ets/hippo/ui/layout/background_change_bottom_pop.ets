/*
 * 上游：app/src/main/res/layout/background_change_bottom_pop.xml（inventory S0564，上游 34 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/background_change_bottom_pop.ets
 *
 * 背景：换背景时从底部弹出的两个选项（拍照 / 从相册选择）。
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                ArkUI
 * RelativeLayout(wrap)                    Stack（单子元素，见 1）
 * LinearLayout(vertical)                  Column
 * TextView#take_photo_with_camera         Text：$r('app.string.take_a_photograph')
 *   match 宽                                .width('100%')
 *   marginLeft/Right/Bottom=@dimen/popup_text_margin(12dp)  .margin({l:12,r:12,b:12})
 *   background=@drawable/bottom_popup_shape 圆角矩形（radius=popup_text_padding=4 + 主题色，见 2）
 *   gravity=center                          .textAlign(TextAlign.Center)
 *   padding=@dimen/popup_text_padding(4dp)  .padding(4)
 *   textSize=@dimen/text_super_large(24fp)  .fontSize($r('app.float.text_super_large'))
 * TextView#choose_from_the_album          Text：$r('app.string.choose_from_the_album')（同上）
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. 上游 RelativeLayout 里只有**一个** LinearLayout 子元素（RelativeLayout 在这里没有承担任何
 *    相对定位职责）→ ArkUI 用 Stack 承载，等价且不丢语义（写成 Column 也可以，
 *    但 Stack 更贴近"容器只做包裹"的原意）。
 * 2. `@drawable/bottom_popup_shape` 是 shape drawable：`corners radius=@dimen/popup_text_padding(4dp)`
 *    + `solid color=?attr/popupWindowStyle` → ArkUI 用 `.borderRadius(4)` + `.backgroundColor(圆角底色)`；
 *    主题色 `?attr/popupWindowStyle` 无 ArkUI attr → @Prop popupColor 注入。
 *    **注意**：`popupWindowStyle` 在这里当**填充色**用（上游这么写），不是窗口背景。
 * 3. 两个 TextView 都是"整行可点"的选项：点击回调分开暴露（拍照 / 相册）。
 * 4. 底部弹出动画（`bottom_popup` 的滑入）不在布局层：由使用方的 popup/半模态承载。
 */

@Component
export struct BackgroundChangeBottomPopLayout {
  @Prop textColor: ResourceColor = '#DE000000';
  /** 上游 @drawable/bottom_popup_shape 的 solid color（?attr/popupWindowStyle） */
  @Prop popupColor: ResourceColor = '#FFFFFFFF';
  /** 上游 @drawable/bottom_popup_shape 的 corners radius（=@dimen/popup_text_padding） */
  @Prop cornerRadius: number = 4;

  onTakePhoto: () => void = () => {
    // 默认空实现：使用方注入
  };
  onChooseFromAlbum: () => void = () => {
    // 默认空实现：使用方注入
  };

  build() {
    Stack() {
      Column() {
        Text($r('app.string.take_a_photograph'))
          .fontSize($r('app.float.text_super_large'))
          .fontColor(this.textColor)
          .textAlign(TextAlign.Center)
          .width('100%')
          .padding($r('app.float.popup_text_padding'))
          .margin({
            left: $r('app.float.popup_text_margin'),
            right: $r('app.float.popup_text_margin'),
            bottom: $r('app.float.popup_text_margin')
          })
          .backgroundColor(this.popupColor)
          .borderRadius(this.cornerRadius)
          .onClick(() => {
            this.onTakePhoto();
          })

        Text($r('app.string.choose_from_the_album'))
          .fontSize($r('app.float.text_super_large'))
          .fontColor(this.textColor)
          .textAlign(TextAlign.Center)
          .width('100%')
          .padding($r('app.float.popup_text_padding'))
          .margin({
            left: $r('app.float.popup_text_margin'),
            right: $r('app.float.popup_text_margin'),
            bottom: $r('app.float.popup_text_margin')
          })
          .backgroundColor(this.popupColor)
          .borderRadius(this.cornerRadius)
          .onClick(() => {
            this.onChooseFromAlbum();
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
  }
}
