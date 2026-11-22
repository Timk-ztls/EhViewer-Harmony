/*
 * 上游：app/src/main/res/layout/preference_dialog_default_categories.xml（inventory S0639，上游 30 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/preference_dialog_default_categories.ets
 *
 * 背景：默认分类对话框内容 = 可滚动容器 + CategoryTable（本模块 S0676 已实现）。
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                ArkUI
 * com.hippo.widget.IndicatingScrollView   IndicatingScrollView（ui-widget 已交付）
 *   style=Indicating                       空态/错误态由控件内部处理
 *   layout_height=0dp / weight=1           .layoutWeight(1)（占满对话框剩余高度）
 *   layout_width=match_parent               .width('100%')
 * com.hippo.ehviewer.widget.CategoryTable  CategoryTableWidgetLayout（S0676，直接 import）
 *   paddingLeft/Right=?attr/dialogPreferredPadding(24dp)  .padding({left:24,right:24})
 *   paddingTop=@dimen/abc_dialog_padding_top_material(24dp) .padding({top:24})
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `IndicatingScrollView` 的 content 必须**显式传 @Builder**：
 *    `IndicatingScrollView({ content: this.tableContent })` —— 不能用尾随块 + 链式属性
 *    （ets 解析器报 Declaration or statement expected，实测于 dialog_checkbox_builder）。
 * 2. CategoryTable 已在本模块落地（widget_category_table.ets，S0676），直接 import 复用，
 *    **不重复实现**分类格子与颜色表；它自身的 4vp 格间距保持不变。
 * 3. 两套 24dp 来源分开：`?attr/dialogPreferredPadding`（主题属性）与
 *    `@dimen/abc_dialog_padding_top_material`（dimens）—— 分别 @Prop（主题化后会分叉）。
 * 4. 上游 CategoryTable 只设 padding（无 margin），滚动容器也没有额外 padding —— 按原样。
 */

import { IndicatingScrollView } from '../../widget/IndicatingScrollView';
import { CategoryTableWidgetLayout } from './widget_category_table';

@Component
export struct DefaultCategoriesDialogLayout {
  /** 已选分类（透传给 CategoryTable） */
  @Prop selected: number[] = [];
  /** 上游 ?attr/dialogPreferredPadding（Material 24dp） */
  @Prop dialogPreferredPadding: number = 24;
  /** 上游 @dimen/abc_dialog_padding_top_material（24dp） */
  @Prop dialogPaddingTop: number = 24;

  onToggle: (id: number, checked: boolean) => void = (id: number, checked: boolean) => {
    // 默认空实现：使用方注入
  };

  @Builder
  tableContent() {
    CategoryTableWidgetLayout({ selected: this.selected, onToggle: this.onToggle })
      .width('100%')
      .padding({
        left: this.dialogPreferredPadding,
        right: this.dialogPreferredPadding,
        top: this.dialogPaddingTop
      })
  }

  build() {
    IndicatingScrollView({ content: this.tableContent })
      .width('100%')
      .layoutWeight(1)
  }
}
