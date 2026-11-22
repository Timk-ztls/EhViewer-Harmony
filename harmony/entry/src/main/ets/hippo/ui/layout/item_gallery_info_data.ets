/*
 * 上游：app/src/main/res/layout/item_gallery_info_data.xml（inventory S0618，上游 36 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/item_gallery_info_data.ets
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                     ArkUI
 * LinearLayout(horizontal)                     Row
 *   paddingLeft/Right=@dimen/keyline_margin(16dp)  .padding({left:16,right:16})
 * TextView#key                                 Text
 *   layout_width=90dp                            .width(90)
 *   padding=8dp                                  .padding(8)
 *   textColor=?android:attr/textColorPrimary      .fontColor(textColorPrimary)
 * TextView#value                                Text
 *   layout_width=wrap_content                    内容撑开
 *   padding=8dp                                  .padding(8)
 *   textColor=?android:attr/textColorPrimary      .fontColor(textColorPrimary)
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `@dimen/keyline_margin`(16dp) 已迁为 `app.float.keyline_margin`，用 `$r` 引用。
 * 2. key 固定 90dp 是**标签列宽**（值列不设权重，靠 key 对齐）；因此 Two Text 都按
 *    上游原值：key 90vp 固定、value 由内容撑开且可换行（不设 maxLines）。
 * 3. 行高由两个 TextView 的 8dp padding + 行高决定，不设 minHeight（上游也未设）。
 * 4. `?android:attr/textColorPrimary` 无 attr → @Prop 注入，默认 '#DE000000'。
 * 5. 该布局是 GalleryInfo 表格的一行，多行之间的分割线/间距由父容器（RecyclerView
 *    的 item decoration）承担，布局自身不含 divider（与上游一致）。
 */

@Component
export struct GalleryInfoDataItemLayout {
  @Prop keyText: string = '';
  @Prop valueText: string = '';
  @Prop textColor: ResourceColor = '#DE000000';

  build() {
    Row() {
      Text(this.keyText)
        .fontColor(this.textColor)
        .width(90)
        .padding(8)

      Text(this.valueText)
        .fontColor(this.textColor)
        .padding(8)
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: $r('app.float.keyline_margin'), right: $r('app.float.keyline_margin') })
    .alignItems(VerticalAlign.Top)
  }
}
