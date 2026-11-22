/*
 * 上游：app/src/main/res/layout/item_blacklist_header.xml（inventory S0601，上游 25 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/item_blacklist_header.ets
 * 上游：app/src/main/res/layout/item_filter_header.xml（inventory S0611，同构，见文末）
 *
 * ── 结构对照（两份 XML 除文件名外完全一致：TextView + Title 样式 + 8dp padding） ──────
 * Android                                           ArkUI
 * TextView#text                                      Text
 *   textAppearance=@style/TextAppearance.AppCompat.Title   .fontSize(20)（见「无法等价」1）
 *   textColor=?android:attr/textColorPrimary                .fontColor(textColorPrimary)
 *   padding=8dp                                             .padding(8)
 *   layout_width=match_parent                               .width('100%')
 *   android:orientation（对 TextView 无意义，上游遗留属性）   忽略，见 2
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `TextAppearance.AppCompat.Title` = **20sp**（AppCompat 定义），
 *    已迁的 float 资源里只有 text_medium(18fp)/text_small(14fp)，没有 20fp 档 →
 *    本组件用 @Prop fontSize 默认 20，不硬编码到布局深处，便于后续统一收口。
 * 2. 上游 `android:orientation="vertical"` 写在 TextView 上（拷贝遗留，无效果），
 *    ArkUI 侧不实现该属性。
 * 3. `?android:attr/textColorPrimary` 无 attr 解析 → @Prop 注入，默认 `#DE000000`。
 * 4. item_filter_header.xml 与本文件**逐属性相同**（上游复制而来），
 *    故此处只落一份实现，`item_filter_header.ets` 复用本组件（见文件末导出别名）。
 */

@Component
export struct BlacklistHeaderItemLayout {
  @Prop text: string = '';
  @Prop fontSize: number = 20;
  @Prop textColor: ResourceColor = '#DE000000';

  build() {
    Text(this.text)
      .fontSize(this.fontSize)
      .fontColor(this.textColor)
      .width('100%')
      .textAlign(TextAlign.Start)
      .padding(8)
  }
}
