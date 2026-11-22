/*
 * 上游：app/src/main/res/layout/item_dir_explorer.xml（inventory S0605，上游 23 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/item_dir_explorer.ets
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                          ArkUI
 * TextView#text                     Text
 *   layout_width=match_parent         .width('100%')
 *   layout_height=wrap_content        （默认）
 *   gravity=center_vertical           Row.alignItems(VerticalAlign.Center) 承托（见 1）
 *   padding=8dp                       .padding(8)
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. 单个 TextView 的 `gravity` 在 ArkUI 由父容器承担：包一层 Row 做垂直居中，
 *    与上游"文本在行内垂直居中"一致（高度仍由内容撑开，不设固定 minHeight）。
 * 2. 上游未设 textColor/textSize → 沿用主题默认（正文 16fp、textColorPrimary），
 *    ArkUI 侧保留 @Prop 供主题层注入，默认值与系统正文一致。
 */

@Component
export struct DirExplorerItemLayout {
  @Prop text: string = '';
  @Prop fontSize: number = 16;
  @Prop textColor: ResourceColor = '#DE000000';

  build() {
    Row() {
      Text(this.text)
        .fontSize(this.fontSize)
        .fontColor(this.textColor)
        .width('100%')
    }
    .width('100%')
    .padding(8)
    .alignItems(VerticalAlign.Center)
  }
}
