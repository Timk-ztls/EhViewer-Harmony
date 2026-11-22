/*
 * 上游：app/src/main/res/layout/limits_count_main.xml（inventory S0635，上游 128 行 —— 零散组最大）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/limits_count_main.ets
 *
 * 背景：首页顶部的额度条：6 个"飘出"的说明条（默认 gone + alpha 0，动画时从下往上飘）
 * + 一条常驻的额度计数（可点刷新，右侧刷新图标 / 转圈二选一）。
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                  ArkUI
 * LinearLayout(vertical)                    Column
 *   maxHeight=**250dp**                      .constraintSize({maxHeight:250})（见 1）
 *   color=?android:navigationBarColor        → 容器色（见 2，实际只影响无障碍/绘制底色）
 * TextView × 5（from_gallery / from_torrent / from_download / from_hentai / current_power）
 *   match × **24dp** 固定高                   .width('100%').height(24)
 *   marginHorizontal=@dimen/limits_home_item_margin_h(30dp)  .margin({left:30,right:30})
 *   marginVertical=@dimen/limits_layout_margin_v(2dp)        .margin({top:2,bottom:2})
 *   alpha=**0** / visibility=**gone**         @Prop 逐条控制（见 3）
 *   background=@drawable/home_item_shape      圆角底色（见 4）
 *   gravity=center / textAlignment=center     .textAlign(TextAlign.Center)
 *   translationZ=-50dp（后 4 条）              → 见 5
 * TextView#reset_limits（同尺寸，额外 paddingHorizontal=@dimen/limits_layout_padding(12dp)）
 * FrameLayout#limits_view（36dp 高）         Stack().height(36)
 *   marginHorizontal=@dimen/limits_layout_padding(12dp)  .margin({left:12,right:12})
 *   background=@drawable/limits_shape          圆角底（见 4）
 *   paddingHorizontal=@dimen/limits_layout_margin_h(24dp) .padding({left:24,right:24})
 * TextView#limits_count（match，minHeight=48dp, 文本 "\????/????"） Text（见 6）
 *   clickable/focusable=true                    .onClick 由使用方给
 * ImageView#refresh_icon（24×24, end|center_vertical） VRefreshDarkX24 + .align(Alignment.End)
 * SpinKitView#refreshing（18×18, gone, CubeGrid）     @BuilderParam / @Prop refreshing（见 7）
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `maxHeight=250dp` 是**上限**（6 条 24dp + 边距 ≈ 6*(24+4)=168 < 250，正常不触顶）→
 *    ArkUI `constraintSize({maxHeight:250})`。
 * 2. `android:color` 在 LinearLayout 上**不是背景色**（它是 View 的 color 属性，只影响
 *    某些绘制如 foreground/滚动条）→ ArkUI 无对位，**不设 backgroundColor**（设了会与上游不一致）。
 * 3. 6 个说明条的 `alpha=0 + visibility=gone` 是**动画初始态**（上游用它们做"飘入"提示）：
 *    ArkUI 侧保留 alpha(@Prop opacity) + visibility 两个维度，由使用方做动画；
 *    **不要**因为"看不见"就省略这些节点（它们是动画的载体）。
 * 4. `@drawable/home_item_shape` / `@drawable/limits_shape` 都是 shape drawable（圆角 + 填充）：
 *    ArkUI 用 `.borderRadius(...)` + `.backgroundColor(...)` 近似（半径/填充色 @Prop 注入）。
 * 5. `translationZ=-50dp`（Z 轴位移，制造"沉在下面"的视觉）→ ArkUI 无 translationZ，
 *    可用 `.translate({z: -50})` 近似；但**默认不设**（上游值是配合动画的，静态渲染无影响），
 *    仅在需要复刻动画时由使用方加 —— 差异登记。
 * 6. `limits_count` 的文本 `"\????/????"` 是**占位**（问号转义，运行期被代码替换为
 *    "已用/总量"），不是真实文案 → ArkUI 侧用 @Prop countText，默认同样的占位串。
 *    另：`minHeight=48dp` 而父容器只有 36dp 高（上游如此，让点击热区大于视觉高度）→ 照原值。
 * 7. `SpinKitView`（第三方 spinkit 的 CubeGrid 动画）未交付 → @Prop refreshing 时用
 *    `LoadingProgress` 18×18 占位 + TODO(ui-widget)；它与 refresh_icon **同一位置互斥显示**。
 */

import { VRefreshDarkX24 } from '../drawable/v_refresh_dark_x24';

