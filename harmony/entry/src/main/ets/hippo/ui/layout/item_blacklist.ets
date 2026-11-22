/*
 * 上游：app/src/main/res/layout/item_blacklist.xml（inventory S0602，上游 57 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/item_blacklist.ets
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                          ArkUI
 * FrameLayout(clipChildren=false)                   Stack（ArkUI 默认不裁剪）
 * com.hippo.widget.ShadowLinearLayout#swipe_handler  SwipeHandlerShadow（共用等价层，见 support/）
 *   orientation=vertical                              → Column
 *   background=?attr/contentColorPrimary              → containerColor 注入
 *   LinearLayout(horizontal)                          Row
 *     ImageView#icon 48x48, padding 12                @BuilderParam iconBuilder（默认 VCopyX24）
 *       srcCompat=@drawable/v_copy_x24                → hippo/ui/drawable/v_copy_x24（已 ported）
 *     TextView#text 0x48, weight=1                    Text（.layoutWeight(1)，height 48）
 *       paddingLeft/Right=16dp                          .padding({left:16,right:16})
 *       gravity=center_vertical                         Row.alignItems(Center)
 *       singleLine / ellipsize=end                      .maxLines(1) + TextOverflow.Ellipsis
 *       textSize=@dimen/text_little_small(16sp)         .fontSize($r('app.float.text_little_small'))
 *       textColor=?android:attr/textColorPrimary         .fontColor(textColorPrimary)
 *   View 1dp, background=?attr/dividerColor            Divider().strokeWidth(1)
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `?attr/dividerColor` 未迁入 colors.json → @Prop dividerColor 注入（默认 '#1F000000'）。
 * 2. `ImageView` 的 `padding=12dp` + 固定 48dp：ArkUI 用 48x48 容器 + 内部 24x24 图标，
 *    等价于"图标四周 12dp 内边距"（48-12*2=24，与 v_copy_x24 的 24dp 栅格一致）。
 * 3. `ShadowLinearLayout` 的阴影由滑动驱动，静态态 alpha=0（见 support 组件的说明）。
 * 4. 删除/拖拽等手势不在布局层（上游由 ItemTouchHelper / 自定义手势处理）。
 */

import { SwipeHandlerShadow } from './support/SwipeHandlerShadow';
import { VCopyX24 } from '../drawable/v_copy_x24';

@Component
export struct BlacklistItemLayout {
  @Prop text: string = '';
  @Prop textColor: ResourceColor = '#DE000000';
  @Prop containerColor: ResourceColor = '#FFFFFFFF';
  @Prop dividerColor: ResourceColor = '#1F000000';

  /** 左侧图标（上游 R.id.icon，默认 @drawable/v_copy_x24） */
  @BuilderParam iconBuilder: () => void = this.defaultIcon;

  @Builder
  defaultIcon() {
    VCopyX24()
  }

  build() {
    Stack() {
      SwipeHandlerShadow({ containerColor: this.containerColor }) {
        Column() {
          Row() {
            Column() {
              this.iconBuilder();
            }
            .width(48)
            .height(48)
            .padding(12)
            .justifyContent(FlexAlign.Center)

            Text(this.text)
              .id('text')
              .fontSize($r('app.float.text_little_small'))
              .fontColor(this.textColor)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
              .height(48)
              .padding({ left: 16, right: 16 })
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
