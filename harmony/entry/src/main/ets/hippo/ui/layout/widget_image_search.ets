/*
 * 上游：app/src/main/res/layout/widget_image_search.xml（inventory S0680，上游 77 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/widget_image_search.ets
 *
 * 背景：图搜（上传图片搜索）的选项块：预览图 + 选择按钮 + 两行 CheckBox 选项。
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                       ArkUI
 * <merge>                                        见「无法等价」1（落 Column 容器）
 * com.hippo.widget.FixedAspectImageView#preview  @BuilderParam previewBuilder（见 2）
 *   maxWidth/maxHeight=@dimen/image_search_max_size(240dp)  容器 .constraintSize({maxWidth:240,maxHeight:240})
 *   adjustViewBounds=true / visibility=gone       .visibility(previewVisible)
 * Button#select_image（buttonBarButtonStyle）     Button：$r('app.string.select_image')
 *   gravity=center_horizontal                      .align 由父 Column 居中
 * TableLayout(match)                              Column（两行 Row，各占 1:1 权重）
 *   TableRow 1: CheckBox#search_uss(weight 1, checked=true) + CheckBox#search_osc(weight 1, false)
 *   TableRow 2: CheckBox#search_se(weight 1, false)        + Space(weight 1)
 *   marginBottom/Top + marginLeft/Right = @dimen/advance_search_table_item_margin(4dp)
 *                                                 → 每个格子 .padding(4) 等价（见 3）
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `<merge>` 根：宿主是图搜对话框里的 LinearLayout → ArkUI 落 Column 容器，无自带间距/背景。
 * 2. `FixedAspectImageView` 未由 ui-widget 交付 → @BuilderParam 槽位 + TODO(ui-widget)；
 *    `maxWidth/maxHeight=240dp` + `adjustViewBounds` 的语义是"按内容比例、最长边不超过 240"，
 *    ArkUI 用 `constraintSize({maxWidth:240,maxHeight:240})` + `objectFit(ImageFit.Contain)` 对位
 *    （控件未交付，故槽位容器先按此约束，注入的组件自行决定缩放）。
 * 3. TableLayout 的单元格边距：上游表格**没有单元格 padding**，靠每个 CheckBox 的
 *    marginBottom/Top/Left/Right=4dp 拉开 → ArkUI 用每个格子的 `.padding(4)` 达到同样的
 *    视觉间隔（4vp 双倍相邻即 8vp 间距，与上游 margin 相加的效果一致）。
 *    注意 checked 初值：search_uss=**true**、osc/se=false（上游 XML 写死）。
 * 4. `Space` 是纯占位（weight 1、无内容）→ ArkUI 用空 `Row().layoutWeight(1)`。
 * 5. `style="?attr/buttonBarButtonStyle"` 无 ArkUI attr → 用系统 Button 默认样式，
 *    文字走 `$r('app.string.select_image')`（已迁多语言资源）。
 * 6. CheckBox 的选中/文案由使用方绑定（上游在 ImageSearchDialog 里 setOnCheckedChangeListener）。
 */

@Component
export struct ImageSearchWidgetLayout {
  /** 预览图是否可见（上游 preview 默认 gone，选图后显示） */
  @Prop previewVisible: boolean = false;
  @Prop ussChecked: boolean = true;
  @Prop oscChecked: boolean = false;
  @Prop seChecked: boolean = false;

  /** 预览图（上游 FixedAspectImageView，ui-widget 交付后注入） */
  @BuilderParam previewBuilder: () => void = this.emptyPreview;

  @Builder
  emptyPreview() {
    // TODO(ui-widget): com.hippo.widget.FixedAspectImageView（maxWidth/maxHeight=240 / adjustViewBounds）
    Column()
      .constraintSize({ maxWidth: $r('app.float.image_search_max_size'),
                        maxHeight: $r('app.float.image_search_max_size') })
  }

  build() {
    Column() {
      Column() {
        this.previewBuilder();
      }
      .constraintSize({ maxWidth: $r('app.float.image_search_max_size'),
                        maxHeight: $r('app.float.image_search_max_size') })
      .visibility(this.previewVisible ? Visibility.Visible : Visibility.None)

      Button($r('app.string.select_image'))
        .alignSelf(ItemAlign.Center)

      // TableRow 1：search_uss / search_osc
      Row() {
        Row() {
          Checkbox({ name: 'search_uss' }).select(this.ussChecked)
          Text($r('app.string.search_uss')).fontSize($r('app.float.text_small'))
        }
        .layoutWeight(1)
        .padding($r('app.float.advance_search_table_item_margin'))

        Row() {
          Checkbox({ name: 'search_osc' }).select(this.oscChecked)
          Text($r('app.string.search_osc')).fontSize($r('app.float.text_small'))
        }
        .layoutWeight(1)
        .padding($r('app.float.advance_search_table_item_margin'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // TableRow 2：search_se + Space
      Row() {
        Row() {
          Checkbox({ name: 'search_se' }).select(this.seChecked)
          Text($r('app.string.search_se')).fontSize($r('app.float.text_small'))
        }
        .layoutWeight(1)
        .padding($r('app.float.advance_search_table_item_margin'))

        Row()
          .layoutWeight(1)
          .padding($r('app.float.advance_search_table_item_margin'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }
}
