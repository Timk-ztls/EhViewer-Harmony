/*
 * 上游：app/src/main/res/layout/preference_dialog_task.xml（inventory S0642，上游 51 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/preference_dialog_task.ets
 *
 * 背景：后台任务对话框：一行"转圈 + 请稍候"，下方一条进度条（初始 gone）。
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                  ArkUI
 * LinearLayout(vertical, match × match)     Column().width('100%').height('100%')
 *   paddingLeft/Right=?attr/dialogPreferredPadding(24dp)   .padding({left:24,right:24})
 *   paddingTop/Bottom=@dimen/abc_dialog_padding_top_material(24dp) .padding({top:24,bottom:24})
 * LinearLayout(horizontal)                 Row
 *   com.hippo.widget.ProgressView          LoadingProgress + TODO(ui-widget)
 *     layout_gravity=center_vertical         Row.alignItems(VerticalAlign.Center)
 *   TextView（please_wait）                Text：$r('app.string.please_wait')
 *     layout_width=match_parent              .layoutWeight(1)
 * ProgressBar#task_progress                Progress({type: Linear})
 *   style=Widget.ProgressBar.Horizontal      （水平条）
 *   indeterminate=**true**                   → 上游是"不确定进度"的横条（见 2）
 *   visibility=gone                          @Prop showProgress（默认不占位）
 *   marginTop=16dp                           .margin({top:16})
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. 上方是 **ProgressView**（Hippo 自绘无限旋转环，32dp）→ 未交付，用 LoadingProgress 占位 +
 *    TODO(ui-widget)；它与下方 ProgressBar 是**两个不同控件**（一个转圈一个横条），不要合并。
 * 2. 下方 ProgressBar 虽然 style 是 Horizontal，但 `indeterminate="true"` —— 语义是
 *    "水平不确定进度条"（滚动条纹），不是确定百分比。ArkUI 没有"水平不确定"内置形态：
 *    用 `Progress({type: Linear})` 且**不绑定 value**（保持 0）作为静态占位，并在
 *    `@Prop indeterminate` 为真时由使用方换成自己的动画（差异登记：滚动条纹动画不可等价）。
 * 3. `visibility=gone` → `Visibility.None`（**不占位**）：任务开始前不预留高度。
 * 4. 上游无取消按钮（任务不可中断）—— 布局层不添加。
 */

@Component
export struct TaskDialogLayout {
  @Prop showProgress: boolean = false;
  @Prop value: number = 0;
  @Prop total: number = 100;
  @Prop textColor: ResourceColor = '#DE000000';
  @Prop dialogPreferredPadding: number = 24;
  @Prop dialogPaddingTop: number = 24;

  build() {
    Column() {
      Row() {
        // TODO(ui-widget): com.hippo.widget.ProgressView（自绘无限旋转环，32dp）
        LoadingProgress()
          .width(32)
          .height(32)

        Text($r('app.string.please_wait'))
          .fontColor(this.textColor)
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 水平进度条（上游 indeterminate=true：滚动条纹；ArkUI 无该形态，见「无法等价」2）
      Progress({ value: this.value, total: this.total, type: ProgressType.Linear })
        .width('100%')
        .margin({ top: 16 })
        .visibility(this.showProgress ? Visibility.Visible : Visibility.None)
    }
    .width('100%')
    .height('100%')
    .padding({
      left: this.dialogPreferredPadding,
      right: this.dialogPreferredPadding,
      top: this.dialogPaddingTop,
      bottom: this.dialogPaddingTop
    })
    .alignItems(HorizontalAlign.Start)
  }
}
