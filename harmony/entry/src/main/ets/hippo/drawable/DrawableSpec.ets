/**
 * ui-widget · Drawable 绘制指令换算层
 * 登记：inventory/ui-widget.extra.txt → harmony/entry/src/main/ets/hippo/drawable/
 *
 * 上游 `GradientDrawable`(shape) / `VectorDrawable`(vector) / `StateListDrawable`(selector) 在 ArkUI 里
 * 没有对应类型，逐条换算成 ArkUI 属性/组件。本文件只放"换算规则"，具体绘制在各绘制文件中内联展开。
 *
 * 关键换算 1：渐变角度
 *   Android `<gradient android:angle>`：0° = 从左到右，逆时针为正方向（90° = 从下往上，270° = 从上往下）
 *   ArkUI `.linearGradient({ angle })`：0° = 从下往上（0 点方向），顺时针为正方向
 *   两者的方向向量：
 *     Android  d = ( cos a, -sin a )        （屏幕坐标 y 向下）
 *     ArkUI    d = ( sin b, -cos b )
 *     令二者相等 ⇒ b = 90° - a
 *   故换算公式：(90 - androidAngle + 360) % 360
 *
 * 关键换算 2：尺寸
 *   Android dp 值 → ArkUI vp 值（1dp ≡ 1vp，系统 DPI 缩放下同义），直接搬数值。
 */
export class DrawableSpec {
  /** Android GradientDrawable angle → ArkUI linearGradient angle（见文件头推导） */
  static androidAngleToArkUI(androidAngle: number): number {
    const b: number = (90 - androidAngle) % 360;
    return b < 0 ? b + 360 : b;
  }

  /** 两色渐变停靠点，等价 Android <gradient startColor/endColor>（无 centerColor 时） */
  static twoStop(start: ResourceColor, end: ResourceColor): Array<[ResourceColor, number]> {
    return [[start, 0.0], [end, 1.0]];
  }

  /** 三色渐变停靠点，等价 Android <gradient centerColor> 存在的场景 */
  static threeStop(start: ResourceColor, center: ResourceColor, end: ResourceColor): Array<[ResourceColor, number]> {
    return [[start, 0.0], [center, 0.5], [end, 1.0]];
  }
}
