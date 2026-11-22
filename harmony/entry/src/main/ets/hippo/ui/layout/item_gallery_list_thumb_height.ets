/*
 * 上游：app/src/main/res/layout/item_gallery_list_thumb_height.xml（inventory S0621，上游 52 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/item_gallery_list_thumb_height.ets
 *
 * 背景：item_gallery_list 的**右侧信息列**在 GridLayoutManager 需要一个"高度对齐缩略图"的
 * 变体（同名布局），故上游单独抽出这一份竖排文本块。
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                       ArkUI
 * LinearLayout(vertical)                         Column
 * TextView（style=CardTitle, marginTop=4, lines=2）  Text：text_medium(18fp) + 2 行省略
 * TextView（style=CardMessage, marginTop=2, lines=1）Text：text_small(14fp) + 1 行省略
 * com.hippo.ehviewer.widget.SimpleRatingView     @BuilderParam ratingBuilder（ui-widget 未交付）
 *   （marginTop=2）
 * TextView#category（CardMessage, marginTop=4/   Text：白字 + 8/2 padding + 1 行
 *   marginBottom=8, padding 8/2, white, allCaps, lines=1）
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `@style/CardTitle` / `@style/CardMessage` 在 ui-widget 的迁移里已落成
 *    `app.float.text_medium`(18fp) / `app.float.text_small`(14fp)，直接 `$r` 引用。
 * 2. `android:lines="N"` 与 `maxLines` 的区别：`lines` 固定显示行数（不足补空），
 *    ArkUI 无对应属性 → 用 `.maxLines(N)`（上限语义）；本布局两处都不依赖"补齐空行"，
 *    视觉一致（差异登记）。
 * 3. `textAllCaps="true"` ArkUI 无属性 → 与 item_gallery_list 一致，由数据侧 toUpperCase()
 *    保证（布局层不做 locale 相关变换）。
 * 4. `SimpleRatingView` 未由 ui-widget 交付 → @BuilderParam 槽位 + TODO(ui-widget)。
 * 5. 各子项 `layout_width=wrap_content`：在 Column 里保持内容撑开（不写 '100%'）。
 */

@Component
export struct GalleryListThumbHeightItemLayout {
  @Prop title: string = '';
  @Prop message: string = '';
  @Prop category: string = '';
  @Prop titleColor: ResourceColor = '#DE000000';
  @Prop messageColor: ResourceColor = '#8A000000';
  @Prop categoryTextColor: ResourceColor = Color.White;

  /** 评分控件（上游 SimpleRatingView，ui-widget 交付后注入） */
  @BuilderParam ratingBuilder: () => void = this.emptyRating;

  @Builder
  emptyRating() {
    // TODO(ui-widget): com.hippo.ehviewer.widget.SimpleRatingView
    Row().width(0).height(0)
  }

  build() {
    Column() {
      Text(this.title)
        .fontSize($r('app.float.text_medium'))
        .fontColor(this.titleColor)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 4 })

      Text(this.message)
        .fontSize($r('app.float.text_small'))
        .fontColor(this.messageColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 2 })

      Column() {
        this.ratingBuilder();
      }
      .margin({ top: 2 })

      Text(this.category)
        .fontSize($r('app.float.text_small'))
        .fontColor(this.categoryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 8, right: 8, top: 2, bottom: 2 })
        .margin({ top: 4, bottom: 8 })
    }
    .alignItems(HorizontalAlign.Start)
  }
}
