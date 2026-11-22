/*
 * 上游：app/src/main/res/layout/widget_advance_search_table.xml（246 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/widget_advance_search_table.ets（S0674）
 *
 * ============================================================================
 * 骨架缺口（auditor-ui 量化 58/246）：**Spinner#search_min_rating 未生成 + 11 个复选框两列塌单列**
 * ============================================================================
 * 上游根节点是 `<merge>`（这个布局被 include 进别的布局，不自带外壳）。
 *
 * 上游结构（每行 2 个 weight=1 的 CheckBox，共 5 行 + 3 行特殊）：
 *   Row1: search_gallery(checked)      | search_gallery_tags(checked)
 *   Row2: search_gallery_description   | search_torrent_filenames
 *   Row3: only_show_galleries_with_torrents | search_low_power_tags
 *   Row4: search_downvoted_tags        | search_expunged_galleries
 *   Row5: minimum_rating(weight=1)     | Spinner#search_min_rating(weight=1, @array/search_min_rating)
 *   Row6: pages_setting + EditText#spf + "to" + EditText#spt + "suffix"
 *   Row7: TextView(@string/search_sf)
 *   Row8: disable_default_filter_language | disable_default_filter_uploader | disable_default_filter_tags
 *
 * 三处**移植陷阱**：
 *   1. **"两列塌单列"的根因**：一行两个 weight=1 的兄弟在 ArkUI 里如果外层是 `Column`
 *      而不是 `Row`，就会**竖向堆叠**变成一列 —— 生成器丢的正是 Row 这一层；
 *   2. `search_min_rating` 的 Spinner **与左边 CheckBox 各占 1/2**（weight 都是 1），
 *      不是"跟在后面的一小截"——照搬 weight；
 *   3. `search_gallery` / `search_gallery_tags` 的 `android:checked="true"` 是**初值**，
 *      必须在 `@Prop` 默认值里体现，否则用户一进来看到的是全不勾。
 */

/** 一行两个复选框的数据（避免 13 个 @Prop 手写重复） */
export class CheckRowSpec {
  id: string = '';
  labelRes: string = '';
  defaultChecked: boolean = false;

  constructor(id: string, labelRes: string, defaultChecked: boolean) {
    this.id = id;
    this.labelRes = labelRes;
    this.defaultChecked = defaultChecked;
  }
}

@Component
export struct WidgetAdvanceSearchTableLayout {
  /** 上游 13 个 CheckBox 的勾选状态，键即 upstream id */
  @Prop checked: Map<string, boolean> = new Map<string, boolean>();
  /** 最小评分下拉的选中下标（@array/search_min_rating） */
  @Prop minRating: number = 0;
  /** 页数区间（EditText#spf / #spt） */
  @Prop spf: string = '';
  @Prop spt: string = '';
  onToggle: (id: string, checked: boolean) => void = (id: string, checked: boolean): void => {};

  /** 前 5 行：每行 2 个。注意前两个默认勾选（上游 checked="true"）。 */
  static readonly ROWS: CheckRowSpec[][] = [
    [new CheckRowSpec('search_gallery', 'search_sname', true),
      new CheckRowSpec('search_gallery_tags', 'search_stags', true)],
    [new CheckRowSpec('search_gallery_description', 'search_sdesc', false),
      new CheckRowSpec('search_torrent_filenames', 'search_storr', false)],
    [new CheckRowSpec('only_show_galleries_with_torrents', 'search_sto', false),
      new CheckRowSpec('search_low_power_tags', 'search_sdt1', false)],
    [new CheckRowSpec('search_downvoted_tags', 'search_sdt2', false),
      new CheckRowSpec('search_expunged_galleries', 'search_sh', false)]
  ];

  /** 第 8 行：3 个"禁用默认过滤器"复选框。 */
  static readonly FILTER_ROWS: CheckRowSpec[] = [
    new CheckRowSpec('disable_default_filter_language', 'search_sfl', false),
    new CheckRowSpec('disable_default_filter_uploader', 'search_sfu', false),
    new CheckRowSpec('disable_default_filter_tags', 'search_sft', false)
  ];

  private isOn(id: string, fallback: boolean): boolean {
    const v: boolean | undefined = this.checked.get(id);
    return v === undefined ? fallback : v;
  }

  @Builder
  checkCell(spec: CheckRowSpec) {
    Row() {
      Checkbox({ name: spec.id, group: 'adv_search' })
        .id(spec.id)
        .select(this.isOn(spec.id, spec.defaultChecked))
        .onChange((v: boolean) => { this.onToggle(spec.id, v); })
      Text($r(`app.string.${spec.labelRes}`)).layoutWeight(1).maxLines(1)
    }
    .layoutWeight(1)
  }

  build() {
    // 上游根是 <merge> → 这里直接 Column（外壳由 include 它的布局提供）
    Column() {
      // 前 4 行：两列
      ForEach(WidgetAdvanceSearchTableLayout.ROWS, (row: CheckRowSpec[]) => {
        Row() {
          this.checkCell(row[0])
          this.checkCell(row[1])
        }
        .width('100%')
      }, (row: CheckRowSpec[]) => row[0].id)

      // 第 5 行：minimum_rating CheckBox + search_min_rating Spinner（各 1/2）
      Row() {
        Row() {
          Checkbox({ name: 'minimum_rating', group: 'adv_search' })
            .id('minimum_rating')
            .select(this.isOn('minimum_rating', false))
            .onChange((v: boolean) => { this.onToggle('minimum_rating', v); })
          Text($r('app.string.search_sr')).layoutWeight(1).maxLines(1)
        }.layoutWeight(1)

        Select([{ value: '' } as SelectOption])
          .id('search_min_rating')
          .layoutWeight(1)
          .selected(this.minRating)
      }
      .width('100%')

      // 第 6 行：页数区间
      Row() {
        Row() {
          Checkbox({ name: 'pages_setting', group: 'adv_search' })
            .id('pages_setting')
            .select(this.isOn('pages_setting', false))
            .onChange((v: boolean) => { this.onToggle('pages_setting', v); })
          Text($r('app.string.search_sp')).maxLines(1)
        }
        TextInput({ text: this.spf }).id('spf').width(64)
        Text($r('app.string.search_sp_to')).maxLines(1)
        TextInput({ text: this.spt }).id('spt').width(64)
        Text($r('app.string.search_sp_suffix')).maxLines(1)
      }
      .width('100%')

      // 第 7 行：标签
      Text($r('app.string.search_sf'))
        .width('100%')
        .textAlign(TextAlign.Start)

      // 第 8 行：三个"禁用默认过滤器"
      Row() {
        ForEach(WidgetAdvanceSearchTableLayout.FILTER_ROWS, (spec: CheckRowSpec) => {
          Row() {
            Checkbox({ name: spec.id, group: 'adv_search' })
              .id(spec.id)
              .select(this.isOn(spec.id, spec.defaultChecked))
              .onChange((v: boolean) => { this.onToggle(spec.id, v); })
            Text($r(`app.string.${spec.labelRes}`)).layoutWeight(1).maxLines(1)
          }
          .layoutWeight(1)
        }, (spec: CheckRowSpec) => spec.id)
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}