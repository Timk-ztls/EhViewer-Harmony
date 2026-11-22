/*
 * 上游：app/src/main/res/layout/widget_archiver_progress.xml（inventory S0675，上游 37 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/widget_archiver_progress.ets
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                  ArkUI
 * LinearLayout(vertical, marginLeft/Right=@dimen/progress_padding)  Column + .margin({left,right})
 *   LinearLayout(horizontal, gravity=center_vertical)               Row
 *     TextView#archiver_downloading（0dp, weight=1,          Text：.layoutWeight(1)
 *       text=@string/archiver_downloading,                    $r('app.string.archiver_downloading')
 *       textColor=?android:attr/textColorHighlight）          .fontColor(textColorHighlight)
 *     ImageButton#archiver_pause_resume（36dp, padding=6,     @BuilderParam
 *       padding 6, srcCompat=@drawable/v_pause_x24）           pauseButtonBuilder（默认 VPauseX24）
 *   ProgressBar#archiver_progress（Horizontal,              Progress({value,total})
 *     marginEnd=@dimen/keyline_margin, marginBottom=0）        .style(Linear? 见 2)
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `?android:attr/textColorHighlight` 无 ArkUI attr → @Prop 注入（默认 '#FF6200EE'，Material 强调色）。
 * 2. `@style/Widget.AppCompat.ProgressBar.Horizontal` 是**确定性**水平进度条（非无限旋转），
 *    ArkUI 用 `Progress({ value, total, type: ProgressType.Linear })` 对位；
 *    上游未设 progressTint → 默认强调色；高度由 style 决定（wrap_content ≈ 4dp），
 *    故 `.height(4)` 并把 `marginEnd` 用 `$r('app.float.keyline_margin')` 对位。
 * 3. `ImageButton` 的 `background=?attr/selectableItemBackgroundBorderless`（无界涟漪）
 *    无 ArkUI 对位 → 用 `.stateStyles` 近似的按下反馈（见 item_drawer_favorites 同一处理）。
 * 4. `@dimen/progress_padding` 已迁为 `app.float.progress_padding`(18vp)；`keyline_margin`(16vp) 同理。
 * 5. 暂停/恢复是行为（上游按状态切 v_pause_x24 / v_resume_x24 并调 Archiver），不在布局层：
 *    图标槽位 + 进度值都由使用方注入。
 */

import { ThemeDimens, ThemeTokens, ThemeTypography } from '../../../common/theme/ThemeTokens';
import { VCloseDarkX24 } from '../drawable/v_close_dark_x24';
import { VPauseX24 } from '../drawable/v_pause_x24';

@Component
export struct ArchiverProgressWidgetLayout {
  @Prop downloadingText: string = '';
  @Prop textColorHighlight: ResourceColor = '#FF6200EE';
  @Prop progressColor: ResourceColor = ThemeTokens.LIGHT.colorAccent;
  @Prop trackColor: ResourceColor = '#33FFFFFF';
  @Prop value: number = 0;
  @Prop total: number = 100;
  @Prop showCancel: boolean = false;

  /** 暂停/恢复按钮（上游 ImageButton#archiver_pause_resume） */
  @BuilderParam pauseButtonBuilder: () => void = this.defaultPauseButton;
  @BuilderParam cancelButtonBuilder: () => void = this.defaultCancelButton;

  @Builder
  defaultPauseButton() {
    VPauseX24()
  }

  @Builder
  defaultCancelButton() {
    VCloseDarkX24()
  }

  build() {
    Column() {
      Row({ space: 2 }) {
        Text(this.downloadingText.length > 0 ? this.downloadingText : $r('app.string.archiver_downloading'))
          .id('archiver_downloading')
          .fontSize(ThemeTypography.TEXT_SMALL)
          .fontColor(this.textColorHighlight)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        Column() {
          this.pauseButtonBuilder();
        }
        .width(32)
        .height(32)
        .padding(4)
        .justifyContent(FlexAlign.Center)
        .stateStyles({
          pressed: {
            .backgroundColor('#1F000000')
          },
          normal: {
            .backgroundColor(Color.Transparent)
          }
        })

        if (this.showCancel) {
          Column() {
            this.cancelButtonBuilder();
          }
          .width(32)
          .height(32)
          .padding(4)
          .justifyContent(FlexAlign.Center)
          .stateStyles({
            pressed: {
              .backgroundColor('#1F000000')
            },
            normal: {
              .backgroundColor(Color.Transparent)
            }
          })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Progress({ value: this.value, total: this.total, type: ProgressType.Linear })
        .width('100%')
        .height(4)
        .color(this.progressColor)
        .backgroundColor(this.trackColor)
        .style({ strokeWidth: 4, enableSmoothEffect: true })
        .margin({ top: 4 })
    }
    .width('100%')
    .padding({ left: ThemeDimens.KEYLINE_MARGIN, right: ThemeDimens.KEYLINE_MARGIN, top: 2, bottom: 10 })
    .alignItems(HorizontalAlign.Start)
  }
}
