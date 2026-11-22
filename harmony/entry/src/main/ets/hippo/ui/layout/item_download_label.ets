/*
 * 上游：app/src/main/res/layout/item_download_label.xml（inventory S0607，上游 64 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/item_download_label.ets
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                          ArkUI
 * FrameLayout(clipChildren=false)                   Stack
 * ShadowLinearLayout#swipe_handler                  SwipeHandlerShadow（共用等价层）
 *   orientation=vertical                              Column
 *   background=?attr/contentColorPrimary              containerColor 注入
 *   LinearLayout(horizontal)                          Row
 *     ImageView#delete 48x48 padding 12               @BuilderParam deleteIconBuilder（默认 VDeleteX24）
 *     TextView#label 0x48 weight=1                    Text（.layoutWeight(1)，height 48）
 *       paddingLeft/Right=16dp                          .padding({left:16,right:16})
 *       gravity=center_vertical                         Row.alignItems(Center)
 *       singleLine / ellipsize=end                      .maxLines(1) + TextOverflow.Ellipsis
 *       textSize=@dimen/text_little_small(16sp)         .fontSize($r('app.float.text_little_small'))
 *       textColor=?android:attr/textColorPrimary        .fontColor(textColor)
 *     ImageView#drag_handler 48x48 padding 12         @BuilderParam dragIconBuilder（默认 VReorderX24）
 *   View 1dp / ?attr/dividerColor                     Divider().strokeWidth(1)
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. 两个 ImageView 都是 48dp 容器 + 12dp padding（图标实际 24dp）；
 *    ArkUI 用 48x48 容器 + 内部图标，与 item_blacklist 的图标栅格一致。
 * 2. `@dimen/text_little_small` 已迁为 `app.float.text_little_small`(16fp)，直接 `$r` 引用。
 * 3. `?attr/contentColorPrimary` / `?attr/dividerColor` 无 attr → @Prop 注入（默认白 / #1F000000）。
 * 4. 拖拽与删除是手势/回调（上游 ItemTouchHelper + 点击），不在布局层。
 */

import { SwipeHandlerShadow } from './support/SwipeHandlerShadow';
import { VDeleteX24 } from '../drawable/v_delete_x24';
import { VReorderX24 } from '../drawable/v_reorder_x24';

@Component
export struct DownloadLabelItemLayout {
  @Prop label: string = '';
  @Prop textColor: ResourceColor = '#DE000000';
  @Prop containerColor: ResourceColor = '#FFFFFFFF';
  @Prop dividerColor: ResourceColor = '#1F000000';
  @Prop showDefaultDragIcon: boolean = true;
  onLabelClick: () => void = (): void => {};

  /** 左侧删除图标（上游 R.id.delete，默认 @drawable/v_delete_x24） */
  @BuilderParam deleteIconBuilder: () => void = this.defaultDeleteIcon;
  /** 右侧拖拽手柄（上游 R.id.drag_handler，默认 @drawable/v_reorder_x24） */
  @BuilderParam dragIconBuilder: () => void = this.defaultDragIcon;
  /** 可选附加操作区（如重命名/排序图标，置于分隔线之上） */
  @BuilderParam trailingActionsBuilder: () => void = this.emptyTrailingSlot;

  @Builder
  defaultDeleteIcon() {
    VDeleteX24()
  }

  @Builder
  defaultDragIcon() {
    VReorderX24()
  }

  @Builder
  emptyTrailingSlot() {
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
              .id('downloadLabelText')
              .fontSize($r('app.float.text_little_small'))
              .fontColor(this.textColor)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
              .height(48)
              .padding({ left: 16, right: 16 })
              .onClick((): void => {
                this.onLabelClick();
              })

            this.trailingActionsBuilder();

            if (this.showDefaultDragIcon) {
              Column() {
                this.dragIconBuilder();
              }
              .width(48)
              .height(48)
              .padding(12)
              .justifyContent(FlexAlign.Center)
            }
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
