/**
 * Material AdvanceSearchTable aligned with Android AdvanceSearchTable.java & widget_advance_search_table.xml.
 */

import {
  ThemeDimens,
  ThemePalette,
  ThemeRadius,
  ThemeTokens,
  ThemeTypography,
} from '../../../common/theme/ThemeTokens';

export class AdvanceSearchFlags {
  static readonly SNAME: number = 0x1;   // 1    Search Gallery
  static readonly STAGS: number = 0x2;   // 2    Search Gallery Tags
  static readonly SDESC: number = 0x4;   // 4    Search Gallery Description
  static readonly STORR: number = 0x8;   // 8    Search Torrent Filenames
  static readonly STO: number = 0x10;    // 16   Only Show Galleries With Torrents
  static readonly SDT1: number = 0x20;   // 32   Search Low-Power Tags
  static readonly SDT2: number = 0x40;   // 64   Search Downvoted Tags
  static readonly SH: number = 0x80;     // 128  Search Expunged Galleries
  static readonly SFL: number = 0x100;   // 256  Disable default filters: Language
  static readonly SFU: number = 0x200;   // 512  Disable default filters: Uploader
  static readonly SFT: number = 0x400;   // 1024 Disable default filters: Tags
}

function parsePositiveIntOrNegOne(text: string): number {
  const trimmed: string = text.trim();
  if (trimmed.length === 0) {
    return -1;
  }
  const n: number = parseInt(trimmed, 10);
  if (Number.isNaN(n) || n <= 0) {
    return -1;
  }
  return n;
}

export class AdvanceSearchState {
  sname: boolean = true;
  stags: boolean = true;
  sdesc: boolean = false;
  storr: boolean = false;
  sto: boolean = false;
  sdt1: boolean = false;
  sdt2: boolean = false;
  sh: boolean = false;
  sfl: boolean = false;
  sfu: boolean = false;
  sft: boolean = false;

  sr: boolean = false;
  minRatingPosition: number = 0;

  sp: boolean = false;
  pageFromText: string = '';
  pageToText: string = '';

  getAdvanceSearch(): number {
    let adv: number = 0;
    if (this.sname) { adv |= AdvanceSearchFlags.SNAME; }
    if (this.stags) { adv |= AdvanceSearchFlags.STAGS; }
    if (this.sdesc) { adv |= AdvanceSearchFlags.SDESC; }
    if (this.storr) { adv |= AdvanceSearchFlags.STORR; }
    if (this.sto) { adv |= AdvanceSearchFlags.STO; }
    if (this.sdt1) { adv |= AdvanceSearchFlags.SDT1; }
    if (this.sdt2) { adv |= AdvanceSearchFlags.SDT2; }
    if (this.sh) { adv |= AdvanceSearchFlags.SH; }
    if (this.sfl) { adv |= AdvanceSearchFlags.SFL; }
    if (this.sfu) { adv |= AdvanceSearchFlags.SFU; }
    if (this.sft) { adv |= AdvanceSearchFlags.SFT; }
    return adv;
  }

  setAdvanceSearch(advanceSearch: number): void {
    this.sname = (advanceSearch & AdvanceSearchFlags.SNAME) !== 0;
    this.stags = (advanceSearch & AdvanceSearchFlags.STAGS) !== 0;
    this.sdesc = (advanceSearch & AdvanceSearchFlags.SDESC) !== 0;
    this.storr = (advanceSearch & AdvanceSearchFlags.STORR) !== 0;
    this.sto = (advanceSearch & AdvanceSearchFlags.STO) !== 0;
    this.sdt1 = (advanceSearch & AdvanceSearchFlags.SDT1) !== 0;
    this.sdt2 = (advanceSearch & AdvanceSearchFlags.SDT2) !== 0;
    this.sh = (advanceSearch & AdvanceSearchFlags.SH) !== 0;
    this.sfl = (advanceSearch & AdvanceSearchFlags.SFL) !== 0;
    this.sfu = (advanceSearch & AdvanceSearchFlags.SFU) !== 0;
    this.sft = (advanceSearch & AdvanceSearchFlags.SFT) !== 0;
  }

