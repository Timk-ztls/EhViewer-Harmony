/*
 * 上游：app/src/main/res/layout/widget_gallery_guide_1.xml（inventory S0678，上游 43 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/widget_gallery_guide_1.ets
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                          ArkUI
 * <merge>（无根容器）               见「无法等价」1
 * TextView × 4（Guide.Title 样式）  Text × 4
 *   layout_width/height=wrap       内容撑开（不写 '100%'）
 *   gravity=center                 .textAlign(TextAlign.Center)
 *   text=@string/guide_gallery_*   $r('app.string.guide_gallery_*')
 *   @style/Guide.Title             .fontSize(20) + .fontColor(guideTitleColor)（见 2）
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `<merge>` 表示"这 4 个 TextView 直接并进宿主布局"（上游在 GuideView 里 addView 到
 *    某个 LinearLayout/FrameLayout）。ArkUI 没有 merge 语义 → 落成一个 **Column 容器**，
 *    由使用方决定放在哪；容器不带 margin/padding/背景，保持"只贡献 4 个子项"的语义。
 *    若使用方本身是竖排引导页，直接嵌套即可（多一层 Column 不影响布局结果，因为不自带间距）。
 * 2. `@style/Guide.Title` = `TextAppearance.AppCompat.Title`(20sp) + `?attr/guideTitleColor`
 *    → 字号 20fp、颜色走 @Prop guideTitleColor（无 ArkUI attr 解析，默认 '#DE000000'）。
 * 3. 4 个引导文案的**出现顺序**与动画（逐条淡入）不在布局层：上游 GuideView 里按索引控制
 *    alpha；本布局只保证顺序与居中，动画由使用方实现。
 * 4. 字符串资源已迁（strings.json 里 4 条 guide_gallery_* 都在），用 `$r` 引用保证多语言。
 */

@Component
export struct GalleryGuide1WidgetLayout {
  @Prop guideTitleColor: ResourceColor = '#DE000000';
  @Prop fontSize: number = 20;

  build() {
    Column() {
      Text($r('app.string.guide_gallery_left'))
        .fontSize(this.fontSize)
        .fontColor(this.guideTitleColor)
        .textAlign(TextAlign.Center)

      Text($r('app.string.guide_gallery_right'))
        .fontSize(this.fontSize)
        .fontColor(this.guideTitleColor)
        .textAlign(TextAlign.Center)

      Text($r('app.string.guide_gallery_menu'))
        .fontSize(this.fontSize)
        .fontColor(this.guideTitleColor)
        .textAlign(TextAlign.Center)

      Text($r('app.string.guide_gallery_progress'))
        .fontSize(this.fontSize)
        .fontColor(this.guideTitleColor)
        .textAlign(TextAlign.Center)
    }
    .alignItems(HorizontalAlign.Center)
  }
}
