/*
 * 上游：app/src/main/res/layout/item_simple_list.xml（inventory S0632，上游 26 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/item_simple_list.ets
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                       ArkUI
 * TextView#android.R.id.text1                   Text
 *   layout_width=match_parent                     .width('100%')
 *   layout_height=wrap_content                    .height('auto')（默认）
 *   textAppearance=?attr/textAppearanceListItemSmall  .fontSize(14)（取值依据见「无法等价」1）
 *   gravity=center_vertical                       .alignItems 由 Column 垂直居中（见 2）
 *   paddingLeft/Right=?attr/listPreferredItemPadding{Left,Right}  .padding({left:16,right:16})
 *   minHeight=?attr/listPreferredItemHeightSmall   .constraintSize({minHeight:48})
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `?attr/textAppearanceListItemSmall` 是运行期主题属性（Material 默认 14sp），
 *    HarmonyOS 无 attr 解析 → 取 Material 默认值 14fp，并由 @Prop fontSize 允许主题层覆盖。
 * 2. 单个 TextView 的 `gravity="center_vertical"` 在 ArkUI 里要由父容器承担：
 *    这里用 `Row().alignItems(VerticalAlign.Center)` 包一层，语义等价（文本在 48vp 行内垂直居中）。
 * 3. `?attr/listPreferredItemPaddingLeft/Right`（Material 默认 16dp）与
 *    `?attr/listPreferredItemHeightSmall`（Material 默认 48dp）同样无 attr，
 *    默认值写死为 16vp / 48vp，保留 @Prop 供主题层注入。
 * 4. ellipsize 未设置（上游此布局不截断）→ 不设 maxLines，长文本按上游换行。
 */

@Component
export struct SimpleListItemLayout {
  // ---- 数据（对应 XML 中的 R.id / android.R.id） ----
  @Prop text: string = '';

  // ---- 主题注入位（上游为 ?attr 运行期解析，鸿蒙侧由主题层赋值） ----
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
        .width('100%')
    }
    .width('100%')
    .constraintSize({ minHeight: this.minHeight })
    .padding({ left: this.paddingLeft, right: this.paddingRight })
    .alignItems(VerticalAlign.Center)
  }
}
