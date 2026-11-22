/*
 * 上游：app/src/main/res/layout/dialog_edittext_builder.xml（inventory S0573，上游 32 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/dialog_edittext_builder.ets
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                    ArkUI
 * TextInputLayout(match × match)              Column（见「无法等价」1）
 *   paddingLeft/Right=?attr/dialogPreferredPadding(24dp)  .padding({left:24,right:24})
 *   paddingTop=@dimen/abc_dialog_padding_top_material(24dp)  .padding({top:24})
 * com.hippo.widget.HackyTextInputEditText     TextInput（见 2）
 *   layout_width=match_parent                   .width('100%')
 *   layout_height=wrap_content                  （默认）
 *   imeOptions=actionDone                       .enterKeyType(EnterKeyType.Done)
 *   inputType=text                              .type(InputType.Normal)
 *   maxLines=1 / singleLine=true                .maxLines(1)
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `TextInputLayout`（Material 浮动标签容器）在 ArkUI 无对位：它提供的浮动 label、
 *    错误文案位、计数位都由具体对话框按需设置。本布局只落**容器内边距**（24/24/24），
 *    label/error 交给使用方（或后续 ui-widget 的等价容器）。
 * 2. `HackyTextInputEditText`（上游 hack：解决 TextInputLayout + EditText 的 hint 兼容问题）
 *    未由 ui-widget 交付 → 用系统 `TextInput` 对位外观与输入属性；hint/超链接等
 *    hack 行为属控件内部，标 TODO(ui-widget)。
 * 3. `?attr/dialogPreferredPadding` 是运行期主题属性（Material 对话框水平内边距 = 24dp），
 *    默认 24 并做成 @Prop。
 */

@Component
export struct EditTextBuilderDialogLayout {
  @Prop text: string = '';
  @Prop placeholder: string = '';
  @Prop textColor: ResourceColor = '#DE000000';
  @Prop paddingHorizontal: number = 24;
  @Prop paddingTop: number = 24;

  /** 输入变化回调（上游 EditText.addTextChangedListener） */
  onTextChange: (value: string) => void = (value: string) => {
    // 默认空实现：使用方注入
  };

  build() {
    Column() {
      // TODO(ui-widget): com.hippo.widget.HackyTextInputEditText（TextInputLayout hint 兼容 hack）
      TextInput({ text: this.text, placeholder: this.placeholder })
        .type(InputType.Normal)
        .enterKeyType(EnterKeyType.Done)
        .maxLines(1)
        .fontColor(this.textColor)
        .width('100%')
        .onChange((value: string) => {
          this.onTextChange(value);
        })
    }
    .width('100%')
    .padding({
      left: this.paddingHorizontal,
      right: this.paddingHorizontal,
      top: this.paddingTop
    })
    .alignItems(HorizontalAlign.Start)
  }
}
