/*
 * 上游：app/src/main/res/layout/dialog_rate.xml（inventory S0581，上游 39 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/dialog_rate.ets
 *
 * 背景：评分对话框：一行说明文字 + 五星评分条。
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                  ArkUI
 * LinearLayout(vertical, match × match)     Column().width('100%').height('100%')
 *   paddingLeft/Right=16dp                    .padding({left:16,right:16})
 * TextView#rating_text（match 宽）          Text：text_little_small(16fp) + textColorPrimary
 *   marginBottom=16dp                         .margin({bottom:16})
 *   gravity=center_horizontal                 .textAlign(TextAlign.Center)
 * com.hippo.ehviewer.widget.GalleryRatingBar @BuilderParam ratingBarBuilder（见 1）
 *   wrap × wrap / layout_gravity=center_horizontal  .alignSelf(ItemAlign.Center)
 *   android:theme=@style/RatingBarTheme        见 2
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `GalleryRatingBar`（Hippo 自绘五角星评分条，支持半分/拖动）未由 ui-widget 交付 →
 *    按铁律：@BuilderParam 槽位 + TODO(ui-widget)，不伪造评分交互。
 *    ArkUI 内置 `Rating` 只能作视觉替身，且不支持上游的半星与"实时显示分数"行为，
 *    因此**不**用它冒充实现。
 * 2. `@style/RatingBarTheme` 只是给 RatingBar 的强调色主题 → 未交付前无意义，
 *    交付时由控件自己读主题，不在布局层复刻。
 * 3. 上游 padding 只有左右 16dp（无 top/bottom），高度 match_parent 由对话框撑开 ——
 *    按原样保留，不加额外间距（这是与 dialog_js_prompt 的 16dp 四周内边距的区别）。
 */

@Component
export struct RateDialogLayout {
  @Prop ratingText: string = '';
  @Prop textColor: ResourceColor = '#DE000000';

  /** 评分条（上游 GalleryRatingBar，ui-widget 交付后注入） */
  @BuilderParam ratingBarBuilder: () => void = this.emptyRatingBar;

  @Builder
  emptyRatingBar() {
    // TODO(ui-widget): com.hippo.ehviewer.widget.GalleryRatingBar（半星 + 拖动 + RatingBarTheme）
    Row().width(0).height(0)
  }

  build() {
    Column() {
      Text(this.ratingText)
        .fontSize($r('app.float.text_little_small'))
        .fontColor(this.textColor)
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ bottom: 16 })

      Column() {
        this.ratingBarBuilder();
      }
      .alignSelf(ItemAlign.Center)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16 })
    .alignItems(HorizontalAlign.Center)
  }
}
