/*
 * 上游：app/src/main/res/layout/item_gallery_comment_more.xml（inventory S0613，上游 28 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/item_gallery_comment_more.ets
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                 ArkUI
 * FrameLayout                              Stack
 *   padding=@dimen/keyline_margin（16dp）    .padding($r('app.float.keyline_margin'))
 * TextView#click_more_comments             Text
 *   layout_gravity=center                    .align(Alignment.Center)
 *   text=@string/click_more_comments         .text($r('app.string.click_more_comments'))
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. FrameLayout 的 `layout_gravity="center"` → Stack 的 `.align(Alignment.CENTER)`，
 *    语义一致（子元素在父容器内居中，不改变父容器尺寸 = wrap_content）。
 * 2. 文本来自资源 `@string/click_more_comments`，已由 ui-widget 迁入
 *    `resources/base/element/strings.json`（值 "Click to load more comments"），
 *    这里用 `$r('app.string.click_more_comments')` 直接引用，不硬编码文案（保证多语言）。
 * 3. 上游未设 textColor/textSize → 沿用主题默认（@Prop 保留注入位）。
 * 4. 点击行为不在布局内（上游由 Adapter 的 onClick 绑到 R.id.click_more_comments），
 *    ArkUI 侧由使用方给本组件套 `.onClick()`。
 */

@Component
export struct GalleryCommentMoreItemLayout {
  @Prop fontSize: number = 16;
  @Prop textColor: ResourceColor = '#DE000000';

  build() {
    Stack() {
      Text($r('app.string.click_more_comments'))
        .fontSize(this.fontSize)
        .fontColor(this.textColor)
    }
    .width('100%')
    .padding($r('app.float.keyline_margin'))
    .alignContent(Alignment.Center)
  }
}
