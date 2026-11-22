/*
 * 上游：app/src/main/res/layout/item_subscription.xml（inventory S0633，上游 63 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/item_subscription.ets
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                       ArkUI
 * FrameLayout(clipChildren=false)                Stack
 * ShadowLinearLayout#swipe_handler               SwipeHandlerShadow（共用等价层）
 *   background=?attr/contentColorPrimary           containerColor 注入
 *   LinearLayout(horizontal)                       Row
 *     ImageView#delete 48x48 padding 12            @BuilderParam deleteIconBuilder（默认 VDeleteX24）
 *       srcCompat=@drawable/v_delete_x24
 *     TextView#label 0x48 weight=1                 Text（.layoutWeight(1)，height 48）
 *       paddingLeft/Right=16dp                       .padding({left:16,right:16})
 *       gravity=**center**（不是 center_vertical）    .textAlign(TextAlign.Center)（见 1）
 *       singleLine / ellipsize=end                   .maxLines(1) + Ellipsis
 *       textSize=@dimen/text_little_small(16sp)      .fontSize($r('app.float.text_little_small'))
 *     ImageView#drag_handler 48x48 padding 12      @BuilderParam dragIconBuilder（默认空，见 2）
 *       **无 srcCompat**（图标由代码 setImageDrawable 注入）
 *   View 1dp / ?attr/dividerColor                  Divider().strokeWidth(1)
 *
 * ── 与 item_download_label 的差别（不能直接复用） ───────────────────────────
 * 1. label 的 gravity 是 `center`（水平+垂直居中），item_download_label 是 `center_vertical`
 *    → 本文件单独实现，`textAlign(TextAlign.Center)` 对位。
 * 2. `drag_handler` 上游**没有** srcCompat：图标在运行期由代码按状态设置
 *    （可拖拽/不可拖拽两种图标）→ 默认槽位留空（0x0），由使用方注入。
 * 其余尺寸/颜色/结构完全一致。
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * - `?attr/contentColorPrimary` / `?attr/dividerColor` / `?android:attr/textColorPrimary`
 *   均无 ArkUI attr → @Prop 注入（默认白 / #1F000000 / #DE000000）。
 * - `@dimen/text_little_small` 已迁为 `app.float.text_little_small`，用 `$r` 引用。
 */

import { SwipeHandlerShadow } from './support/SwipeHandlerShadow';
import { VDeleteX24 } from '../drawable/v_delete_x24';

@Component
export struct SubscriptionItemLayout {
  @Prop label: string = '';
  @Prop textColor: ResourceColor = '#DE000000';
  @Prop containerColor: ResourceColor = '#FFFFFFFF';
  @Prop dividerColor: ResourceColor = '#1F000000';

  /** 左侧删除图标（上游 R.id.delete，默认 @drawable/v_delete_x24） */
  @BuilderParam deleteIconBuilder: () => void = this.defaultDeleteIcon;
  /** 右侧拖拽手柄（上游 R.id.drag_handler，无默认图标，由代码按状态注入） */
  @BuilderParam dragIconBuilder: () => void = this.emptyDragIcon;

  @Builder
  defaultDeleteIcon() {
    VDeleteX24()
  }

  @Builder
  emptyDragIcon() {
    Row().width(0).height(0)
  }

  build() {
    Stack() {
      SwipeHandlerShadow({ containerColor: this.containerColor }) {
        Column() {
          Row() {
            Column() {
              this.deleteIconBuilder();
            }
            .width(48)
            .height(48)
            .padding(12)
            .justifyContent(FlexAlign.Center)

            Text(this.label)
              .id('subscriptionLabelText')
              .fontSize($r('app.float.text_little_small'))
              .fontColor(this.textColor)
              .textAlign(TextAlign.Center)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
              .height(48)
              .padding({ left: 16, right: 16 })

            Column() {
              this.dragIconBuilder();
            }
            .width(48)
            .height(48)
            .padding(12)
            .justifyContent(FlexAlign.Center)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Divider()
            .strokeWidth(1)
            .color(this.dividerColor)
            .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
  }
}
