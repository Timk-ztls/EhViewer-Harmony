/**
 * 重绘自 app/src/main/res/drawable/jump_selector_shape.xml  （inventory S0762，上游 6 行）
 * 上游节点：<shape android:shape="rectangle">
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: base）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 *   <corners radius="12dp"> → .borderRadius(12)
 */


@Component
export struct JumpSelectorShape {
  @Prop boxWidth: Length = '100%';
  @Prop boxHeight: Length = '100%';
  build() {
    Column() {
    }
    .width(this.boxWidth)
    .height(this.boxHeight)
        .backgroundColor(Color.Transparent)
    .borderRadius(12)
  }
}