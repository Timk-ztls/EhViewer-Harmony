/*
 * 上游：app/src/main/res/layout/widget_gallery_guide_2.xml（inventory S0679，上游 25 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/widget_gallery_guide_2.ets
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                 ArkUI
 * <merge>                                 见「无法等价」1（落单子 Stack 容器）
 * TextView（match_parent × match_parent）  Text
 *   gravity=center                          .textAlign(TextAlign.Center) + 容器对齐 Center
 *   text=@string/guide_gallery_long_click   $r('app.string.guide_gallery_long_click')
 *   style=Guide.Title                       .fontSize(20) + .fontColor(guideTitleColor)
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `<merge>` + 单个 `match_parent × match_parent` 的 TextView：语义是"铺满宿主"。
 *    ArkUI 落成 `Stack` + 全尺寸 Text + `.align(Alignment.Center)`，等价于铺满并居中。
 * 2. `@style/Guide.Title` = AppCompat.Title(20sp) + `?attr/guideTitleColor` → @Prop 注入。
 * 3. 该引导只有一句长按提示（无逐条动画），淡入淡出由使用方控制。
 */

@Component
export struct GalleryGuide2WidgetLayout {
  @Prop guideTitleColor: ResourceColor = '#DE000000';
  @Prop fontSize: number = 20;

  build() {
    Stack() {
      Text($r('app.string.guide_gallery_long_click'))
        .fontSize(this.fontSize)
        .fontColor(this.guideTitleColor)
        .width('100%')
        .height('100%')
        .textAlign(TextAlign.Center)
        .align(Alignment.Center)
    }
    .width('100%')
    .height('100%')
  }
}
