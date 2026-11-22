/*
 * 上游：app/src/main/res/layout/dialog_archive_list.xml（inventory S0569，上游 39 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/dialog_archive_list.ets
 *
 * 背景：归档列表对话框：加载中转圈 / 空提示 / 列表三态**叠放**。
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                               ArkUI
 * FrameLayout(wrap × wrap)                Stack
 *   paddingTop/Bottom=@dimen/abc_dialog_padding_top_material(24dp)  .padding({top:24,bottom:24})
 * com.hippo.widget.ProgressView#progress  LoadingProgress + TODO(ui-widget)（32vp，居中）
 *   layout_gravity=center                   .align(Alignment.Center)
 * TextView#text（AppCompat.Medium）       Text：text_medium(18fp) + 居中
 *   layout_gravity=center                   .align(Alignment.Center)
 * ListView#list_view（match × match）     @BuilderParam listBuilder（见 2）
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. 三态是**叠放**（FrameLayout 子元素同一位置，靠可见性切换）→ 必须 `Stack`，
 *    写成 `Column` 会把转圈/提示/列表竖排（与 widget_content_layout 同类结构陷阱）。
 * 2. `ListView`（不是 RecyclerView）→ ArkUI `List`；本布局用 @BuilderParam 槽位承载，
 *    分隔线/滚动属列表控件内部；空态提示 `TextView#text` 与进度环由使用方按状态显示。
 * 3. `ProgressView` 是 Hippo 自绘无限旋转环（32dp，颜色取强调色）→ 未由 ui-widget 交付，
 *    暂用系统 `LoadingProgress`（32vp）+ TODO(ui-widget)。
 * 4. 外框 `wrap_content`：宽度由对话框内容决定，Stack 不设固定宽；只有上下 24dp 内边距。
 */

@Component
export struct ArchiveListDialogLayout {
  @Prop tip: string = '';
  @Prop tipColor: ResourceColor = '#DE000000';

  /** 三态开关（上游 setVisibility 切换；默认全隐藏，由 dialog 逻辑打开其中一个） */
  @Prop showProgress: boolean = false;
  @Prop showTip: boolean = false;

  @BuilderParam listBuilder: () => void = this.emptyList;

  @Builder
  emptyList() {
    // TODO(ui-widget): 列表实现（上游 ListView#list_view）
    Column().width('100%').height('100%')
  }

  build() {
    Stack() {
      Column() {
        this.listBuilder();
      }
      .width('100%')
      .height('100%')

      // TODO(ui-widget): com.hippo.widget.ProgressView（自绘无限旋转环，32dp）
      LoadingProgress()
        .width(32)
        .height(32)
        .visibility(this.showProgress ? Visibility.Visible : Visibility.None)
        .align(Alignment.Center)

      Text(this.tip)
        .fontSize($r('app.float.text_medium'))
        .fontColor(this.tipColor)
        .textAlign(TextAlign.Center)
        .visibility(this.showTip ? Visibility.Visible : Visibility.None)
        .align(Alignment.Center)
    }
    .padding({ top: 24, bottom: 24 })
  }
}
