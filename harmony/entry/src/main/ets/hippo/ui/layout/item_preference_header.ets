/*
 * 上游：app/src/main/res/layout/item_preference_header.xml（inventory S0627，上游 62 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/item_preference_header.ets
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                          ArkUI
 * LinearLayout(horizontal, minHeight=72dp,        Row（minHeight 72、垂直居中）
 *   gravity=center_vertical,                        .constraintSize({minHeight:72})
 *   background=?attr/preferenceHeaderBackground)    .backgroundColor(headerBackground)（注入位）
 * ImageView#android.R.id.icon（24x24,             @BuilderParam iconBuilder（默认 24x24 占位）
 *   scaleType=centerInside, marginLeft=16,          + .margin({left:16,right:32})
 *   marginRight=32）
 * LinearLayout(vertical, match_parent/match_parent) Column().layoutWeight(1).height('100%')
 *   FrameLayout(weight=1)                            Stack().layoutWeight(1)
 *     TextView#android.R.id.title                      Text（AppCompat.Medium=18fp，
 *       center_vertical / singleLine / marquee /          .align(Alignment.Start) + 垂直居中，
 *       textColorPrimary）                                 maxLines 1 + MARQUEE，textColorPrimary）
 *     TextView#android.R.id.summary                    Text（默认样式，叠在同一 Stack 内，见 3）
 *   View#tile_divider（1dp, dividerVertical）          Divider().strokeWidth(1)
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `?attr/preferenceHeaderBackground` 是 AndroidX preference 的主题属性（浅色下为
 *    colorBackground、深色下略亮一档），无 ArkUI attr → @Prop headerBackground 注入，
 *    默认 '#F5F5F5'（Material 浅色背景），由主题层覆盖。
 * 2. `scaleType="centerInside"` → ArkUI `objectFit(ImageFit.CONTAIN)`（等比缩放并居中，
 *    不裁剪、不放大）；图标资源由 ui-widget/使用方注入（@BuilderParam），
 *    未注入时占位 24x24 以保持左右间距与行高稳定。
 * 3. 上游 title 与 summary 同在**一个 FrameLayout** 里（叠放）：title 垂直居中、
 *    summary 按默认 gravity（左上）叠在同一区域，通常由 Preference 框架控制其显示。
 *    ArkUI 用 Stack 保持"叠放"语义（不是 Column 上下排），否则 summary 出现时会把
 *    title 顶开，与上游不一致 —— 这是本文件唯一需要作者留意的地方。
 * 4. `fadingEdge="horizontal"`（API 14 起 marquee 用）ArkUI 无对位：
 *    marquee 滚动的渐隐边缘由系统实现，不单独暴露（差异登记）。
 * 5. minHeight 72dp = AndroidX preference header 的固定值，写死为 72vp（上游即硬编码）。
 */

@Component
export struct PreferenceHeaderItemLayout {
  @Prop title: string = '';
  @Prop summary: string = '';

  // 主题注入位（上游 ?attr）
  @Prop headerBackground: ResourceColor = '#FFF5F5F5';
  @Prop titleColor: ResourceColor = '#DE000000';
  @Prop summaryColor: ResourceColor = '#8A000000';
  @Prop dividerColor: ResourceColor = '#1F000000';

  /** 左侧图标（上游 android.R.id.icon，由 Preference 框架注入 drawable） */
  @BuilderParam iconBuilder: () => void = this.emptyIcon;

  @Builder
  emptyIcon() {
    Column().width(24).height(24)
  }

  build() {
    Row() {
      Column() {
        this.iconBuilder();
      }
      .width(24)
      .height(24)
      .margin({ left: 16, right: 32 })
      .justifyContent(FlexAlign.Center)

      Column() {
        Stack() {
          // summary 在上层判定顺序里先画，保证 title 覆盖其上（与上游 FrameLayout 子序一致）
          Text(this.summary)
            .fontSize($r('app.float.text_small'))
            .fontColor(this.summaryColor)
            .width('100%')
            .textAlign(TextAlign.Start)
            .align(Alignment.TopStart)

          Text(this.title)
            .fontSize($r('app.float.text_medium'))
            .fontColor(this.titleColor)
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.MARQUEE })
            .align(Alignment.Start)
        }
        .width('100%')
        .layoutWeight(1)

        Divider()
          .strokeWidth(1)
          .color(this.dividerColor)
          .width('100%')
      }
      .width('100%')
      .height('100%')
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .constraintSize({ minHeight: 72 })
    .backgroundColor(this.headerBackground)
    .alignItems(VerticalAlign.Center)
  }
}
