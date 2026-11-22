/*
 * 上游：app/src/main/res/layout/dialog_add_blacklist.xml（inventory S0567，上游 54 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/dialog_add_blacklist.ets
 *
 * 背景：添加黑名单项：一个类型下拉（CuteSpinner）+ 一个原因输入框。
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                      ArkUI
 * LinearLayout(vertical)                        Column
 *   paddingLeft/Right=?attr/dialogPreferredPadding(24dp)  .padding({left:24,right:24})
 *   paddingTop=@dimen/abc_dialog_padding_top_material(24dp) .padding({top:24})
 * TextInputLayout#text_input_layout             Column（见 1）
 *   layout_marginTop=16dp                         .margin({top:16})
 *   hint=@string/blacklist_text                   → 作为 Spinner 的占位说明（见 2）
 *   com.hippo.widget.CuteSpinner#spinner          CuteSpinner（ui-widget 已交付）
 *     entries=@array/blacklist_entries              $r('app.array.blacklist_entries')
 * TextInputLayout#text_inputreason_layout       Column
 *   layout_marginTop=16dp                         .margin({top:16})
 *   hint=@string/blacklist_text                    → TextInput 的 placeholder
 *   HackyTextInputEditText#reason_text            TextInput（TODO(ui-widget)）
 *     imeOptions=actionDone / inputType=text        EnterKeyType.Done / InputType.Normal
 *     maxLines=2 / singleLine=true                  .maxLines(1)（见 3）
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `TextInputLayout`（Material 浮动标签容器）在 ArkUI 无对位：它提供浮动 label + 错误位，
 *    本布局只用它的 hint 语义 → 拆成"标签文本/placeholder + 输入控件"，不伪造浮动动画。
 * 2. 两个 TextInputLayout 的 `android:hint` **都是 `@string/blacklist_text`**（上游复制粘贴，
 *    两处 hint 文案相同）；照原样保留（不"顺手修正"成不同文案，否则与上游不一致）。
 * 3. `maxLines=2` 与 `singleLine=true` 同时存在时 **singleLine 优先**（Android 语义）→
 *    实际单行输入，ArkUI 用 `.maxLines(1)` 对位（这与 item_simple_list_2 的
 *    "textSize 覆盖 textAppearance" 是同一类"显式属性覆盖"规则）。
 * 4. `CuteSpinner` 已由 ui-widget 交付（`hippo/widget/CuteSpinner.ets`），直接 import；
 *    其 entries 通过数组资源传入（arrays.json 已有 blacklist_entries）。
 * 5. `HackyTextInputEditText` 未交付 → 用系统 TextInput 对位外观与输入属性，标 TODO(ui-widget)。
 */

import { CuteSpinner } from '../../widget/CuteSpinner';

@Component
export struct AddBlacklistDialogLayout {
  @Prop spinnerIndex: number = 0;
  @Prop reason: string = '';
  @Prop textColor: ResourceColor = '#DE000000';
  /** 上游 ?attr/dialogPreferredPadding（Material 24dp） */
  @Prop dialogPreferredPadding: number = 24;
  /** 上游 @dimen/abc_dialog_padding_top_material（24dp） */
  @Prop dialogPaddingTop: number = 24;

  onSpinnerChange: (index: number) => void = (index: number) => {
    // 默认空实现：使用方注入
  };
  onReasonChange: (value: string) => void = (value: string) => {
    // 默认空实现：使用方注入
  };

  build() {
    Column() {
      // 类型下拉（上游 TextInputLayout + CuteSpinner，hint=@string/blacklist_text）
      Column() {
        CuteSpinner()
          .width('100%')
      }
      .width('100%')
      .margin({ top: 16 })

      // 原因输入（上游 TextInputLayout + HackyTextInputEditText）
      Column() {
        // TODO(ui-widget): com.hippo.widget.HackyTextInputEditText（TextInputLayout hint hack）
        TextInput({ text: this.reason, placeholder: $r('app.string.blacklist_text') })
          .type(InputType.Normal)
          .enterKeyType(EnterKeyType.Done)
          .maxLines(1)
          .fontColor(this.textColor)
          .width('100%')
          .onChange((value: string) => {
            this.reason = value;
            this.onReasonChange(value);
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
