/*
 * 上游：app/src/main/res/layout/preference_widget_seekbar.xml（inventory S0644，上游 68 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/preference_widget_seekbar.ets
 *
 * 背景：带 SeekBar 的 Preference 行（标题 + 摘要 + 占位 widget_frame + 滑杆）。
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                     ArkUI
 * LinearLayout(horizontal)                    Row
 *   minHeight=?android:attr/listPreferredItemHeight(48dp)  .constraintSize({minHeight:48})
 *   gravity=center_vertical                     .alignItems(VerticalAlign.Center)
 *   paddingLeft=@dimen/preference_item_padding_side(16dp)   .padding({left:16})
 *   paddingRight=?android:attr/scrollbarSize(4dp)           .padding({right:4})
 *   background=?android:attr/activatedBackgroundIndicator   @Prop（激活态高亮，见 2）
 * RelativeLayout(0dp, weight=1)                Column().layoutWeight(1)
 *   paddingRight=@dimen/preference_item_padding_inner(16dp) .padding({right:16})
 *   paddingTop/Bottom=6dp                        .padding({top:6,bottom:6})
 *   TextView#title                               Text：textAppearanceMedium(18fp)
 *     singleLine / ellipsize=marquee               .maxLines(1) + TextOverflow.MARQUEE
 *     fadingEdge=horizontal                        （见 3）
 *   TextView#summary                             Text：textAppearanceSmall(14fp) + textColorSecondary
 *     below=title / alignLeft=title                RelativeContainer 或 Column 顺序（见 4）
 *     maxLines=10                                  .maxLines(10)
 *   LinearLayout#widget_frame                    Column（widget 占位，见 5）
 *     below=summary / alignLeft=title              minWidth=preference_widget_width
 *     minWidth=@dimen/preference_widget_width(48dp) .constraintSize({minWidth:48})
 *     gravity=center                               .justifyContent(FlexAlign.Center)
 *   SeekBar#seekbar                              Slider
 *     below=summary / toRightOf=widget_frame       （与 widget_frame 同一行，见 5）
 *     alignParentRight / match_parent 宽            .layoutWeight(1)
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. 这是 Android Preference 框架的**标准行布局变体**（`android:id/title`/`summary`/`widget_frame`
 *    是框架约定的 id，不是业务 id）。ArkUI 侧没有 Preference 框架，因此本组件是"行外观"的
 *    等价物：title/summary 文案与 seekbar 值都由使用方注入。
 * 2. `?android:attr/activatedBackgroundIndicator`（选中/激活态高亮）无 ArkUI attr →
 *    @Prop activated + `.backgroundColor(activated ? highlight : Color.Transparent)`。
 * 3. `fadingEdge="horizontal"` + `ellipsize="marquee"`：跑马灯的**两端渐隐**在 ArkUI 无对位
 *    （`TextOverflow.MARQUEE` 只给滚动，不做渐隐蒙版）→ 差异登记。
 * 4. RelativeLayout 里 title → summary → (widget_frame | seekbar) 是**纵向链**，
 *    只有 widget_frame 与 seekbar 是**同一行的左右关系** → 用 Column 承载前两行，
 *    最后一行用 Row（widget_frame 定宽 + seekbar 占余）—— 不需要 RelativeContainer，
 *    结构更简单且约束更少。
 * 5. `widget_frame` 是"给 Preference 自己塞 widget 的位置"（本布局里被 seekbar 用掉了右侧）。
 *    ArkUI 侧保留同尺寸槽位（minWidth 48dp、居中），由使用方决定是否注入（@BuilderParam）。
 * 6. `SeekBar` → ArkUI `Slider`：上游没有 style，取系统默认；值/范围由 @Prop 注入。
 */

@Component
export struct PreferenceWidgetSeekbarLayout {
  @Prop title: string = '';
  @Prop summary: string = '';
  @Prop value: number = 0;
  @Prop min: number = 0;
  @Prop max: number = 100;
  /** 上游 ?android:attr/activatedBackgroundIndicator（激活态高亮） */
  @Prop activated: boolean = false;
  @Prop activatedColor: ResourceColor = '#1F6200EE';
  @Prop titleColor: ResourceColor = '#DE000000';
  @Prop summaryColor: ResourceColor = '#8A000000';
  @Prop paddingSide: number = 16;
  @Prop paddingInner: number = 16;
  @Prop paddingRight: number = 4;
  @Prop minHeight: number = 48;
  @Prop widgetWidth: number = 48;

  onValueChange: (value: number) => void = (value: number) => {
    // 默认空实现：使用方注入
  };

  /** widget_frame 槽位（上游给 Preference 自己塞控件的位置） */
  @BuilderParam widgetBuilder: () => void = this.emptyWidget;

  @Builder
  emptyWidget() {
    Row().width(0).height(0)
  }

  build() {
    Row() {
      Column() {
        Text(this.title)
          .fontSize($r('app.float.text_medium'))
          .fontColor(this.titleColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.MARQUEE })
          .width('100%')

        Text(this.summary)
          .fontSize($r('app.float.text_small'))
          .fontColor(this.summaryColor)
          .maxLines(10)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        // 末行：widget_frame（定宽居中）+ SeekBar（占余）
        Row() {
          Column() {
            this.widgetBuilder();
          }
          .constraintSize({ minWidth: this.widgetWidth })
          .justifyContent(FlexAlign.Center)

          Slider({ value: this.value, min: this.min, max: this.max, step: 1 })
            .layoutWeight(1)
            .onChange((value: number) => {
              this.value = value;
              this.onValueChange(value);
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .padding({ right: this.paddingInner, top: 6, bottom: 6 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .constraintSize({ minHeight: this.minHeight })
    .padding({ left: this.paddingSide, right: this.paddingRight })
    .backgroundColor(this.activated ? this.activatedColor : Color.Transparent)
    .alignItems(VerticalAlign.Center)
  }
}
