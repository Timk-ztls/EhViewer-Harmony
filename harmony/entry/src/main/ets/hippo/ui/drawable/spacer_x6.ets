/**
 * 重绘自 app/src/main/res/drawable/spacer_x6.xml  （inventory S0772，上游 24 行）
 * 上游节点：<shape android:shape="rectangle">
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: base）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 *   <solid color="@android:color/transparent"> → .backgroundColor('#00000000')
 *   <size width="6dp" height="6dp"> → .width(6).height(6)
 */


@Component
export struct SpacerX6 {
  @Prop boxWidth: Length = 6;
  @Prop boxHeight: Length = 6;
  build() {
    Column() {
    }
    .width(this.boxWidth)
    .height(this.boxHeight)
        .backgroundColor('#00000000')
    .borderRadius(0)
  }
}