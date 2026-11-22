/**
 * 重绘自 app/src/main/res/drawable/spacer_keyline.xml  （inventory S0771，上游 25 行）
 * 上游节点：<shape android:shape="rectangle">
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: base）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 *   <solid color="@android:color/transparent"> → .backgroundColor('#00000000')
 *   <size width="@dimen/keyline_margin" height="@dimen/keyline_margin"> → .width(16).height(16)
 */


@Component
export struct SpacerKeyline {
  @Prop boxWidth: Length = 16;
  @Prop boxHeight: Length = 16;
  build() {
    Column() {
    }
    .width(this.boxWidth)
    .height(this.boxHeight)
        .backgroundColor('#00000000')
    .borderRadius(0)
  }
}