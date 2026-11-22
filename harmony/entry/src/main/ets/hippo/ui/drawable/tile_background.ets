/**
 * 重绘自 app/src/main/res/drawable/tile_background.xml  （inventory S0773，上游 21 行）
 * 上游节点：<selector>
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: base）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 *   [this.activated] drawable @drawable/tile_background_activated → .backgroundColor('#7F9C27B0')
 *   [default] drawable @drawable/transparent → .backgroundColor('#00000000')
 * 差异：Android StateListDrawable 由 View 的 drawableState 驱动，ArkUI 无 state 选择器体系；
 *       故把 state_* 提升为组件入参，由调用方（ui-scene 的控件）按激活/选中状态传入，语义等价、时机由调用方决定。
 */


@Component
export struct TileBackground {
  @Prop activated : boolean = false;
  build() {
    Stack() {
      if (this.activated) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#7F9C27B0')
          .borderRadius(0)
      } else
      {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#00000000')
          .borderRadius(0)
      }
    }
    .width('100%')
    .height('100%')
  }
}