/*
 * 上游：app/src/main/res/layout/item_selected_tag_group.xml（inventory S0630，上游 26 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/item_selected_tag_group.ets
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                        ArkUI
 * LinearLayout(vertical)                          Column
 *   paddingStart/End=4dp, paddingTop/Bottom=6dp     .padding({left:4,right:4,top:6,bottom:6})
 * TextView#tv_group_title                          Text
 *   paddingBottom=8dp                                .margin({bottom:8})（见 1）
 *   textSize=14sp                                    .fontSize($r('app.float.text_small'))
 *   textStyle=bold                                   .fontWeight(FontWeight.Bold)
 * FlexboxLayout#flex_selected_tags                 Flex({wrap: FlexWrap.Wrap, ...})
 *   flexDirection=row / flexWrap=wrap                direction: Row + wrap: Wrap
 *   justifyContent=flex_start                        justifyContent: FlexAlign.Start
 *   alignItems=flex_start                            alignItems: ItemAlign.Start
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. 上游 title 用 `paddingBottom=8dp`（内边距，会撑进自身背景），
 *    ArkUI 的 Text 没有独立 padding 语义差异，等效用 `.margin({bottom:8})`；
 *    本布局 title 无背景色，二者视觉一致。
 * 2. FlexboxLayout 只是**容器**：具体标签项由父页面/使用方塞进
 *    `@BuilderParam tagItems`（上游是运行期 addView，ArkUI 用 Builder 槽位等价）。
 * 3. `alignItems="flex_start"`（交叉轴起点）→ `ItemAlign.Start`；
 *    `justifyContent="flex_start"`（主轴起点）→ `FlexAlign.Start`。
 */

@Component
export struct SelectedTagGroupItemLayout {
  @Prop groupTitle: string = '';
  @Prop titleColor: ResourceColor = '#DE000000';

  /** 标签项（上游 FlexboxLayout 的子 View 由调用方动态加入） */
  @BuilderParam tagItems: () => void = this.emptyTags;

  @Builder
  emptyTags() {
    Row().width(0).height(0)
  }

  build() {
    Column() {
      Text(this.groupTitle)
        .fontSize($r('app.float.text_small'))
        .fontWeight(FontWeight.Bold)
        .fontColor(this.titleColor)
        .width('100%')
        .margin({ bottom: 8 })

      Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap,
             justifyContent: FlexAlign.Start, alignItems: ItemAlign.Start }) {
        this.tagItems();
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 4, right: 4, top: 6, bottom: 6 })
    .alignItems(HorizontalAlign.Start)
  }
}
