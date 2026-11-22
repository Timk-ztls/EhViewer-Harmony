/*
 * 上游：app/src/main/res/layout/item_download_label_list.xml（inventory S0606，上游 25 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/item_download_label_list.ets
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                          ArkUI
 * LinearLayout(horizontal)                          Row
 * TextView#text1  wrap_content                      Text（左）
 *   textAppearance=?attr/textAppearanceListItemSmall .fontSize(14)
 *   gravity=center_vertical                          Row.alignItems(Center)
 *   paddingStart/End=?attr/listPreferredItemPadding*  .padding({left:16,right:16})
 *   minHeight=?attr/listPreferredItemHeightSmall     .constraintSize({minHeight:48})
 * TextView#text2  match_parent                      Text（右）
 *   gravity=center_vertical|end                      .textAlign(TextAlign.End)
 *   （其余同上）
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `?attr/textAppearanceListItemSmall`(14sp) / `listPreferredItemPaddingLeft|Right`(16dp) /
 *    `listPreferredItemHeightSmall`(48dp) 都是运行期主题属性 → 取 Material 默认值并做成 @Prop。
 * 2. 上游 text2 是 `match_parent`：在 Row 里等价于".layoutWeight(1) 撑满剩余宽度"，
 *    若照搬 '100%' 会把 text1 挤成 0 宽（这是从 LinearLayout 迁到 Row 最常见的错位）。
 * 3. 两个 TextView 的高度都靠 minHeight=48dp 撑起（不是写死高度），故用 constraintSize。
 * 4. 上游 text2 未设 textColor → 同 text1（主题 textColorPrimary）。
 */

@Component
export struct DownloadLabelListItemLayout {
  @Prop text1: string = '';
  @Prop text2: string = '';

  // 主题注入位（上游 ?attr）
  @Prop fontSize: number = 14;
  @Prop textColor: ResourceColor = '#DE000000';
  @Prop paddingLeft: number = 16;
  @Prop paddingRight: number = 16;
  @Prop minHeight: number = 48;

  build() {
    Row() {
      Text(this.text1)
        .fontSize(this.fontSize)
        .fontColor(this.textColor)
        .constraintSize({ minHeight: this.minHeight })
        .padding({ left: this.paddingLeft, right: this.paddingRight })

      Text(this.text2)
        .fontSize(this.fontSize)
        .fontColor(this.textColor)
        .textAlign(TextAlign.End)
        .constraintSize({ minHeight: this.minHeight })
        .padding({ left: this.paddingLeft, right: this.paddingRight })
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}
