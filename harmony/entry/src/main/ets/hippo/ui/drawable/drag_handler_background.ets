/**
 * 重绘自 app/src/main/res/drawable/drag_handler_background.xml  （inventory S0728，上游 6 行）
 * 上游节点：<shape android:shape="rectangle">
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: base）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 *   <solid color="#80000000"> → .backgroundColor('#80000000')
 *   <corners radius="4dp"> → .borderRadius(4)
 */


@Component
export struct DragHandlerBackground {
  @Prop boxWidth: Length = '100%';
  @Prop boxHeight: Length = '100%';
  build() {
    Column() {
    }
    .width(this.boxWidth)
    .height(this.boxHeight)
        .backgroundColor('#80000000')
    .borderRadius(4)
  }
}