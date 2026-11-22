/*
 * 上游：app/src/main/res/layout/preference_dialog_excluded_tag_namespaces.xml（122 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/preference_dialog_excluded_tag_namespaces.ets（S0640）
 *
 * ============================================================================
 * 骨架缺口（auditor-ui 量化 29/122）：**8 个 CheckBox 一个都没生成**
 * ============================================================================
 * 原因同 S0591：生成器把 `<TableLayout>` 当未识别节点整块跳过，连带 4 个 TableRow
 * 里的 8 个 CheckBox 全丢。本版按上游逐行还原。
 *
 * 上游结构：
 *   IndicatingScrollView（weight=1）
 *     TableLayout#table_layout
 *       TableRow ×4，每行 2 个 CheckBox（各 weight=1）：
 *         reclass | language
 *         parody  | character
 *         group   | artist
 *         male    | female
 *
 * ⚠️ **TableRow + 两个 weight=1 的等价物是 `Row` + 两个 `layoutWeight(1)`**，
 * 因为这里两个兄弟**都是 weight=1**（没有 wrap_content 项），
 * 所以 Android「分剩余」与 ArkUI「分总空间」结果一致 ——
 * 与 `gallery_detail_info` 的"中间列不能给 weight"是**不同情况**，别把那条规则误用到所有 TableRow。
 */

@Component
export struct PreferenceDialogExcludedTagNamespacesLayout {
  /** 上游 8 个 CheckBox 的勾选状态（顺序与 XML 一致） */
  @Prop tagGroupReclass: boolean = false;
  @Prop tagGroupLanguage: boolean = false;
  @Prop tagGroupParody: boolean = false;
  @Prop tagGroupCharacter: boolean = false;
  @Prop tagGroupGroup: boolean = false;
  @Prop tagGroupArtist: boolean = false;
  @Prop tagGroupMale: boolean = false;
  @Prop tagGroupFemale: boolean = false;
  /** 勾选变化回调（上游每个 CheckBox 各自 setOnCheckedChangeListener） */
  onToggle: (id: string, checked: boolean) => void = (id: string, checked: boolean): void => {};

  build() {
    // IndicatingScrollView（带指示条的自定义滚动容器）→ Scroll（指示条属 ui-widget）
    Scroll() {
      // TableLayout#table_layout → Column（4 个 TableRow → 4 个 Row）
      Column() {
        Row() {
          Checkbox({ name: 'tag_group_reclass', group: 'excluded_ns' })
            .id('tag_group_reclass')
            .select(this.tagGroupReclass)
            .layoutWeight(1)
            .onChange((v: boolean) => { this.onToggle('tag_group_reclass', v); })
          Text('reclass').layoutWeight(1).maxLines(1)
        }.width('100%')
        Row() {
          Checkbox({ name: 'tag_group_language', group: 'excluded_ns' })
            .id('tag_group_language')
            .select(this.tagGroupLanguage)
            .layoutWeight(1)
            .onChange((v: boolean) => { this.onToggle('tag_group_language', v); })
          Text('language').layoutWeight(1).maxLines(1)
        }.width('100%')
        Row() {
          Checkbox({ name: 'tag_group_parody', group: 'excluded_ns' })
            .id('tag_group_parody')
            .select(this.tagGroupParody)
            .layoutWeight(1)
            .onChange((v: boolean) => { this.onToggle('tag_group_parody', v); })
          Text('parody').layoutWeight(1).maxLines(1)
        }.width('100%')
        Row() {
          Checkbox({ name: 'tag_group_character', group: 'excluded_ns' })
            .id('tag_group_character')
            .select(this.tagGroupCharacter)
            .layoutWeight(1)
            .onChange((v: boolean) => { this.onToggle('tag_group_character', v); })
          Text('character').layoutWeight(1).maxLines(1)
        }.width('100%')
        Row() {
          Checkbox({ name: 'tag_group_group', group: 'excluded_ns' })
            .id('tag_group_group')
            .select(this.tagGroupGroup)
            .layoutWeight(1)
            .onChange((v: boolean) => { this.onToggle('tag_group_group', v); })
          Text('group').layoutWeight(1).maxLines(1)
        }.width('100%')
        Row() {
          Checkbox({ name: 'tag_group_artist', group: 'excluded_ns' })
            .id('tag_group_artist')
            .select(this.tagGroupArtist)
            .layoutWeight(1)
            .onChange((v: boolean) => { this.onToggle('tag_group_artist', v); })
          Text('artist').layoutWeight(1).maxLines(1)
        }.width('100%')
        Row() {
          Checkbox({ name: 'tag_group_male', group: 'excluded_ns' })
            .id('tag_group_male')
            .select(this.tagGroupMale)
            .layoutWeight(1)
            .onChange((v: boolean) => { this.onToggle('tag_group_male', v); })
          Text('male').layoutWeight(1).maxLines(1)
        }.width('100%')
        Row() {
          Checkbox({ name: 'tag_group_female', group: 'excluded_ns' })
            .id('tag_group_female')
            .select(this.tagGroupFemale)
            .layoutWeight(1)
            .onChange((v: boolean) => { this.onToggle('tag_group_female', v); })
          Text('female').layoutWeight(1).maxLines(1)
        }.width('100%')
      }
      .id('table_layout')
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .align(Alignment.TopStart)
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
  }
}