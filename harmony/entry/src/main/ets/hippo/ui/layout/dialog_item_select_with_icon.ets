/*
 * 上游：app/src/main/res/layout/dialog_item_select_with_icon.xml（inventory S0578，上游 30 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/dialog_item_select_with_icon.ets
 *
 * 上游注释原文：本布局由 AlertDialog 在展示"带图标的列表项"时 inflate，作为单个 item 的 TextView。
 * 与 item_select_dialog（S0629）的唯一差别：**多了左侧 drawable + drawablePadding=16dp**。
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                       ArkUI
 * TextView#android.R.id.text1                    Text（+ 图标槽位）
 *   layout_width=match_parent                     .width('100%')
 *   minHeight=?android:attr/listPreferredItemHeightSmall(48dp)  .constraintSize({minHeight:48})
 *   textAppearance=?android:attr/textAppearanceListItemSmall(14sp)  .fontSize(14)
 *   textColor=?android:attr/textColorAlertDialogListItem            .fontColor(textColorPrimary)
 *   gravity=center_vertical                       Row.alignItems(Center)
 *   paddingLeft/Right=?attr/listPreferredItemPadding*(16dp)        .padding({left:16,right:16})
 *   drawablePadding=@dimen/keyline_margin(16dp)   图标与文字的间距（见 2）
 *   ellipsize=marquee                             .maxLines(1) + TextOverflow.MARQUEE
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `?android:attr` 与 `?attr/listPreferredItem*` 都是运行期主题属性，ArkUI 无解析 →
 *    默认取 Material 值（48dp / 14sp / 16dp），全部 @Prop 注入。
 * 2. `drawablePadding=16dp` 在 ArkUI 没有等价属性：用"图标 → 16vp 间隔 → 文本"的 Row 结构
 *    显式表达（图标由 `iconBuilder` 槽位注入，默认不占位，与上游未设 drawable 时一致）。
 * 3. `ellipsize=marquee` 的触发条件差异见 item_select_dialog（同一处理）。
 */

@Component
export struct ItemSelectWithIconDialogLayout {
  @Prop text: string = '';
  @Prop fontSize: number = 14;
  @Prop textColor: ResourceColor = '#DE000000';
  @Prop paddingLeft: number = 16;
  @Prop paddingRight: number = 16;
  @Prop minHeight: number = 48;
  /** 上游 drawablePadding=@dimen/keyline_margin(16dp) */
  @Prop drawablePadding: number = 16;

  /** 左侧图标（上游 TextView 的 compound drawable，运行期 setCompoundDrawables 注入） */
  @BuilderParam iconBuilder: () => void = this.emptyIcon;

  @Builder
  emptyIcon() {
    Row().width(0).height(0)
  }

  build() {
    Row() {
      Column() {
        this.iconBuilder();
      }
      .margin({ right: this.drawablePadding })

      Text(this.text)
        .fontSize(this.fontSize)
        .fontColor(this.textColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.MARQUEE })
        .layoutWeight(1)
    }
    .width('100%')
    .constraintSize({ minHeight: this.minHeight })
    .padding({ left: this.paddingLeft, right: this.paddingRight })
    .alignItems(VerticalAlign.Center)
  }
}
