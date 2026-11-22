/**
 * 重绘自 app/src/main/res/drawable/bg_tag_selector.xml  （inventory S0717，上游 16 行）
 * 上游节点：<selector>
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: base）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 *   [this.selected] solid #009688 → .backgroundColor('#FF009688')
 *   [default] solid #00000000 → .backgroundColor('#00000000')
 *   [default] stroke 1=#BDBDBD → .border(...)
 * 差异：Android StateListDrawable 由 View 的 drawableState 驱动，ArkUI 无 state 选择器体系；
 *       故把 state_* 提升为组件入参，由调用方（ui-scene 的控件）按激活/选中状态传入，语义等价、时机由调用方决定。
 */


@Component
export struct BgTagSelector {
  @Prop selected : boolean = false;
  build() {
    Stack() {
      if (this.selected) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#FF009688')
          .borderRadius(16)
      } else
      {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#00000000')
        .border({ width: 1, color: '#FFBDBDBD' })
          .borderRadius(16)
      }
    }
    .width('100%')
    .height('100%')
  }
}