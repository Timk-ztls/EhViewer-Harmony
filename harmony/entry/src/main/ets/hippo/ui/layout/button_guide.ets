/*
 * 上游：app/src/main/res/layout/button_guide.xml（inventory S0566，上游 26 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/button_guide.ets
 *
 * 背景：引导页右下角的"知道了/Get it"按钮（无背景、白字、加粗）。
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                            ArkUI
 * Button                             Button
 *   layout_width/height=wrap_content   内容撑开（不写 '100%'）
 *   text=@string/get_it                $r('app.string.get_it')
 *   textStyle=bold                     .fontWeight(FontWeight.Bold)
 *   background=@null                   .backgroundColor(Color.Transparent)（见 1）
 *   textSize=@dimen/text_little_small   .fontSize($r('app.float.text_little_small'))（16fp）
 *   textAllCaps=true                   （见 2）
 *   textColor=@android:color/white      .fontColor(Color.White)
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `background="@null"` 是"**无背景**"，不是"透明背景"：Android 上还会丢掉 Button 的
 *    最小宽度/内边距（默认 style 的 padding）。ArkUI 的 `Button` 自带圆角背景与内边距 →
 *    必须同时 `ButtonType.Normal` + 透明背景 + `padding(0)`，否则按钮会比上游"胖一圈"。
 * 2. `textAllCaps="true"` ArkUI 无属性：`@string/get_it` 各语言资源已按需要大小写维护，
 *    布局层不做 toUpperCase（locale 相关变换不能放布局层，与 item_gallery_list 同一处理）。
 * 3. 无 `minWidth/minHeight`：上游 wrap_content，按内容撑开。
 */

@Component
export struct ButtonGuideLayout {
  @Prop text: ResourceStr = $r('app.string.get_it');
  @Prop textColor: ResourceColor = Color.White;

  /** 注意：成员名**不能**叫 onClick（与 CustomComponent 基类成员冲突，编译报 not assignable） */
  onButtonClick: () => void = () => {
    // 默认空实现：使用方注入
  };

  build() {
    Button(this.text)
      .type(ButtonType.Normal)
      .backgroundColor(Color.Transparent)
      .padding(0)
      .fontSize($r('app.float.text_little_small'))
      .fontWeight(FontWeight.Bold)
      .fontColor(this.textColor)
      .onClick(() => {
        this.onButtonClick();
      })
  }
}