@Component
export struct LimitsCountMainLayout {
  // ---- 6 个飘出说明条的文案与显示状态（上游 alpha=0 + gone，动画时打开） ----
  @Prop showFromGallery: boolean = false;
  @Prop showFromTorrent: boolean = false;
  @Prop showFromDownload: boolean = false;
  @Prop showFromHentai: boolean = false;
  @Prop showCurrentPower: boolean = false;
  @Prop showResetLimits: boolean = false;
  /** 6 条的透明度（上游 alpha=0 起始，动画中 0→1） */
  @Prop floatOpacity: number = 0;

  // ---- 常驻额度计数 ----
  @Prop countText: string = '\\????/????';
  @Prop refreshing: boolean = false;
  @Prop textColor: ResourceColor = '#DE000000';
  @Prop itemColor: ResourceColor = '#22FFFFFF';
  @Prop itemRadius: number = 4;
  @Prop barColor: ResourceColor = '#33FFFFFF';
  @Prop barRadius: number = 18;

  onRefreshClick: () => void = () => {
    // 默认空实现：使用方注入
  };

  /** 一条飘出说明条（数据参数化，避免 @Builder 传 builder 的坑） */
  @Builder
  floatItem(text: Resource, visible: boolean) {
    Text(text)
      .fontSize($r('app.float.text_small'))
      .fontColor(this.textColor)
      .textAlign(TextAlign.Center)
      .width('100%')
      .height(24)
      .opacity(this.floatOpacity)
      .visibility(visible ? Visibility.Visible : Visibility.None)
      .backgroundColor(this.itemColor)
      .borderRadius(this.itemRadius)
      .margin({
        left: $r('app.float.limits_home_item_margin_h'),
        right: $r('app.float.limits_home_item_margin_h'),
        top: $r('app.float.limits_layout_margin_v'),
        bottom: $r('app.float.limits_layout_margin_v')
      })
  }

  build() {
    Column() {
      this.floatItem($r('app.string.from_gallery_visits'), this.showFromGallery);
      this.floatItem($r('app.string.from_torrent_completions'), this.showFromTorrent);
      this.floatItem($r('app.string.from_archive_download'), this.showFromDownload);
      this.floatItem($r('app.string.from_hentai_home'), this.showFromHentai);
      this.floatItem($r('app.string.current_moderation_power'), this.showCurrentPower);

      // reset_limits：同尺寸，额外 paddingHorizontal=@dimen/limits_layout_padding(12dp)
      Text($r('app.string.reset_cost'))
        .fontSize($r('app.float.text_small'))
        .fontColor(this.textColor)
        .textAlign(TextAlign.Center)
        .width('100%')
        .height(24)
        .opacity(this.floatOpacity)
        .visibility(this.showResetLimits ? Visibility.Visible : Visibility.None)
        .backgroundColor(this.itemColor)
        .borderRadius(this.itemRadius)
        .padding({ left: $r('app.float.limits_layout_padding'),
                   right: $r('app.float.limits_layout_padding') })
        .margin({
          left: $r('app.float.limits_home_item_margin_h'),
          right: $r('app.float.limits_home_item_margin_h'),
          top: $r('app.float.limits_layout_margin_v'),
          bottom: $r('app.float.limits_layout_margin_v')
        })

      // 常驻额度条（36dp 高，圆角底，左右 padding 24）
      Stack() {
        Text(this.countText)
          .fontSize($r('app.float.text_small'))
          .fontColor(this.textColor)
          .textAlign(TextAlign.Center)
          .width('100%')
          .constraintSize({ minHeight: 48 })
          .align(Alignment.Center)
          .onClick(() => {
            this.onRefreshClick();
          })

        // 刷新图标（24×24，右端垂直居中）
        Column() {
          VRefreshDarkX24()
        }
        .width(24)
        .height(24)
        .visibility(this.refreshing ? Visibility.None : Visibility.Visible)
        .align(Alignment.End)

        // TODO(ui-widget): com.github.ybq.android.spinkit.SpinKitView（CubeGrid）
        LoadingProgress()
          .width(18)
          .height(18)
          .visibility(this.refreshing ? Visibility.Visible : Visibility.None)
          .align(Alignment.End)
      }
      .width('100%')
      .height(36)
      .padding({ left: $r('app.float.limits_layout_margin_h'),
                 right: $r('app.float.limits_layout_margin_h') })
      .margin({ left: $r('app.float.limits_layout_padding'),
                right: $r('app.float.limits_layout_padding') })
      .backgroundColor(this.barColor)
      .borderRadius(this.barRadius)
    }
    .width('100%')
    .constraintSize({ maxHeight: 250 })
    .alignItems(HorizontalAlign.Start)
  }
}

