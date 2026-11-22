/*
 * 上游：app/src/main/res/layout/dialog_recycler_view.xml（inventory S0582，上游 23 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/dialog_recycler_view.ets
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                    ArkUI
 * com.hippo.easyrecyclerview.EasyRecyclerView  @BuilderParam listBuilder（见「无法等价」1）
 *   style=@style/Indicating                     → 空态/错误提示由 IndicatingListView 承担（ui-widget 已交付）
 *   paddingTop/Bottom=@dimen/abc_dialog_padding_top_material(24dp)  .padding({top:24,bottom:24})
 *   match_parent × match_parent                 .width('100%').height('100%')
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `EasyRecyclerView`（含 Indicating 空态/错误态）未由 ui-widget 交付完整等价物
 *    （现有 `IndicatingListView` / `IndicatingScrollView` 是 Scroll 系，不是 Recycler 的
 *    多布局/StaggeredGrid 能力）→ 用 @BuilderParam 槽位承载列表实现，本布局只负责
 *    外层尺寸与上下 24dp 内边距，标 TODO(ui-widget)。
 * 2. `@style/Indicating` 的效果是"列表为空/出错时在中心显示提示"，属控件内部行为，
 *    布局层不复刻（不写假实现）。
 * 3. 这是**对话框内容**的通用宿主：padding 只为和 Material 对话框的 24dp 边距对齐，
 *    左右 padding 由具体对话框（AlertDialog）给，本布局只管上下。
 */

@Component
export struct RecyclerViewDialogLayout {
  /** 列表实现（上游 EasyRecyclerView，ui-widget 交付后注入） */
  @BuilderParam listBuilder: () => void = this.emptyList;

  @Builder
  emptyList() {
    // TODO(ui-widget): com.hippo.easyrecyclerview.EasyRecyclerView（Indicating 空态/错误态）
    Column().width('100%').height('100%')
  }

  build() {
    Column() {
      this.listBuilder();
    }
    .width('100%')
    .height('100%')
    .padding({ top: 24, bottom: 24 })
  }
}
