/**
 * 重绘自 app/src/main/res/drawable/shadow_bottom.xml  （inventory S0769，上游 24 行）
 * 上游节点：<shape android:shape="rectangle">
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: base）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 *   <gradient startColor="@android:color/transparent" endColor="@color/shadow_light" angle="90"> → .linearGradient({ angle: 0, colors: [[start,0.0],[end,1.0]] })
 *     angle 换算：(90 - 90 + 360) % 360 = 0。Android 0°=左→右逆时针为正；ArkUI 0°=下→上顺时针为正
 *     差异：Android GradientDrawable 的渐变按 drawable 边界计算，ArkUI linearGradient 按组件边界计算 —— 组件尺寸与 drawable 相同时等价
 */
import { DrawablePalette } from '../../drawable/DrawablePalette';

@Component
export struct ShadowBottom {
  @Prop boxWidth: Length = '100%';
  @Prop boxHeight: Length = '100%';
  build() {
    Column() {
    }
    .width(this.boxWidth)
    .height(this.boxHeight)
        .linearGradient({ angle: 0, colors: [['#00000000', 0.0], [DrawablePalette.SHADOW_LIGHT, 1.0]] })
    .borderRadius(0)
  }
}