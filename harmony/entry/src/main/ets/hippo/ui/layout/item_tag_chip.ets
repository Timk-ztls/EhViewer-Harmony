/*
 * 上游：app/src/main/res/layout/item_tag_chip.xml（inventory S0634，上游 26 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/item_tag_chip.ets
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                          ArkUI
 * CardView（match_parent / wrap_content，margin 8dp）  Stack + .margin(8)
 *   cardCornerRadius=20dp                              .borderRadius(20)
 *   cardElevation=0dp                                  .shadow 不设（elevation 0 = 无阴影）
 *   cardBackgroundColor=transparent                    .backgroundColor(Color.Transparent)
 * TextView#tv_tag_name                               Text
 *   background=@drawable/bg_tag_chip                   BgTagChip 组件（S0716 已 ported，直接 import）
 *   layout_width=match_parent                          .width('100%')
 *   gravity=center                                     .textAlign(TextAlign.Center)
 *   paddingStart/End=16dp, paddingTop/Bottom=10dp      .padding({left:16,right:16,top:10,bottom:10})
 *   textColor=#757575                                  .fontColor('#757575')
 *   textSize=14sp                                      .fontSize($r('app.float.text_small'))
 *   maxLines=1 / ellipsize=end                         .maxLines(1) + TextOverflow.Ellipsis
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. CardView 的 cornerRadius 与内部 drawable 的 20dp 圆角**重复**（上游两者都是 20dp），
 *    且 CardView 背景透明、drawable 自带白底+1dp 灰边 —— 圆角实际由 drawable 生效。
 *    鸿蒙侧同样把圆角交给 BgTagChip（drawable 等价物），Stack 只承担 margin。
 * 2. `cardElevation=0dp` → 不设 .shadow()（ArkUI 默认无阴影，语义一致）。
 * 3. BgTagChip 是 `@Component struct`，需要用 Stack 包一层让它铺满 Text 背后；
 *    其默认 boxWidth/boxHeight 为 '100%'，正好对上 match_parent 的 Text。
 */

import { BgTagChip } from '../drawable/bg_tag_chip';

@Component
export struct TagChipItemLayout {
  @Prop tagName: string = 'Tag Name';
  @Prop tagTextColor: ResourceColor = '#757575';

  build() {
    Stack() {
      BgTagChip()

      Text(this.tagName)
        .fontSize($r('app.float.text_small'))
        .fontColor(this.tagTextColor)
        .textAlign(TextAlign.Center)
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    }
    .width('100%')
    .margin(8)
    .borderRadius(20)
    .backgroundColor(Color.Transparent)
  }
}
