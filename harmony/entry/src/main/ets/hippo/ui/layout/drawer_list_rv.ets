/*
 * 上游：app/src/main/res/layout/drawer_list_rv.xml（inventory S0585，上游 50 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/drawer_list_rv.ets
 *
 * 背景：抽屉里的**单列表**页：顶部 Toolbar + 内容区（8dp 阴影 + 居中 tip + RecyclerView 叠放）。
 * 与 drawer_list（S0586，只有 ViewPager）是**两个不同布局**，不要混。
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                    ArkUI
 * LinearLayout(vertical, match × match)       Column
 * androidx.appcompat.widget.Toolbar          @BuilderParam toolbarBuilder（见 1）
 *   id=toolbar                                 —
 *   layout_height=?attr/actionBarSize(56dp)     .height(56)（见 2）
 *   background=?attr/toolbarColor               @Prop toolbarColor
 *   theme=ThemeOverlay.AppCompat.Dark.ActionBar  → 深色叠加主题（见 3）
 *   app:popupTheme=?attr/toolbarPopupTheme       → 弹窗主题（见 3）
 *   saveEnabled=false                            无对位（保存状态相关，ArkUI 不涉及）
 * FrameLayout(match × 0dp, weight=1)          Stack().layoutWeight(1)
 *   View（match × 8dp, @drawable/shadow_bottom） Column：8vp 高 + 顶部阴影（见 4）
 *   TextView#tip（wrap, layout_gravity=center）  Text：居中 + @Prop showTip（默认 gone→不占位）
 *   EasyRecyclerView#recycler_view_drawer       @BuilderParam listBuilder（见 5）
 *     match × match                               .width('100%').height('100%')
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `Toolbar`（ActionBar 的现代替代）在 ArkUI 无直接等价物：用 @BuilderParam 槽位，
 *    由使用方注入（ArkUI 的 Navigation/自定义标题栏）。**不伪造** Toolbar 的
 *    menu/overflow/logo 行为。
 * 2. `?attr/actionBarSize` = 56dp（Material）→ @Prop actionBarHeight 默认 56。
 * 3. `theme` / `popupTheme` 是 Android 的**主题叠加**机制（只影响该 View 子树）：
 *    ArkUI 没有主题继承子树的概念 → 无对位，差异登记（深色叠加只影响 Toolbar 内的文字/图标颜色，
 *    由注入的槽位自己决定）。
 * 4. `@drawable/shadow_bottom` 是"内容顶部 8dp 阴影条"（视觉上是内容被 Toolbar 压住的投影）：
 *    ArkUI 用 8vp 高的容器 + `linearGradient`/`shadow` 近似；上游是 9-patch/渐变 drawable，
 *    像素级不可等价 → 差异登记，默认用半透明渐变色块。
 * 5. `EasyRecyclerView` 未由 ui-widget 交付 → @BuilderParam + TODO(ui-widget)。
 * 6. 三个子元素在 FrameLayout 里**叠放**（阴影条压在最上、tip 居中、列表铺满）→ 必须 Stack。
 */

@Component
export struct DrawerListRvLayout {
  @Prop toolbarColor: ResourceColor = '#FF6200EE';
  @Prop showTip: boolean = false;
  @Prop tip: string = '';
  @Prop tipColor: ResourceColor = '#DE000000';
  /** 上游 ?attr/actionBarSize（Material 56dp） */
  @Prop actionBarHeight: number = 56;

  /** 顶部 Toolbar（上游 androidx Toolbar，ui-widget 交付后注入） */
  @BuilderParam toolbarBuilder: () => void = this.emptyToolbar;
  /** 列表（上游 EasyRecyclerView#recycler_view_drawer） */
  @BuilderParam listBuilder: () => void = this.emptyList;

  @Builder
  emptyToolbar() {
    // TODO(ui-widget): androidx.appcompat.widget.Toolbar 等价物（标题 + menu/overflow）
    Row().width('100%').height('100%')
  }

  @Builder
  emptyList() {
    // TODO(ui-widget): com.hippo.easyrecyclerview.EasyRecyclerView
    Column().width('100%').height('100%')
  }

  build() {
    Column() {
      // Toolbar（actionBarSize 高，主题色底）
      Column() {
        this.toolbarBuilder();
      }
      .width('100%')
      .height(this.actionBarHeight)
      .backgroundColor(this.toolbarColor)

      // 内容区（weight 1）：阴影条 / tip / 列表 三者叠放
      Stack() {
        Column() {
          this.listBuilder();
        }
        .width('100%')
        .height('100%')

        // 顶部 8dp 阴影条（上游 @drawable/shadow_bottom；渐变/9-patch 不可像素级等价）
        Column()
          .width('100%')
          .height(8)
          .linearGradient({
            angle: 180,
            colors: [['#33000000', 0.0], ['#00000000', 1.0]]
          })
          .align(Alignment.Top)

        Text(this.tip)
          .fontColor(this.tipColor)
          .visibility(this.showTip ? Visibility.Visible : Visibility.None)
          .align(Alignment.Center)
      }
      .width('100%')
      .layoutWeight(1)
      .alignContent(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
  }
}
