/*
 * 上游：app/src/main/res/layout/item_simple_list_2.xml（inventory S0631，上游 41 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/item_simple_list_2.ets
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                          ArkUI
 * LinearLayout(vertical)                            Column
 *   paddingLeft/Right=?attr/listPreferredItemPadding{Left,Right}(16dp)  .padding({left:16,right:16})
 *   paddingTop/Bottom=8dp                            .padding({top:8,bottom:8})
 * TextView#android.R.id.text1                       Text
 *   layout_marginBottom=4dp                           .margin({bottom:4})
 *   textSize=@dimen/text_little_small(16sp)           .fontSize($r('app.float.text_little_small'))
 *   textColor=?android:attr/textColorPrimary          .fontColor(textColorPrimary)
 *   textAppearance=?attr/textAppearanceListItemSmall  被显式 textSize 覆盖（见「无法等价」1）
 * TextView#android.R.id.text2                       Text
 *   textSize=@dimen/text_small(14sp)                  .fontSize($r('app.float.text_small'))
 *   textColor=?android:attr/textColorSecondary        .fontColor(textColorSecondary)
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. 两个 TextView 都同时写了 `textAppearance` 与 `textSize`：**显式 textSize 优先**，
 *    因此 text1=16sp、text2=14sp（不是 textAppearanceListItemSmall 的 14sp）。
 *    这是本文件最容易照抄错的地方，按"显式属性覆盖样式"的 Android 规则落到 16/14。
 * 2. `@dimen/text_little_small`(16sp) 与 `@dimen/text_small`(14sp) 都已由 ui-widget
 *    迁为 `app.float.*`，直接 `$r` 引用，不再写字面量。
 * 3. `?attr/listPreferredItemPaddingLeft|Right`（16dp）无 attr → @Prop 注入，默认 16。
 * 4. 两个文字都是 wrap_content（左对齐），不设 width('100%')，避免撑出父容器。
 */

@Component
export struct SimpleList2ItemLayout {
  @Prop text1: string = '';
  @Prop text2: string = '';

  // 主题注入位（上游 ?attr）
  @Prop textColorPrimary: ResourceColor = '#DE000000';
  @Prop textColorSecondary: ResourceColor = '#8A000000';
  @Prop paddingLeft: number = 16;
  @Prop paddingRight: number = 16;

  build() {
    Column() {
      Text(this.text1)
        .fontSize($r('app.float.text_little_small'))
        .fontColor(this.textColorPrimary)
        .margin({ bottom: 4 })

      Text(this.text2)
        .fontSize($r('app.float.text_small'))
        .fontColor(this.textColorSecondary)
    }
    .width('100%')
    .padding({ left: this.paddingLeft, right: this.paddingRight, top: 8, bottom: 8 })
    .alignItems(HorizontalAlign.Start)
  }
}
