/**
 * 重绘自 app/src/main/res/drawable/bg_tag_chip.xml  （inventory S0716，上游 7 行）
 * 上游节点：<shape android:shape="rectangle">
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: base）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 *   <solid color="#FFFFFF"> → .backgroundColor('#FFFFFFFF')
 *   <stroke width="1"dp color="#BDBDBD"> → .border({ width: 1, color: '#FFBDBDBD' })
 *   <corners radius="20dp"> → .borderRadius(20)
 */


@Component
export struct BgTagChip {
  @Prop boxWidth: Length = '100%';
  @Prop boxHeight: Length = '100%';
  build() {
    Column() {
    }
    .width(this.boxWidth)
    .height(this.boxHeight)
        .backgroundColor('#FFFFFFFF')
        .border({ width: 1, color: '#FFBDBDBD' })
    .borderRadius(20)
  }
}