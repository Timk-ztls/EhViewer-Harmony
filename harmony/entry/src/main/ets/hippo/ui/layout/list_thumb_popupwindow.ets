/*
 * 上游：app/src/main/res/layout/list_thumb_popupwindow.xml（inventory S0636，上游 23 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/list_thumb_popupwindow.ets
 *
 * 背景：列表缩略图模式的标签选择弹窗：可滚动容器 + ChipGroup（多选、不换行限制）。
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                              ArkUI
 * LinearLayout(vertical)                Column
 *   background=?attr/popupWindowStyle     .backgroundColor(@Prop popupColor)
 *   match × match                         .width('100%').height('100%')
 * ScrollView(wrap 高)                   Scroll（见 1）
 *   com.google.android.material.chip.ChipGroup  Flex({ wrap: FlexWrap.Wrap })（见 2）
 *     id=tab_tag_flow                       ——
 *     animateLayoutChanges=true              → 增删 chip 的动画（见 3）
 *     paddingTop=5dp / paddingLeft=5dp       .padding({top:5,left:5})
 *     chipSpacing=@dimen/gallery_tab_layout_spacing(3dp)  → 见 2
 *     singleLine=false                       .wrap(Wrap)（多行）
 *     singleSelection=false                  → 多选（见 4）
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `ScrollView` 的高度是 `wrap_content`（不是 match）：内容少时容器不撑满 —— ArkUI 的
 *    `Scroll` 需要显式高度约束，故给它 `.constraintSize({maxHeight: '100%'})` + 由父 Column
 *    决定实际高度（父是 match×match，等价于"最多占满"）。这是本文件唯一的尺寸近似。
 * 2. `ChipGroup`（Material）→ ArkUI `Flex({wrap: Wrap})`：
 *    - `chipSpacing` 是**统一间距**（横向纵向同一个值）→ 用 chip 之间的 margin 表达：
 *      每个 chip `.margin({right:3,bottom:3})`（3vp = gallery_tab_layout_spacing）
 *    - `singleLine=false` → `FlexWrap.Wrap`（多行）
 *    - 上游 ChipGroup **没有** `chipSpacingVertical/Horizontal` 分开设置，故不分横纵
 * 3. `animateLayoutChanges="true"`：chip 增删时的默认过渡动画（Android 的 LayoutTransition）。
 *    ArkUI 的 Flex 无等价物 → **差异登记**；如需动画由使用方对 chip 容器加 `.transition(...)`。
 * 4. `singleSelection=false` 是**多选**语义，`singleSelection=true` 才是单选 —— 本布局是多选；
 *    chip 自身的选中态由 `item_chip_tag`（S0637，含 TODO(ui-widget) Material Chip）承担，
 *    这里只负责排布容器。
 * 5. chip 列表内容由 @BuilderParam 槽位注入（上游在代码里 addView 动态生成）。
 */

@Component
export struct ListThumbPopupwindowLayout {
  /** 上游 ?attr/popupWindowStyle（弹窗底色） */
  @Prop popupColor: ResourceColor = '#FFFFFFFF';
  /** 上游 chipSpacing=@dimen/gallery_tab_layout_spacing(3dp) */
  @Prop chipSpacing: number = 3;

  /** chip 列表（上游 ChipGroup 的子项，代码动态生成） */
  @BuilderParam chipsBuilder: () => void = this.emptyChips;

  @Builder
  emptyChips() {
    Row().width(0).height(0)
  }

  build() {
    Column() {
      Scroll() {
        Column() {
          Flex({ wrap: FlexWrap.Wrap }) {
            this.chipsBuilder();
          }
          .width('100%')
          .padding({ top: 5, left: 5 })
        }
        .width('100%')
      }
      .width('100%')
      .constraintSize({ maxHeight: '100%' })
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.popupColor)
  }
}
