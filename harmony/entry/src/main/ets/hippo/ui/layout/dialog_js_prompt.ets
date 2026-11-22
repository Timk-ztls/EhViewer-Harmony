/*
 * 上游：app/src/main/res/layout/dialog_js_prompt.xml（inventory S0579，上游 34 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/dialog_js_prompt.ets
 *
 * 背景：JS 脚本 prompt() 的对话框内容（一行 message + 一个输入框）。
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                ArkUI
 * LinearLayout(vertical)                  Column
 *   layout_width=match_parent               .width('100%')
 *   padding=@dimen/keyline_margin(16dp)     .padding($r('app.float.keyline_margin'))
 * TextView#message                        Text
 *   textAppearance=AppCompat.Subhead        .fontSize($r('app.float.text_little_small'))（16sp）
 *   layout_width=match_parent               .width('100%')
 * EditText#value                          TextInput
 *   layout_marginTop=@dimen/keyline_margin  .margin({top: $r('app.float.keyline_margin')})
 *   inputType=text                          .type(InputType.Normal)
 *   layout_width=match_parent               .width('100%')
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `?attr/dialogPreferredPadding` 在本布局**没有使用**（用的是 keyline_margin=16dp），
 *    与 dialog_edittext_builder（24dp）不同 —— 两者不要互相套用。
 * 2. `TextAppearance.AppCompat.Subhead` = 16sp，对应已迁资源 `app.float.text_little_small`。
 * 3. 上游未设 textColor → 主题默认（@Prop 注入位保留）。
 * 4. 输入值默认空字符串 `''`（上游 dialog 代码在读不到时用空串），不做 null 语义
 *    （C-13：可空一律 `T | null`，但这里是"输入框内容"，空串即空值，与上游一致）。
 */

@Component
export struct JsPromptDialogLayout {
  @Prop message: string = '';
  @Prop value: string = '';
  @Prop messageColor: ResourceColor = '#DE000000';

  onValueChange: (value: string) => void = (value: string) => {
    // 默认空实现：使用方注入
  };

  build() {
    Column() {
      Text(this.message)
        .fontSize($r('app.float.text_little_small'))
        .fontColor(this.messageColor)
        .width('100%')

      TextInput({ text: this.value })
        .type(InputType.Normal)
        .width('100%')
        .margin({ top: $r('app.float.keyline_margin') })
        .onChange((value: string) => {
          this.onValueChange(value);
        })
    }
    .width('100%')
    .padding($r('app.float.keyline_margin'))
    .alignItems(HorizontalAlign.Start)
  }
}
