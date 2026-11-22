/*
 * 上游：app/src/main/res/layout/item_drawer_favorites.xml（inventory S0609，上游 41 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/item_drawer_favorites.ets
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                          ArkUI
 * LinearLayout(horizontal)                          Row
 *   minHeight=?attr/listPreferredItemHeightSmall(48dp)  .constraintSize({minHeight:48})
 *   background=?android:attr/selectableItemBackground    .stateStyles / 点击态（见 1）
 * TextView#key（0dp, weight=1, match_parent 高）      Text().layoutWeight(1)
 *   textAppearance=?attr/textAppearanceListItemSmall    .fontSize(14)
 *   textColor=?android:attr/textColorPrimary            .fontColor(textColorPrimary)
 *   gravity=center_vertical                            Row.alignItems(Center)
 *   paddingLeft=?attr/listPreferredItemPaddingLeft(16)  .padding({left:16})
 * TextView#value（wrap_content, match_parent 高）      Text
 *   textAppearance / textColor 同上                     .fontSize(14) + textColorPrimary
 *   gravity=center_vertical                            Row.alignItems(Center)
 *   paddingRight=?attr/listPreferredItemPaddingRight    .padding({right:16})
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `?android:attr/selectableItemBackground`（点击涟漪/前景）→ ArkUI 无 attr：
 *    默认用 `.stateStyles({ pressed: {...} })` 近似（按下时 12% 前景），
 *    涟漪扩散动画不可等价（ArkUI 只在部分容器上有默认涟漪）。差异登记。
 * 2. 两个 TextView 都是 `match_parent` 高（不是 wrap_content）：在 Row 里等价于
 *    随行高拉伸，配合 `alignItems(Center)` 得到垂直居中；本实现用 Row 的统一交叉轴对齐，
 *    不额外设 height('100%')（否则会与 minHeight 语义打架）。
 * 3. `?attr/listPreferredItem*` 均为运行期主题属性 → 默认取 Material 值（48dp / 16dp / 14sp），
 *    并暴露 @Prop 供主题层注入。
 */

@Component
export struct DrawerFavoritesItemLayout {
  @Prop keyText: string = '';
  @Prop valueText: string = '';
  @Prop textColor: ResourceColor = '#DE000000';
  @Prop fontSize: number = 14;
  @Prop paddingLeft: number = 16;
  @Prop paddingRight: number = 16;
  @Prop minHeight: number = 48;

  build() {
    Row() {
      Text(this.keyText)
        .id('key')
        .fontSize(this.fontSize)
        .fontColor(this.textColor)
        .padding({ left: this.paddingLeft })
        .layoutWeight(1)

      Text(this.valueText)
        .fontSize(this.fontSize)
        .fontColor(this.textColor)
        .padding({ right: this.paddingRight })
    }
    .width('100%')
    .constraintSize({ minHeight: this.minHeight })
    .alignItems(VerticalAlign.Center)
    .stateStyles({
      pressed: {
        .backgroundColor('#1F000000')
      },
      normal: {
        .backgroundColor(Color.Transparent)
      }
    })
  }
}
