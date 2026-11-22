/*
 * 上游：app/src/main/res/layout/item_select_dialog.xml（inventory S0629，上游 28 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/item_select_dialog.ets
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                          ArkUI
 * TextView#android.R.id.text1                      Text
 *   layout_width=match_parent                        .width('100%')
 *   minHeight=?attr/listPreferredItemHeightSmall     .constraintSize({minHeight:48})
 *   textAppearance=?attr/textAppearanceListItemSmall .fontSize(14)
 *   textColor=?attr/textColorAlertDialogListItem     .fontColor(textColorPrimary)（见「无法等价」2）
 *   gravity=center_vertical                          Row.alignItems(CENTER)
 *   paddingLeft/Right=?attr/listPreferredItemPadding .padding({left:16,right:16})
 *   ellipsize=marquee                                .textOverflow({overflow: MARQUEE})（见 3）
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `?attr/textAppearanceListItemSmall` / `listPreferredItemHeightSmall` /
 *    `listPreferredItemPaddingLeft|Right` 是运行期主题属性，ArkUI 无 attr 解析，
 *    取 Material 默认值（14fp / 48vp / 16vp），保留 @Prop 供主题层注入。
 * 2. `?attr/textColorAlertDialogListItem` 在 Material 主题下等同 `textColorPrimary`；
 *    这里默认 `#DE000000` 并在注释登记依据（DEVIATIONS 汇总项由 Lead 收口）。
 * 3. `ellipsize="marquee"`：ArkUI `TextOverflow.MARQUEE` 需要文本超宽才滚动，
 *    上游 marquee 还需 `focusable/selected` 触发；鸿蒙侧无同名触发条件，
 *    统一用 MARQUEE 溢出策略 + 单行，滚动时机由父级焦点决定（差异登记）。
 */

@Component
export struct SelectDialogItemLayout {
  @Prop text: string = '';

  // 主题注入位（上游 ?attr）
  @Prop fontSize: number = 14;
  @Prop textColor: ResourceColor = '#DE000000';
  @Prop paddingLeft: number = 16;
  @Prop paddingRight: number = 16;
  @Prop minHeight: number = 48;

  build() {
    Row() {
      Text(this.text)
        .fontSize(this.fontSize)
        .fontColor(this.textColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.MARQUEE })
        .width('100%')
    }
    .width('100%')
    .constraintSize({ minHeight: this.minHeight })
    .padding({ left: this.paddingLeft, right: this.paddingRight })
    .alignItems(VerticalAlign.Center)
  }
}
