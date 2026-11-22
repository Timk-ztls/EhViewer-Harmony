/*
 * 上游：app/src/main/res/layout/widget_content_layout.xml（inventory S0677，上游 57 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/widget_content_layout.ets
 *
 * 背景：这是列表页的**内容骨架**（加载中/空提示/内容 三态叠放），被 GalleryList、下载列表、
 * 收藏、历史等页面复用，故归 widget_ 组。
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                          ArkUI
 * <merge>（宿主是 FrameLayout）                      Stack（见「无法等价」1）
 * com.hippo.widget.ProgressView#progress            LoadingProgress + TODO(ui-widget)
 *   （wrap, layout_gravity=center, style=ProgressView）
 * TextView#tip（228dp 宽, gravity=center,          Text：.width(228) + textAlign Center
 *   drawablePadding=8, AppCompat.Medium）            + @BuilderParam tipBuilder（见 2）
 * FrameLayout#content_view（match_parent）          Stack（内容层，铺满）
 *   com.hippo.refreshlayout.RefreshLayout            TODO(ui-widget) → @BuilderParam
 *   com.hippo.easyrecyclerview.EasyRecyclerView      TODO(ui-widget) → 内容槽位
 *   com.hippo.easyrecyclerview.FastScroller#fast_scroller（30dp 宽 + 右对齐 + padding 20/4/8/8）
 *                                                    @BuilderParam fastScrollerBuilder
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `<merge>` 的宿主是 FrameLayout → 用 Stack 保留"三态叠放"语义：
 *    进度环居中、tip 居中、content 铺满（三者同一层，靠 visibility 切换）。
 *    若改成 Column 会把三态排开 —— 这是本文件最容易错的地方。
 * 2. `drawablePadding=8`（tip 文本左侧 drawable 与文字的间距）→ ArkUI 无 drawablePadding；
 *    用 @BuilderParam tipBuilder 让使用方自带图标+文本的组合，默认只渲染文本
 *    （TODO(ui-widget)：上游 tip 的 drawable 由代码 setCompoundDrawables 注入）。
 * 3. `RefreshLayout`（com.hippo.refreshlayout）与 `EasyRecyclerView`、`FastScroller`
 *    都未由 ui-widget 交付 → 全部保留 @BuilderParam 槽位 + TODO(ui-widget)；
 *    不写假实现（不伪造下拉刷新/快速滚动条行为）。
 * 4. `FastScroller` 的 30dp 宽 + padding(20,8,4,8) + 右对齐 → 槽位容器按此尺寸约束，
 *    实际绘制在控件内部（ui-widget 交付后注入）。
 * 5. `TextAppearance.AppCompat.Medium` = 18fp → 已迁资源 `app.float.text_medium`。
 */

@Component
export struct ContentLayoutWidgetLayout {
  @Prop tip: string = '';
  @Prop tipColor: ResourceColor = '#8A000000';

  /** 加载中（上游 ProgressView#progress，ui-widget 交付后注入） */
  @BuilderParam progressBuilder: () => void = this.defaultProgress;
  /** 空/错误提示的图文组合（上游 tip + drawablePadding=8） */
  @BuilderParam tipBuilder: () => void = this.defaultTip;
  /** 内容区（上游 RefreshLayout > EasyRecyclerView） */
  @BuilderParam contentBuilder: () => void = this.emptyContent;
  /** 快速滚动条（上游 FastScroller#fast_scroller） */
  @BuilderParam fastScrollerBuilder: () => void = this.emptyFastScroller;

  @Builder
  defaultProgress() {
    // TODO(ui-widget): com.hippo.widget.ProgressView（自绘无限旋转环，32dp）
    LoadingProgress().width(32).height(32)
  }

  @Builder
  defaultTip() {
    // TODO(ui-widget): 上游 tip 的左侧 drawable 由代码注入，drawablePadding=8
    Text(this.tip)
      .fontSize($r('app.float.text_medium'))
      .fontColor(this.tipColor)
      .width(228)
      .textAlign(TextAlign.Center)
  }

  @Builder
  emptyContent() {
    Column().width('100%').height('100%')
  }

  @Builder
  emptyFastScroller() {
    Column().width(0).height(0)
  }

  build() {
    Stack() {
      // 内容层（铺满，最底层）
      Stack() {
        this.contentBuilder();
      }
      .width('100%')
      .height('100%')
      .alignContent(Alignment.TopStart)

      // 快速滚动条（右对齐，宽度 30 + 内边距 20/4/8/8）
      Column() {
        this.fastScrollerBuilder();
      }
      .width(30)
      .height('100%')
      .padding({ left: 20, right: 4, top: 8, bottom: 8 })
      .align(Alignment.End)

      // 三态叠加：进度环居中
      Column() {
        this.progressBuilder();
      }
      .align(Alignment.Center)

      // 三态叠加：提示文案居中
      Column() {
        this.tipBuilder();
      }
      .align(Alignment.Center)
    }
    .width('100%')
    .height('100%')
  }
}
