/*
 * 上游：app/src/main/res/layout/dialog_go_to.xml（inventory S0576，上游 44 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/dialog_go_to.ets
 *
 * 背景：阅读器"跳转到指定页"对话框：左页码 + 滑杆 + 右页码。
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                              ArkUI
 * LinearLayout(horizontal)              Row
 *   layout_height=match_parent            .height('100%')
 *   paddingTop=16dp                       .padding({top:16})
 *   paddingLeft/Right=16dp                .padding({left:16,right:16})
 * TextView#start（32dp 宽）             Text：.width(32) + textAlign(Center)
 *   gravity=center_horizontal             .align 由 Row 的 VerticalAlign.Center 承担
 * com.hippo.widget.Slider#slider        Slider（ArkUI 内置；上游自定义同名控件，见 1）
 *   style=@style/Slider                   见 2
 *   layout_width=0dp / weight=1           .layoutWeight(1)
 *   layout_height=48dp                    .height(48)
 * TextView#end（32dp 宽）               Text：.width(32) + textAlign(Center)
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. **组件名陷阱**：上游自定义控件叫 `com.hippo.widget.Slider`，而 `Slider` 是 ArkUI 内置组件标签名，
 *    **不能用作 struct 名**（CONTRIBUTING 陷阱 7）。本文件 struct 名取 `GoToDialogLayout`，
 *    内部直接用 ArkUI 的 `Slider`——两者不是同一个东西，但视觉与交互对位（连续滑动选页码）。
 * 2. `@style/Slider` 是上游对滑块的高度/颜色定制；ArkUI `Slider` 默认样式与 Material 有差异：
 *    轨道高/滑块半径不做像素级复刻，只固定 48vp 高度（与上游 layout_height 一致），
 *    颜色走 `.selectedColor/.trackColor` 的 @Prop 注入位。
 * 3. 页码文本（start/end）的字体未在上游指定 → 主题默认；`gravity=center_horizontal` →
 *    `TextAlign.Center`，垂直方向由 Row 的 `alignItems(VerticalAlign.Center)` 对齐。
 */

@Component
export struct GoToDialogLayout {
  @Prop min: number = 1;
  @Prop max: number = 100;
  @Prop value: number = 1;
  @Prop startText: string = '';
  @Prop endText: string = '';
  @Prop textColor: ResourceColor = '#DE000000';
  @Prop trackColor: ResourceColor = '#33FF6200EE';
  @Prop selectedColor: ResourceColor = '#FF6200EE';

  onValueChange: (value: number) => void = (value: number) => {
    // 默认空实现：使用方注入
  };

  build() {
    Row() {
      Text(this.startText)
        .width(32)
        .fontColor(this.textColor)
        .textAlign(TextAlign.Center)

      Slider({ value: this.value, min: this.min, max: this.max, step: 1 })
        .id('slider')
        .layoutWeight(1)
        .height(48)
        .trackColor(this.trackColor)
        .selectedColor(this.selectedColor)
        .onChange((value: number) => {
          this.value = value;
          this.onValueChange(value);
        })

      Text(this.endText)
        .width(32)
        .fontColor(this.textColor)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height('100%')
    .padding({ top: 16, left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
  }
}