  getMinRating(): number {
    if (this.sr && this.minRatingPosition >= 0) {
      return this.minRatingPosition + 2;
    }
    return -1;
  }

  setMinRating(minRating: number): void {
    if (minRating >= 2 && minRating <= 5) {
      this.sr = true;
      this.minRatingPosition = minRating - 2;
    } else {
      this.sr = false;
    }
  }

  getPageFrom(): number {
    if (this.sp) {
      return parsePositiveIntOrNegOne(this.pageFromText);
    }
    return -1;
  }

  getPageTo(): number {
    if (this.sp) {
      return parsePositiveIntOrNegOne(this.pageToText);
    }
    return -1;
  }

  setPageFrom(pageFrom: number): void {
    if (pageFrom > 0) {
      this.pageFromText = String(pageFrom);
      this.sp = true;
    } else {
      this.sp = false;
      this.pageFromText = '';
    }
  }

  setPageTo(pageTo: number): void {
    if (pageTo > 0) {
      this.pageToText = String(pageTo);
      this.sp = true;
    } else {
      this.pageToText = '';
    }
  }
}

export class AdvanceSearchSavedState {
  advanceSearch: number = 0;
  minRating: number = -1;
  pageFrom: number = -1;
  pageTo: number = -1;
}

@Component
export struct AdvanceSearchTable {
  state: AdvanceSearchState = new AdvanceSearchState();
  @State rev: number = 0;
  @Prop themeId: number = -1;

  @Prop labelSname: ResourceStr = $r('app.string.search_sname');
  @Prop labelStags: ResourceStr = $r('app.string.search_stags');
  @Prop labelSdesc: ResourceStr = $r('app.string.search_sdesc');
  @Prop labelStorr: ResourceStr = $r('app.string.search_storr');
  @Prop labelSto: ResourceStr = $r('app.string.search_sto');
  @Prop labelSdt1: ResourceStr = $r('app.string.search_sdt1');
  @Prop labelSdt2: ResourceStr = $r('app.string.search_sdt2');
  @Prop labelSh: ResourceStr = $r('app.string.search_sh');
  @Prop labelSr: ResourceStr = $r('app.string.search_sr');
  @Prop labelSp: ResourceStr = $r('app.string.search_sp');
  @Prop labelSpTo: ResourceStr = $r('app.string.search_sp_to');
  @Prop labelSf: ResourceStr = $r('app.string.search_sf');
  @Prop labelSfl: ResourceStr = $r('app.string.search_sfl');
  @Prop labelSfu: ResourceStr = $r('app.string.search_sfu');
  @Prop labelSft: ResourceStr = $r('app.string.search_sft');

  @Prop minRatingOptions: SelectOption[] = [
    { value: $r('app.string.star_2') },
    { value: $r('app.string.star_3') },
    { value: $r('app.string.star_4') },
    { value: $r('app.string.star_5') },
  ];

  private resolvePalette(): ThemePalette {
    if (this.themeId >= 0) {
      return ThemeTokens.of(this.themeId);
    }
    return ThemeTokens.current();
  }

  private selectedRatingLabel(): ResourceStr {
    const idx: number = this.state.minRatingPosition;
    if (idx >= 0 && idx < this.minRatingOptions.length) {
      return this.minRatingOptions[idx].value;
    }
    return $r('app.string.star_2');
  }

  saveState(): AdvanceSearchSavedState {
    const s: AdvanceSearchSavedState = new AdvanceSearchSavedState();
    s.advanceSearch = this.state.getAdvanceSearch();
    s.minRating = this.state.getMinRating();
    s.pageFrom = this.state.getPageFrom();
    s.pageTo = this.state.getPageTo();
    return s;
  }

  restoreState(s: AdvanceSearchSavedState): void {
    this.state.setAdvanceSearch(s.advanceSearch);
    this.state.setMinRating(s.minRating);
    this.state.setPageFrom(s.pageFrom);
    this.state.setPageTo(s.pageTo);
    this.rev++;
  }

