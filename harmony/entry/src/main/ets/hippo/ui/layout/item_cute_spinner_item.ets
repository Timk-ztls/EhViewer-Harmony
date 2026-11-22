/*
 * 上游：app/src/main/res/layout/item_cute_spinner_item.xml（inventory S0604，上游 24 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/item_cute_spinner_item.ets
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                            ArkUI
 * TextView#android.R.id.text1                         Text
 *   style=?attr/spinnerDropDownItemStyle               见「无法等价」1（下拉项样式）
 *   android:singleLine=true                            .maxLines(1)
 *   ellipsize=marquee                                   .textOverflow({overflow: MARQUEE})
 *   layout_width=match_parent                           .width('100%')
 *   layout_height=wrap_content                          （默认）
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `?attr/spinnerDropDownItemStyle` 是运行期主题样式（Material 默认为
 *    `Widget.Material.DropDownItem.Spinner`：minHeight 48dp、paddingLeft 16dp、正文 16sp、
 *    textColorPrimary）。ArkUI 无 attr 解析 → 默认值取 Material 对应值并全部做成 @Prop，
 *    由主题层/使用方注入；paddingLeft 引用已迁资源 `app.float.spinner_horizontal_padding`(16vp)。
 * 2. `ellipsize="marquee"`：ArkUI 需 `TextOverflow.MARQUEE` + 单行；
 *    上游 marquee 依赖 selected/focusable 触发滚动，鸿蒙由父级焦点决定（差异登记）。
 * 3. 该布局只描述**下拉项**外观；CuteSpinner 本体由 ui-widget 的
 *    `hippo/widget/CuteSpinner.ets`（已交付）实现，二者职责不重叠。
 */

@Component
export struct CuteSpinnerItemLayout {
  @Prop text: string = '';
  @Prop fontSize: number = 16;
  @Prop textColor: ResourceColor = '#DE000000';
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
    .padding({ left: $r('app.float.spinner_horizontal_padding') })
    .alignItems(VerticalAlign.Center)
  }
}
