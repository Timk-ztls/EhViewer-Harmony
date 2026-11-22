/*
 * 上游：app/src/main/res/layout/item_gallery_comment_progress.xml（inventory S0614，上游 28 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/item_gallery_comment_progress.ets
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                     ArkUI
 * FrameLayout                                  Stack
 *   padding=@dimen/keyline_margin（16dp）        .padding($r('app.float.keyline_margin'))
 * com.hippo.widget.ProgressView#progress       LoadingProgress（临时对位，见「无法等价」1）
 *   style=@style/ProgressView                    TODO(ui-widget) ProgressView
 *   layout_gravity=center                        .align(Alignment.Center)
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. 上游 `com.hippo.widget.ProgressView` 是 Hippo 自绘的**无限旋转进度环**
 *    （`app/src/main/java/com/hippo/widget/ProgressView.java`，自定义 Drawable 动画，
 *    颜色取自 `?attr/colorAccent`、尺寸 32dp）。ui-widget 尚未交付该控件 →
 *    按铁律"依赖未交付就 import + TODO(模块)"：此处用系统 `LoadingProgress` 占位，
 *    尺寸按上游 ProgressView 的 32dp 固定，并标 TODO(ui-widget)；
 *    交付后改为 import 其 ProgressView 组件一行替换（路径见 ui-widget 交付时的 widget 目录）。
 * 2. 上游 `style="@style/ProgressView"` 只设 width/height=32dp 与 indeterminate=true，
 *    其余走默认 → 占位组件保持 32x32vp 与独立居中，不引入额外间距。
 * 3. 点击/加载完成回调都不在布局层（上游由 Adapter 处理）。
 */

@Component
export struct GalleryCommentProgressItemLayout {
  /** 上游 ProgressView 固定 32dp（style/@style/ProgressView） */
  @Prop progressSize: number = 32;

  build() {
    Stack() {
      // TODO(ui-widget): 上游 com.hippo.widget.ProgressView 交付后替换为自绘进度环
      LoadingProgress()
        .width(this.progressSize)
        .height(this.progressSize)
    }
    .width('100%')
    .padding($r('app.float.keyline_margin'))
    .alignContent(Alignment.Center)
  }
}

