/*
 * 上游：app/src/main/res/layout/dialog_donate.xml（inventory S0572，上游 123 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/dialog_donate.ets
 *
 * 背景：捐赠对话框（支付宝 / 微信二维码 + 保存图片/复制按钮 + 引导文案）。
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                   ArkUI
 * LinearLayout(vertical)                     Column
 *   padding=@dimen/keyline_margin(16dp)       .padding($r('app.float.keyline_margin'))
 * TextView（donate_message）                Text：$r('app.string.settings_about_donate_message')
 * Space（高 keyline_margin=16dp）            Row().height(16)（见 1）
 * RelativeLayout#RelativeLayout1            Stack（见 2）
 *   ImageView#image_aliPay                  @BuilderParam alipayQrBuilder（见 3）
 *     layout_toStartOf=image_center           左半区
 *     height=@dimen/gallery_page_min_height    .height(gallery_page_min_height)
 *     background=@drawable/zhifubao            图片资源由槽位提供
 *   View#image_center（1dp 竖线，居中）       Divider().vertical(true)（见 4）
 *     layout_centerInParent / marginTop=5 / marginBottom=10
 *     background=?attr/dividerColor
 *   ImageView#image_weChat                   @BuilderParam wechatQrBuilder
 *     layout_toEndOf=image_center             右半区
 * TextView（settings_about_donate_alipay）   Text：text_little_small(16fp) + bold + 居中
 *   textColor=?attr/textColorThemePrimary      .fontColor(textColorThemePrimary)
 * TextView#alipay_text（居中）               Text（支付宝账号文本）
 * TableLayout > TableRow(gravity=center)     Row（三按钮，权重 2:1:2，见 5）
 *   Button#save_image_aliPay（weight 2, 蓝）   Button：text_small + $r('app.color.blue_FA')
 *   Button#alipay_copy（weight 1）             Button：text_small
 *   Button#save_image_weChat（weight 2, 绿）   Button：text_small + $r('app.color.deep_green_600')
 * Space（16dp）                              Row().height(16)
 * TextView（settings_about_donate_guide）    Text：16fp + bold + 居中 + textColorThemePrimary2
 * TextView#guide_text（居中）                Text（引导文本）
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `Space`（无内容、固定高度）→ ArkUI 用 `Row().height(N)` 占位（不能用 margin 代替：
 *    Space 是**参与布局的实体**，间距会被 Column 的 alignItems 影响，margin 不会）。
 * 2. RelativeLayout 的三子元素关系是"左图 | 中竖线 | 右图"，且中竖线
 *    `layout_centerInParent` —— 用 `Stack` + `Alignment.Center` 放竖线，左右两张图用
 *    Row 的两半区（layoutWeight 1:1）承载。这样竖线始终在正中，与上游一致。
 * 3. 两张二维码是 `@drawable/zhifubao` / `@drawable/weixin`（上游把图片当 **background** 用，
 *    不是 src）：ArkUI 侧用 @BuilderParam 槽位由使用方注入图片组件（Image($r(...)) 或
 *    已迁 drawable），本布局只保证尺寸（高 = gallery_page_min_height）与左右分区。
 * 4. `View` 1dp 竖线 → ArkUI `Divider().vertical(true)`，颜色 @Prop 注入（?attr/dividerColor）。
 * 5. `TableRow` + 三按钮 weight 2:1:2 → `Row` 里三个 Button 各 `.layoutWeight(2/1/2)`；
 *    `Widget.AppCompat.Button.Borderless.Colored`（无边框彩色文字按钮）→ ArkUI `Button` 默认
 *    带背景，故显式 `.backgroundColor(Color.Transparent)` + `.type(ButtonType.Normal)`，
 *    文字颜色分别为 `$r('app.color.blue_FA')` / 默认 / `$r('app.color.deep_green_600')`。
 * 6. 三个按钮的 `padding=0dp`（save 两个）与 textSize=text_small(14fp) 按原值；
 *    `?attr/textColorThemePrimary(2)` 无 ArkUI attr → @Prop 注入。
 */

