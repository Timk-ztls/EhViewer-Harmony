/*
 * 上游：app/src/main/res/layout/notification_contentview.xml（inventory S0638，上游 73 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/notification_contentview.ets
 *
 * 背景：下载通知的**自定义 RemoteViews** 内容（300dp 宽卡片）：标题 + 详情列 + 右侧环形进度。
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                  ArkUI
 * LinearLayout(vertical)                    Column
 *   layout_width=**300dp**（固定）            .width(300)（见 1）
 *   paddingTop/Bottom=20dp                   .padding({top:20,bottom:20})
 *   paddingLeft/Right=14dp                   .padding({left:14,right:14})
 * TextView#download_name（CardTitle）       Text：text_medium(18fp) + 居中 + maxLines 5
 *   gravity=center / maxLines=5                .textAlign(Center) + .maxLines(5)
 * FrameLayout(match × wrap)                  Stack（叠放：详情列 + 居中进度）
 *   LinearLayout#download_detail(vertical)   Column
 *     TextView#download_path（CardMessageMultipleLines） Text：text_small + 多行
 *     TextView#download_state（CardMessage）             Text：text_small + 单行
 *     LinearLayout(horizontal)               Row
 *       Button#leader（wrap）                  Button：文字由业务给（见 2）
 *       View(1dp, weight=1)                    Row().layoutWeight(1) 撑开（见 3）
 *       Button#action（wrap）                  Button
 *   FrameLayout#progress_view（居中）        Stack().align(Alignment.Center)
 *     com.hippo.widget.ProgressView 70×70      LoadingProgress 70 + TODO(ui-widget)
 *     TextView#download_progress（CardTitle,   Text：text_little_large(20fp) 居中
 *       textSize=@dimen/text_little_large）
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. 上游是 **RemoteViews 布局**（系统通知栏里渲染）：ArkUI 侧没有"通知自定义内容"的等价物，
 *    鸿蒙的通知由 `@ohos.notificationManager` 提供固定模板（不能塞任意布局）。
 *    因此本组件是**内容外观的等价物**（可用于应用内的"下载中"卡片，或作为通知模板的参数来源），
 *    不能真的当 RemoteViews 用 —— 这是本文件最重要的差异，**不是实现缺失**。
 * 2. 两个 Button **都没有 text**（上游由代码 setText 按状态切换"暂停/继续/重试"）→
 *    本组件用 @Prop leaderText/actionText，空串时不显示文字（与上游一致）。
 * 3. 中间的 `View(1dp, weight=1)` 是**撑开占位**（把两个按钮推到两端）→ ArkUI 用
 *    `Row().layoutWeight(1)`；注意它不是 1dp 宽的线（那是 layout_weight 的占位效果），
 *    **不要**画成 Divider。
 * 4. `FrameLayout` 里"详情列"与"进度环"是**叠放**（进度环居中压在详情上）→ 必须 Stack；
 *    写成 Row/Column 会把进度环挤到旁边（与 item_download#actions、widget_content_layout 同类）。
 * 5. `CardMessageMultipleLines` = text_small 多行（不省略）；`CardMessage` = text_small 单行。
 * 6. `ProgressView`（Hippo 自绘环）未交付 → LoadingProgress 70×70 + TODO(ui-widget)；
 *    环内文字 download_progress 是**独立 TextView**（不是控件内属性）。
 */

@Component
export struct NotificationContentviewLayout {
  @Prop downloadName: string = '';
  @Prop downloadPath: string = '';
  @Prop downloadState: string = '';
  @Prop downloadProgress: string = '';
  @Prop leaderText: string = '';
  @Prop actionText: string = '';
  @Prop textColor: ResourceColor = '#DE000000';
  @Prop messageColor: ResourceColor = '#8A000000';
  /** 上游 showProgressView（详情列 vs 进度环 二选一显示） */
  @Prop showProgressView: boolean = false;

  onLeaderClick: () => void = () => {
    // 默认空实现：使用方注入
  };
  onActionClick: () => void = () => {
    // 默认空实现：使用方注入
  };

  build() {
    Column() {
      Text(this.downloadName)
        .fontSize($r('app.float.text_medium'))
        .fontColor(this.textColor)
        .textAlign(TextAlign.Center)
        .maxLines(5)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Stack() {
        // 详情列（上游 download_detail）
        Column() {
          Text(this.downloadPath)
            .fontSize($r('app.float.text_small'))
            .fontColor(this.messageColor)
            .maxLines(3)
            .visibility(this.showProgressView ? Visibility.None : Visibility.Visible)
            .width('100%')

          Text(this.downloadState)
            .fontSize($r('app.float.text_small'))
            .fontColor(this.messageColor)
            .maxLines(1)
            .visibility(this.showProgressView ? Visibility.None : Visibility.Visible)
            .width('100%')

          Row() {
            Button(this.leaderText)
              .visibility(this.showProgressView ? Visibility.None : Visibility.Visible)
              .onClick(() => {
                this.onLeaderClick();
              })

            // 撑开占位（上游 View 1dp + weight=1，**不是**分隔线）
            Row().layoutWeight(1)

            Button(this.actionText)
              .visibility(this.showProgressView ? Visibility.None : Visibility.Visible)
              .onClick(() => {
                this.onActionClick();
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        // 环形进度（居中压在详情上；上游 FrameLayout#progress_view）
        Stack() {
          // TODO(ui-widget): com.hippo.widget.ProgressView（自绘环，70×70）
          LoadingProgress()
            .width(70)
            .height(70)

          Text(this.downloadProgress)
            .fontSize($r('app.float.text_little_large'))
            .fontColor(this.textColor)
            .textAlign(TextAlign.Center)
        }
        .visibility(this.showProgressView ? Visibility.Visible : Visibility.None)
        .align(Alignment.Center)
      }
      .width('100%')
    }
    .width(300)
    .padding({ top: 20, bottom: 20, left: 14, right: 14 })
    .alignItems(HorizontalAlign.Start)
  }
}
