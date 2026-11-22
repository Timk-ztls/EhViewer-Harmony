/*
 * 上游：app/src/main/res/layout/dialog_list_checkbox_builder.xml（inventory S0580，上游 44 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/dialog_list_checkbox_builder.ets
 *
 * 背景：带"不再提示"复选框的**列表**对话框（与 dialog_checkbox_builder 的区别：
 * 上面是列表而不是可滚动文本）。
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                ArkUI
 * LinearLayout(vertical, match × wrap)    Column().width('100%')
 * com.hippo.widget.IndicatingListView    IndicatingListView（ui-widget 已交付）
 *   layout_height=0dp / weight=1           .layoutWeight(1)
 *   divider=?attr/listDividerAlertDialog   分隔线由控件内部按主题设置
 *   paddingTop/Bottom=8dp                  .padding({top:8,bottom:8})
 *   clipToPadding=false                    ArkUI 默认不裁剪（无需设置）
 *   style=Indicating                       空态/错误态由控件内部处理
 * AppCompatCheckBox#checkbox             Checkbox
 *   marginLeft/Right=?attr/dialogPreferredPadding(24dp)  .margin({left:24,right:24})
 *   marginBottom=@dimen/abc_dialog_padding_top_material(24dp) .margin({bottom:24})
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `IndicatingListView` 已交付（`hippo/widget/IndicatingListView.ets`）→ 直接 import；
 *    **调用必须用显式 content 参数**（`IndicatingListView({ content: this.x })`），
 *    不能用尾随块 + 链式属性（ets 解析器报 Declaration or statement expected，实测）。
 * 2. `divider`/`dividerHeight`/`scrollbars`/`overScrollMode`/`fadingEdge` 都是 Android 列表
 *    控件属性：ArkUI 的 `List` 用 `.divider({strokeWidth,color})` 表达分隔线，其余无对位
 *    （滚动条由系统、过滚动/渐隐边不暴露）—— 属控件内部，布局层不复刻。
 * 3. 与 dialog_checkbox_builder 的**差异**：那边是可滚动文本 + marginTop 24，
 *    这边是列表（weight 1 + 上下 8dp padding）+ 复选框 marginBottom 24。
 *    两者不能互相复用。
 */

import { IndicatingListView } from '../../widget/IndicatingListView';

@Component
export struct ListCheckboxBuilderDialogLayout {
  @Prop checkboxText: string = '';
  @Prop checked: boolean = false;
  @Prop textColor: ResourceColor = '#DE000000';
  /** 上游 ?attr/dialogPreferredPadding（Material 24dp） */
  @Prop dialogPreferredPadding: number = 24;
  /** 上游 @dimen/abc_dialog_padding_top_material（24dp） */
  @Prop dialogPaddingBottom: number = 24;

  onCheckedChange: (checked: boolean) => void = (checked: boolean) => {
    // 默认空实现：使用方注入
  };

  /** 列表内容（上游 IndicatingListView 的子项由 Adapter 提供） */
  @BuilderParam listContent: () => void = this.emptyList;

  @Builder
  emptyList() {
    Row().width(0).height(0)
  }

  build() {
    Column() {
      IndicatingListView({ content: this.listContent })
        .width('100%')
        .layoutWeight(1)
        .padding({ top: 8, bottom: 8 })

      Row() {
        Checkbox({ name: 'checkbox' })
          .select(this.checked)
          .onChange((value: boolean) => {
            this.checked = value;
            this.onCheckedChange(value);
          })
        Text(this.checkboxText)
          .fontSize($r('app.float.text_small'))
          .fontColor(this.textColor)
      }
      .width('100%')
      .margin({
        left: this.dialogPreferredPadding,
        right: this.dialogPreferredPadding,
        bottom: this.dialogPaddingBottom
      })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