@Component
export struct DonateDialogLayout {
  @Prop alipayText: string = '';
  @Prop guideText: string = '';
  @Prop messageColor: ResourceColor = '#DE000000';
  @Prop primaryThemeColor: ResourceColor = '#FF6200EE';
  @Prop secondaryThemeColor: ResourceColor = '#FF03A9F4';
  @Prop dividerColor: ResourceColor = '#1F000000';

  /** 支付宝二维码（上游 @drawable/zhifubao 作为 background） */
  @BuilderParam alipayQrBuilder: () => void = this.emptyQr;
  /** 微信二维码（上游 @drawable/weixin 作为 background） */
  @BuilderParam wechatQrBuilder: () => void = this.emptyQr;

  onSaveAlipay: () => void = () => {
    // 默认空实现：使用方注入
  };
  onCopyAlipay: () => void = () => {
    // 默认空实现：使用方注入
  };
  onSaveWechat: () => void = () => {
    // 默认空实现：使用方注入
  };

  @Builder
  emptyQr() {
    Column()
      .height($r('app.float.gallery_page_min_height'))
      .backgroundColor('#11000000')
  }

  build() {
    Column() {
      Text($r('app.string.settings_about_donate_message'))
        .fontColor(this.messageColor)
        .width('100%')

      // Space（参与布局的实体占位）
      Row().height($r('app.float.keyline_margin'))

      // 二维码区：左图 | 中竖线 | 右图
      Stack() {
        Row() {
          Column() {
            this.alipayQrBuilder();
          }
          .layoutWeight(1)
          .height($r('app.float.gallery_page_min_height'))

          Column() {
            this.wechatQrBuilder();
          }
          .layoutWeight(1)
          .height($r('app.float.gallery_page_min_height'))
        }
        .width('100%')

        Divider()
          .vertical(true)
          .strokeWidth(1)
          .color(this.dividerColor)
          .height($r('app.float.gallery_page_min_height'))
          .margin({ top: 5, bottom: 10 })
          .align(Alignment.Center)
      }
      .width('100%')

      Text($r('app.string.settings_about_donate_alipay'))
        .fontSize($r('app.float.text_little_small'))
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryThemeColor)
        .textAlign(TextAlign.Center)
        .width('100%')

      Text(this.alipayText)
        .textAlign(TextAlign.Center)
        .fontColor(this.messageColor)
        .width('100%')

      // 三按钮（weight 2:1:2，无边框彩色文字按钮）
      Row() {
        Button($r('app.string.settings_save_image_aliPay'))
          .type(ButtonType.Normal)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.blue_FA'))
          .fontSize($r('app.float.text_small'))
          .padding(0)
          .layoutWeight(2)
          .onClick(() => {
            this.onSaveAlipay();
          })

        Button($r('app.string.settings_about_donate_copy'))
          .type(ButtonType.Normal)
          .backgroundColor(Color.Transparent)
          .fontSize($r('app.float.text_small'))
          .layoutWeight(1)
          .onClick(() => {
            this.onCopyAlipay();
          })

        Button($r('app.string.settings_save_image_weChat'))
          .type(ButtonType.Normal)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.deep_green_600'))
          .fontSize($r('app.float.text_small'))
          .padding(0)
          .layoutWeight(2)
          .onClick(() => {
            this.onSaveWechat();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)

      // Space（第二个）
      Row().height($r('app.float.keyline_margin'))

      Text($r('app.string.settings_about_donate_guide'))
        .fontSize($r('app.float.text_little_small'))
        .fontWeight(FontWeight.Bold)
        .fontColor(this.secondaryThemeColor)
        .textAlign(TextAlign.Center)
        .width('100%')

      Text(this.guideText)
        .textAlign(TextAlign.Center)
        .fontColor(this.messageColor)
        .width('100%')
    }
    .width('100%')
    .padding($r('app.float.keyline_margin'))
    .alignItems(HorizontalAlign.Start)
  }
}
