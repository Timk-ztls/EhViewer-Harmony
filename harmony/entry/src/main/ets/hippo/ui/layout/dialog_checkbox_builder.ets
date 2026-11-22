/*
 * 上游：app/src/main/res/layout/dialog_checkbox_builder.xml（inventory S0571，上游 43 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/dialog_checkbox_builder.ets
 *
 * 背景：带"不再提示"复选框的确认对话框（message 可滚动 + 复选框）。
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                    ArkUI
 * LinearLayout(vertical, match × match)       Column().width('100%').height('100%')
 * com.hippo.widget.IndicatingScrollView       IndicatingScrollView（ui-widget 已交付）
 *   style=Indicating                            → 空态/错误态由控件内部处理
 *   layout_height=0dp / weight=1                .layoutWeight(1)
 *   TextView#message                            Text：AppCompat.Subhead(16fp)
 *     paddingLeft/Right=?attr/dialogPreferredPadding(24dp)  .padding({left:24,right:24})
 *     paddingTop=@dimen/abc_dialog_padding_top_material(24dp) .padding({top:24})
 * AppCompatCheckBox#checkbox                 Checkbox
 *   marginLeft/Right=?attr/dialogPreferredPadding(24dp)  .margin({left:24,right:24})
 *   marginTop=@dimen/abc_dialog_padding_top_material(24dp) .margin({top:24})
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `IndicatingScrollView` 已由 ui-widget 交付（`hippo/widget/IndicatingScrollView.ets`），
 *    直接 import；它的"内容区 + 空态/错误态"切换属控件行为，布局层不复制。
 *    上游 `layout_height=0dp + weight=1` → ArkUI `.layoutWeight(1)`（占满剩余高度）。
 * 2. `?attr/dialogPreferredPadding`（Material 对话框水平内边距 24dp）与
 *    `@dimen/abc_dialog_padding_top_material`（24dp）都是 24，但**来源不同**：
 *    前者是主题属性、后者是 dimens —— 分别做成 @Prop，不合并成一个常量（便于主题化时独立调整）。
 * 3. 复选框文案由使用方注入（上游 `setText()`），布局层不写死文案；
 *    选中态走 @Link 语义的 @Prop + 回调（C-13 可空约定不涉及布尔）。
 */

import { IndicatingScrollView } from '../../widget/IndicatingScrollView';

@Component
export struct CheckboxBuilderDialogLayout {
  @Prop message: string = '';
  @Prop checkboxText: string = '';
  @Prop checked: boolean = false;

  /** 上游 ?attr/dialogPreferredPadding（Material 24dp） */
  @Prop dialogPreferredPadding: number = 24;
  /** 上游 @dimen/abc_dialog_padding_top_material（24dp） */
  @Prop dialogPaddingTop: number = 24;
  @Prop messageColor: ResourceColor = '#DE000000';

  onCheckedChange: (checked: boolean) => void = (checked: boolean) => {
    // 默认空实现：使用方注入
  };

  /** 滚动内容（上游 IndicatingScrollView 的单一子 View） */
  @Builder
  messageContent() {
    Text(this.message)
      .fontSize($r('app.float.text_little_small'))
      .fontColor(this.messageColor)
      .width('100%')
      .padding({
        left: this.dialogPreferredPadding,
        right: this.dialogPreferredPadding,
        top: this.dialogPaddingTop
      })
  }

  build() {
    Column() {
      IndicatingScrollView({ content: this.messageContent })
        .width('100%')
        .layoutWeight(1)

      Row() {
        Checkbox({ name: 'checkbox' })
          .select(this.checked)
          .onChange((value: boolean) => {
            this.checked = value;
            this.onCheckedChange(value);
          })
        Text(this.checkboxText)
          .fontSize($r('app.float.text_small'))
          .fontColor(this.messageColor)
      }
      .width('100%')
      .margin({ left: this.dialogPreferredPadding, right: this.dialogPreferredPadding,
                top: this.dialogPaddingTop })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }
}


