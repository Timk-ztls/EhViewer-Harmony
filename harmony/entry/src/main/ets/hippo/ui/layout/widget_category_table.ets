/*
 * 上游：app/src/main/res/layout/widget_category_table.xml（inventory S0676，上游 134 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/widget_category_table.ets
 *
 * 背景：分类多选表格（10 个分类，5 行 × 2 列），每格是"带底色 + 白字 + 选中态"的
 * `com.hippo.widget.CheckTextView`。
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                   ArkUI
 * <merge>                                    见「无法等价」1（落 Column 容器）
 * TableRow × 5                               Row × 5（每行两格，各 layoutWeight(1)）
 * com.hippo.widget.CheckTextView            @Builder categoryCell()：Text + 底色 + 选中态（见 2）
 *   style=@style/CategoryText                16fp(Subhead) + bold + 居中 + minHeight 40
 *   layout_width=0dp / weight=1              .layoutWeight(1)
 *   layout_marginBottom/Top/Left/Right=4dp    .margin(4) 逐格（首行无 top、末行无 bottom，见 3）
 *   background=@color/<category>             .backgroundColor($r('app.color.<category>'))
 *   textColor=@android:color/white           .fontColor(Color.White)
 *   text=@string/<category>                  $r('app.string.<category>')
 *
 * 10 个分类与颜色（colors.json 已迁，取自上游 @color/*，与 EhUtils.BG_COLOR_* 同源）：
 *   doujinshi #FFF44336  manga #FFFF9800  artist_cg #FFFBC02D  game_cg   （colors.json）
 *   western             non_h #FF2196F3    image_set              cosplay
 *   asian_porn #FF9575CD misc #FFF06292
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `<merge>` 根 → 独立 Column 容器，无自带背景/内边距（只有格子间的 4vp margin）。
 * 2. `CheckTextView` 未由 ui-widget 交付（`hippo/widget/` 现有组件里没有）→ 按铁律：
 *    本文件用 `Text` + 边框 + 透明度表达**外观**，并把"选中切换"做成 @Prop + 回调，
 *    不伪造控件内部的 Checkable/Toggle 状态机；标 TODO(ui-widget)。
 *    上游 CheckTextView 的选中态表现是：选中 = 全彩底 + 白字；未选中 = 半透明底（alpha 0x66）。
 * 3. 边距照上游逐格还原：首行只有 bottom，中间行 top+bottom，末行只有 top；
 *    每行左格 right、右格 left 各 4vp。**不要**统一改成 padding —— 行间是 8vp（上下各 4 相加），
 *    格间也是 8vp，统一 padding 会变成 16vp。
 * 4. 分类位值语义不在本文件里（`EhConfig.DOUJINSHI=0x2 …`，见 CONTRACTS C-12）：
 *    回调传的是分类 id（与 `EhConfig` 常量一致），位值由调用方（CategoryTable 等价层）处理，
 *    布局层不硬编码任何位。
 * 5. `CategoryText` 的 `textAppearance=AppCompat.Subhead` = 16sp（已迁 `app.float.text_little_small`）。
 */

/** 分类项（10 个，顺序与上游 TableRow 一致） */
class CategoryCell {
  id: number;
  text: Resource;
  color: ResourceColor;

  constructor(id: number, text: Resource, color: ResourceColor) {
    this.id = id;
    this.text = text;
    this.color = color;
  }
}

@Component
export struct CategoryTableWidgetLayout {
  /** 已选中的分类 id 列表（上游 CheckTextView 的 checked 集合） */
  @Prop selected: number[] = [];

  /** 选中态切换回调：id 与 EhConfig 的分类位常量一致（位值不在布局层） */
  onToggle: (id: number, checked: boolean) => void = (id: number, checked: boolean) => {
    // 默认空实现：使用方必须注入
  };

  /** 10 个分类（顺序 = 上游 5 行 × 2 列的顺序） */
  private cells: CategoryCell[] = [
    new CategoryCell(0x2, $r('app.string.doujinshi'), $r('app.color.doujinshi')),
    new CategoryCell(0x4, $r('app.string.manga'), $r('app.color.manga')),
    new CategoryCell(0x8, $r('app.string.artist_cg'), $r('app.color.artist_cg')),
    new CategoryCell(0x10, $r('app.string.game_cg'), $r('app.color.game_cg')),
    new CategoryCell(0x200, $r('app.string.western'), $r('app.color.western')),
    new CategoryCell(0x100, $r('app.string.non_h'), $r('app.color.non_h')),
    new CategoryCell(0x20, $r('app.string.image_set'), $r('app.color.image_set')),
    new CategoryCell(0x40, $r('app.string.cosplay'), $r('app.color.cosplay')),
    new CategoryCell(0x80, $r('app.string.asian_porn'), $r('app.color.asian_porn')),
    new CategoryCell(0x1, $r('app.string.misc'), $r('app.color.misc'))
  ];

  @Builder
  categoryCell(index: number, marginTop: boolean, marginBottom: boolean, marginLeft: boolean, marginRight: boolean) {
    Text(this.cells[index].text)
      .fontSize($r('app.float.text_little_small'))
      .fontWeight(FontWeight.Bold)
      .fontColor(Color.White)
      .textAlign(TextAlign.Center)
      .width('100%')
      .constraintSize({ minHeight: $r('app.float.category_table_item_height') })
      .backgroundColor(this.cells[index].color)
      .opacity(this.selected.indexOf(this.cells[index].id) >= 0 ? 1.0 : 0.4)
      .padding({ top: 8, bottom: 8 })
      .margin({
        top: marginTop ? $r('app.float.category_table_item_margin') : 0,
        bottom: marginBottom ? $r('app.float.category_table_item_margin') : 0,
        left: marginLeft ? $r('app.float.category_table_item_margin') : 0,
        right: marginRight ? $r('app.float.category_table_item_margin') : 0
      })
      .onClick(() => {
        const id: number = this.cells[index].id;
        this.onToggle(id, this.selected.indexOf(id) < 0);
      })
  }

  build() {
    Column() {
      // 行1：doujinshi / manga（首行：只有 bottom）
      Row() {
        Row() {
          this.categoryCell(0, false, true, false, true);
        }
        .layoutWeight(1)

        Row() {
          this.categoryCell(1, false, true, true, false);
        }
        .layoutWeight(1)
      }
      .width('100%')

      // 行2：artist_cg / game_cg
      Row() {
        Row() {
          this.categoryCell(2, true, true, false, true);
        }
        .layoutWeight(1)

        Row() {
          this.categoryCell(3, true, true, true, false);
        }
        .layoutWeight(1)
      }
      .width('100%')

      // 行3：western / non_h
      Row() {
        Row() {
          this.categoryCell(4, true, true, false, true);
        }
        .layoutWeight(1)

        Row() {
          this.categoryCell(5, true, true, true, false);
        }
        .layoutWeight(1)
      }
      .width('100%')

      // 行4：image_set / cosplay
      Row() {
        Row() {
          this.categoryCell(6, true, true, false, true);
        }
        .layoutWeight(1)

        Row() {
          this.categoryCell(7, true, true, true, false);
        }
        .layoutWeight(1)
      }
      .width('100%')

      // 行5：asian_porn / misc（末行：只有 top）
      Row() {
        Row() {
          this.categoryCell(8, true, false, false, true);
        }
        .layoutWeight(1)

        Row() {
          this.categoryCell(9, true, false, true, false);
        }
        .layoutWeight(1)
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
