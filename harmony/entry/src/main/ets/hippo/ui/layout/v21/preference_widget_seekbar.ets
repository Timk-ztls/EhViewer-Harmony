/*
 * 上游：app/src/main/res/layout-v21/preference_widget_seekbar.xml（inventory S0685，上游 68 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/v21/preference_widget_seekbar.ets
 *
 * 与 base（`layout/preference_widget_seekbar.ets`，S0644）的**四处差异**（v21 才是现代设备生效的那份）：
 *   1. `paddingTop/Bottom = 16dp`（base 是 6dp）
 *   2. title 用 `?android:textAppearanceListItem`（base 是 textAppearanceMedium）
 *   3. summary 用 `?android:textAppearanceListItemSecondary`（base 是 textAppearanceSmall）
 *   4. 外层多了 `clipToPadding=false`；`paddingLeft/Right` 改用 `?android:listPreferredItemPadding*`
 *
 * ── 结构对照（RelativeLayout 的相对约束 → RelativeContainer 的 alignRules） ──
 * Android                                     ArkUI
 * LinearLayout(horizontal)                     Row
 *   minHeight=?attr/listPreferredItemHeightSmall   .constraintSize({minHeight:48})
 *   gravity=center_vertical                      .alignItems(VerticalAlign.Center)
 *   paddingLeft/Right=?android:listPreferredItemPadding*(16)  .padding({left:16,right:16})
 *   background=?android:activatedBackgroundIndicator          @Prop activated
 * RelativeLayout(0dp, weight=1)                RelativeContainer().layoutWeight(1)
 *   paddingTop/Bottom=16dp                        .padding({top:16,bottom:16})
 *   TextView#title（@android:id/title）           Text#title：父左上
 *     singleLine / ellipsize=marquee               .maxLines(1) + TextOverflow.MARQUEE
 *     textAppearanceListItem(18sp)                 .fontSize($r('app.float.text_medium'))
 *   TextView#summary（below=title, alignLeft=title） Text#summary
 *     textAppearanceListItemSecondary(14sp)+secondary  left→title.Start, top→title.Bottom
 *     maxLines=10                                   .maxLines(10)
 *   LinearLayout#widget_frame(wrap, match 高)      Column#widgetFrame
 *     below=summary / alignLeft=title               left→title.Start, top→summary.Bottom
 *     minWidth=@dimen/preference_widget_width(48)   .constraintSize({minWidth:48})
 *     gravity=center                                .justifyContent(FlexAlign.Center)
 *   SeekBar#seekbar(match 宽)                      Slider#seekbar
 *     below=summary / toRightOf=widget_frame        left→widgetFrame.End, top→summary.Bottom
 *     alignParentRight=true                         right→__container__.End
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `toRightOf` + `alignParentRight` 同时存在 → RelativeContainer 用 **left+right 双锚**：
 *    左贴 widget_frame、右贴容器。这比写 `width('100%')` 更准确 —— 上游 match_parent 宽度
 *    实际是从 widget_frame 右侧量到父右边。
 * 2. `clipToPadding=false`：ArkUI 的容器默认不把子元素裁剪到 padding 内，语义等价，无需设置。
 * 3. `@android:id/*` 是 **framework 约定 id**（title/summary/widget_frame），不是业务 id ——
 *    本组件保留同名 @Prop，供 Preference 等价层注入。
 * 4. `?android:attr/*`（textAppearance* / textColorSecondary / activatedBackgroundIndicator /
 *    listPreferredItemPadding*）全部无 ArkUI attr → @Prop 注入。
 * 5. 生成器对该文件的初版**丢了全部 alignRules 与 layoutWeight**；本文件已手写补齐，
 *    并据此修了转换脚本的第 7/8 号缺陷（`@android:id/*` 未识别、容器 `layout_weight` 只登记不生成）。
 */

@Component
export struct PreferenceWidgetSeekbarV21Layout {
  @Prop title: string = '';
  @Prop summary: string = '';
  @Prop value: number = 0;
  @Prop min: number = 0;
  @Prop max: number = 100;

  /** 上游 ?android:attr/activatedBackgroundIndicator */
  @Prop activated: boolean = false;
  @Prop activatedColor: ResourceColor = '#1F6200EE';
  @Prop titleColor: ResourceColor = '#DE000000';
  @Prop summaryColor: ResourceColor = '#8A000000';
  /** 上游 ?android:attr/listPreferredItemPaddingLeft/Right（Material 16dp） */
  @Prop itemPaddingSide: number = 16;
  /** 上游 @dimen/preference_widget_width */
  @Prop widgetWidth: number = 48;
  /** 上游 ?android:attr/listPreferredItemHeightSmall（48dp） */
  @Prop minHeight: number = 48;

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
      Column({ space: 4 }) {
        Text(this.title)
          .id('title')
          .fontSize($r('app.float.text_medium'))
          .fontColor(this.titleColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.MARQUEE })

        Text(this.summary)
          .id('summary')
          .fontSize($r('app.float.text_small'))
          .fontColor(this.summaryColor)
          .maxLines(10)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row() {
          Column() {
            this.widgetBuilder();
          }
          .id('widgetFrame')
          .constraintSize({ minWidth: this.widgetWidth })
          .justifyContent(FlexAlign.Center)

          Slider({ value: this.value, min: this.min, max: this.max, step: 1 })
            .id('seekbar')
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
      .alignItems(HorizontalAlign.Start)
      .padding({ top: 16, bottom: 16 })
    }
    .width('100%')
    .constraintSize({ minHeight: this.minHeight })
    .padding({ left: this.itemPaddingSide, right: this.itemPaddingSide })
    .backgroundColor(this.activated ? this.activatedColor : Color.Transparent)
    .alignItems(VerticalAlign.Center)
  }
}

