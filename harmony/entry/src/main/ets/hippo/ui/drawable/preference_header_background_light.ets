/**
 * 重绘自 app/src/main/res/drawable/preference_header_background_light.xml  （inventory S0767，上游 20 行）
 * 上游节点：<selector>
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: base）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 *   [this.activated] drawable @drawable/grey_200 → .backgroundColor(DrawablePalette.GREY_200)
 *   [default] drawable @drawable/transparent → .backgroundColor('#00000000')
 * 差异：Android StateListDrawable 由 View 的 drawableState 驱动，ArkUI 无 state 选择器体系；
 *       故把 state_* 提升为组件入参，由调用方（ui-scene 的控件）按激活/选中状态传入，语义等价、时机由调用方决定。
 */
import { DrawablePalette } from '../../drawable/DrawablePalette';

@Component
export struct PreferenceHeaderBackgroundLight {
  @Prop activated : boolean = false;
  build() {
    Stack() {
      if (this.activated) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(DrawablePalette.GREY_200)
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