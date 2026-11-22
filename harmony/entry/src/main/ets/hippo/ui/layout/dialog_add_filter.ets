/*
 * 上游：app/src/main/res/layout/dialog_add_filter.xml（inventory S0568，上游 46 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/dialog_add_filter.ets
 *
 * 背景：添加过滤项：类型下拉（CuteSpinner）+ 一个输入框。
 * 与 dialog_add_blacklist（S0567）**结构同型**，差别有三处（不能直接别名复用）：
 *   1. 本布局的 CuteSpinner 没有包 TextInputLayout（无 hint / 无 marginTop）
 *   2. 输入框 hint 是 @string/filter_text（blacklist 是 @string/blacklist_text）
 *   3. 输入框 maxLines=1（blacklist 是 maxLines=2 + singleLine）
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                ArkUI
 * LinearLayout(vertical)                  Column
 *   paddingLeft/Right=?attr/dialogPreferredPadding(24dp)  .padding({left:24,right:24})
 *   paddingTop=@dimen/abc_dialog_padding_top_material(24dp) .padding({top:24})
 * com.hippo.widget.CuteSpinner#spinner    CuteSpinner（ui-widget 已交付）
 *   entries=@array/filter_entries           $r('app.array.filter_entries')
 * TextInputLayout#text_input_layout       Column
 *   layout_marginTop=16dp                    .margin({top:16})
 *   hint=@string/filter_text                 → TextInput placeholder
 *   HackyTextInputEditText#edit_text         TextInput（TODO(ui-widget)）
 *     imeOptions=actionDone                    EnterKeyType.Done
 *     inputType=text                           InputType.Normal
 *     maxLines=1 / singleLine=true             .maxLines(1)
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `TextInputLayout` 无 ArkUI 对位 → 只取 hint 作 placeholder，不伪造浮动标签动画。
 * 2. 注意与 dialog_add_blacklist 的**三处结构差异**（见文件头）：Spinner 是否被
 *    TextInputLayout 包裹、hint 文案、maxLines —— 别名复用会丢掉这些差异，故单独实现。
 * 3. `CuteSpinner` 已交付，直接 import；`filter_entries` 数组已在 arrays.json。
 */

import { CuteSpinner } from '../../widget/CuteSpinner';

@Component
export struct AddFilterDialogLayout {
  @Prop spinnerIndex: number = 0;
  @Prop text: string = '';
  @Prop textColor: ResourceColor = '#DE000000';
  @Prop dialogPreferredPadding: number = 24;
  @Prop dialogPaddingTop: number = 24;

  onSpinnerChange: (index: number) => void = (index: number) => {
    // 默认空实现：使用方注入
  };
  onTextChange: (value: string) => void = (value: string) => {
    // 默认空实现：使用方注入
  };

  build() {
    Column() {
      // 类型下拉（上游**没有** TextInputLayout 包裹、没有 marginTop）
      CuteSpinner()
        .width('100%')

      // 输入（TextInputLayout hint=@string/filter_text，marginTop 16）
      Column() {
        // TODO(ui-widget): com.hippo.widget.HackyTextInputEditText
        TextInput({ text: this.text, placeholder: $r('app.string.filter_text') })
          .type(InputType.Normal)
          .enterKeyType(EnterKeyType.Done)
          .maxLines(1)
          .fontColor(this.textColor)
          .width('100%')
          .onChange((value: string) => {
            this.text = value;
            this.onTextChange(value);
          })
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .width('100%')
    .padding({
      left: this.dialogPreferredPadding,
      right: this.dialogPreferredPadding,
      top: this.dialogPaddingTop
    })
    .alignItems(HorizontalAlign.Start)
  }
}