  @Builder
  private checkBoxCell(
    name: string,
    label: ResourceStr,
    checked: boolean,
    onToggle: (next: boolean) => void
  ): void {
    Row({ space: ThemeDimens.SPACING_XS }) {
      Checkbox({ name: name, group: 'adv_table' })
        .select(checked)
        .selectedColor(this.resolvePalette().controlActivated)
        .unselectedColor(this.resolvePalette().textSecondary)
        .shape(CheckBoxShape.ROUNDED_SQUARE)
        .width(18)
        .height(18)
        .onChange((isChecked: boolean): void => {
          onToggle(isChecked);
        })

      Text(label)
        .fontSize(ThemeTypography.TEXT_SMALL)
        .fontColor(this.resolvePalette().textPrimary)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .layoutWeight(1)
    .constraintSize({ minHeight: ThemeDimens.CATEGORY_TABLE_ITEM_HEIGHT })
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      onToggle(!checked);
    })
  }

  build(): void {
    this.buildTable();
  }

  @Builder
  private buildTable(): void {
    Column({ space: ThemeDimens.SPACING }) {
      Row({ space: ThemeDimens.SPACING }) {
        this.checkBoxCell('sname', this.labelSname, this.rev >= 0 && this.state.sname, (v: boolean): void => {
          this.state.sname = v;
          this.rev++;
        })
        this.checkBoxCell('stags', this.labelStags, this.rev >= 0 && this.state.stags, (v: boolean): void => {
          this.state.stags = v;
          this.rev++;
        })
      }.width('100%').alignItems(VerticalAlign.Center)

      Row({ space: ThemeDimens.SPACING }) {
        this.checkBoxCell('sdesc', this.labelSdesc, this.rev >= 0 && this.state.sdesc, (v: boolean): void => {
          this.state.sdesc = v;
          this.rev++;
        })
        this.checkBoxCell('storr', this.labelStorr, this.rev >= 0 && this.state.storr, (v: boolean): void => {
          this.state.storr = v;
          this.rev++;
        })
      }.width('100%').alignItems(VerticalAlign.Center)

      Row({ space: ThemeDimens.SPACING }) {
        this.checkBoxCell('sto', this.labelSto, this.rev >= 0 && this.state.sto, (v: boolean): void => {
          this.state.sto = v;
          this.rev++;
        })
        this.checkBoxCell('sdt1', this.labelSdt1, this.rev >= 0 && this.state.sdt1, (v: boolean): void => {
          this.state.sdt1 = v;
          this.rev++;
        })
      }.width('100%').alignItems(VerticalAlign.Center)

      Row({ space: ThemeDimens.SPACING }) {
        this.checkBoxCell('sdt2', this.labelSdt2, this.rev >= 0 && this.state.sdt2, (v: boolean): void => {
          this.state.sdt2 = v;
          this.rev++;
        })
        this.checkBoxCell('sh', this.labelSh, this.rev >= 0 && this.state.sh, (v: boolean): void => {
          this.state.sh = v;
          this.rev++;
        })
      }.width('100%').alignItems(VerticalAlign.Center)

      Row({ space: ThemeDimens.SPACING }) {
        this.checkBoxCell('sr', this.labelSr, this.rev >= 0 && this.state.sr, (v: boolean): void => {
          this.state.sr = v;
          this.rev++;
        })

        Select(this.minRatingOptions)
          .selected(this.rev >= 0 ? this.state.minRatingPosition : 0)
          .value(this.rev >= 0 ? this.selectedRatingLabel() : $r('app.string.star_2'))
          .font({ size: ThemeTypography.TEXT_SMALL })
          .fontColor(this.resolvePalette().textPrimary)
          .backgroundColor(this.resolvePalette().transparent)
          .selectedOptionBgColor(this.resolvePalette().cardActivatedBackground)
          .selectedOptionFontColor(this.resolvePalette().colorPrimary)
          .optionBgColor(this.resolvePalette().popupBackground)
          .optionFontColor(this.resolvePalette().textPrimary)
          .layoutWeight(1)
          .onSelect((index: number, _value: string): void => {
            this.state.minRatingPosition = index;
            this.rev++;
          })
      }.width('100%').alignItems(VerticalAlign.Center)

      Row({ space: ThemeDimens.ADVANCE_SEARCH_TABLE_ITEM_MARGIN }) {
        Row({ space: ThemeDimens.SPACING_XS }) {
          Checkbox({ name: 'sp', group: 'adv_table' })
            .select(this.rev >= 0 && this.state.sp)
            .selectedColor(this.resolvePalette().controlActivated)
            .unselectedColor(this.resolvePalette().textSecondary)
            .shape(CheckBoxShape.ROUNDED_SQUARE)
            .width(18)
            .height(18)
            .onChange((v: boolean): void => {
              this.state.sp = v;
              this.rev++;
            })

          Text(this.labelSp)
            .fontSize(ThemeTypography.TEXT_SMALL)
            .fontColor(this.resolvePalette().textPrimary)
        }
        .alignItems(VerticalAlign.Center)
        .onClick((): void => {
          this.state.sp = !this.state.sp;
          this.rev++;
        })

        TextInput({ text: this.rev >= 0 ? this.state.pageFromText : '' })
          .width(64)
          .height(36)
          .padding({ left: 4, right: 4, top: 0, bottom: 2 })
          .backgroundColor(this.resolvePalette().transparent)
          .borderRadius(ThemeRadius.NONE)
          .borderWidth({ bottom: 1 })
          .borderColor(this.resolvePalette().divider)
          .fontSize(ThemeTypography.TEXT_SMALL)
          .fontColor(this.resolvePalette().textPrimary)
          .caretColor(this.resolvePalette().controlActivated)
          .textAlign(TextAlign.Center)
          .type(InputType.Number)
          .onChange((v: string): void => {
            this.state.pageFromText = v;
          })

        Text(this.labelSpTo)
          .fontSize(ThemeTypography.TEXT_SMALL)
          .fontColor(this.resolvePalette().textPrimary)
          .margin({ left: ThemeDimens.ADVANCE_SEARCH_TABLE_ITEM_MARGIN, right: ThemeDimens.ADVANCE_SEARCH_TABLE_ITEM_MARGIN })

        TextInput({ text: this.rev >= 0 ? this.state.pageToText : '' })
          .width(64)
          .height(36)
          .padding({ left: 4, right: 4, top: 0, bottom: 2 })
          .backgroundColor(this.resolvePalette().transparent)
          .borderRadius(ThemeRadius.NONE)
          .borderWidth({ bottom: 1 })
          .borderColor(this.resolvePalette().divider)
          .fontSize(ThemeTypography.TEXT_SMALL)
          .fontColor(this.resolvePalette().textPrimary)
          .caretColor(this.resolvePalette().controlActivated)
          .textAlign(TextAlign.Center)
          .type(InputType.Number)
          .onChange((v: string): void => {
            this.state.pageToText = v;
          })
      }
      .width('100%')
      .constraintSize({ minHeight: ThemeDimens.CATEGORY_TABLE_ITEM_HEIGHT })
      .alignItems(VerticalAlign.Center)

      Text(this.labelSf)
        .fontSize(ThemeTypography.TEXT_SMALL)
        .fontColor(this.resolvePalette().textPrimary)
        .width('100%')
        .margin({ top: ThemeDimens.ADVANCE_SEARCH_TABLE_ITEM_MARGIN })

      Row({ space: ThemeDimens.ADVANCE_SEARCH_TABLE_ITEM_MARGIN }) {
        this.checkBoxCell('sfl', this.labelSfl, this.rev >= 0 && this.state.sfl, (v: boolean): void => {
          this.state.sfl = v;
          this.rev++;
        })
        this.checkBoxCell('sfu', this.labelSfu, this.rev >= 0 && this.state.sfu, (v: boolean): void => {
          this.state.sfu = v;
          this.rev++;
        })
        this.checkBoxCell('sft', this.labelSft, this.rev >= 0 && this.state.sft, (v: boolean): void => {
          this.state.sft = v;
          this.rev++;
        })
      }.width('100%').alignItems(VerticalAlign.Center)
    }
    .width('100%')
  }
}
