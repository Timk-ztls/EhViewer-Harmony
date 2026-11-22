/**
 * Material CategoryTable aligned with Android CategoryTable.java & widget_category_table.xml.
 * 5 rows x 2 columns of 40vp CategoryColors tiles using CheckTextView #8A000000 mask overlay.
 */

import {
  CategoryColors,
  ThemeDimens,
  ThemePalette,
  ThemeRadius,
  ThemeTokens,
  ThemeTypography,
} from '../../../common/theme/ThemeTokens';
import { CheckTextView } from '../../widget/CheckTextView';

export class CategoryOption {
  readonly name: string;
  readonly bit: number;
  readonly label: string;

  constructor(name: string, bit: number, label: string) {
    this.name = name;
    this.bit = bit;
    this.label = label;
  }
}

export class CategoryFlags {
  static readonly MISC: number = 0x1;
  static readonly DOUJINSHI: number = 0x2;
  static readonly MANGA: number = 0x4;
  static readonly ARTIST_CG: number = 0x8;
  static readonly GAME_CG: number = 0x10;
  static readonly IMAGE_SET: number = 0x20;
  static readonly COSPLAY: number = 0x40;
  static readonly ASIAN_PORN: number = 0x80;
  static readonly NON_H: number = 0x100;
  static readonly WESTERN: number = 0x200;
  static readonly ALL_CATEGORY: number = 0x3ff;

  static readonly OPTIONS: CategoryOption[] = [
    new CategoryOption('doujinshi', CategoryFlags.DOUJINSHI, 'Doujinshi'),
    new CategoryOption('manga', CategoryFlags.MANGA, 'Manga'),
    new CategoryOption('artist_cg', CategoryFlags.ARTIST_CG, 'Artist CG'),
    new CategoryOption('game_cg', CategoryFlags.GAME_CG, 'Game CG'),
    new CategoryOption('western', CategoryFlags.WESTERN, 'Western'),
    new CategoryOption('non_h', CategoryFlags.NON_H, 'Non-H'),
    new CategoryOption('image_set', CategoryFlags.IMAGE_SET, 'Image Set'),
    new CategoryOption('cosplay', CategoryFlags.COSPLAY, 'Cosplay'),
    new CategoryOption('asian_porn', CategoryFlags.ASIAN_PORN, 'Asian Porn'),
    new CategoryOption('misc', CategoryFlags.MISC, 'Misc'),
  ];
}

export class CategoryTableState {
  checked: boolean[] = [];

  constructor() {
    for (let i: number = 0; i < CategoryFlags.OPTIONS.length; i++) {
      this.checked.push(true);
    }
  }

  getCategory(): number {
    let category: number = 0;
    for (let i: number = 0; i < CategoryFlags.OPTIONS.length; i++) {
      if (this.checked[i]) {
        category |= CategoryFlags.OPTIONS[i].bit;
      }
    }
    return category;
  }

  setCategory(category: number): void {
    for (let i: number = 0; i < CategoryFlags.OPTIONS.length; i++) {
      this.checked[i] = (category & CategoryFlags.OPTIONS[i].bit) !== 0;
    }
  }

  toggleAll(): void {
    const allChecked: boolean = this.getCategory() === CategoryFlags.ALL_CATEGORY;
    this.setCategory(allChecked ? 0 : CategoryFlags.ALL_CATEGORY);
  }

  toggle(index: number): void {
    if (index >= 0 && index < this.checked.length) {
      this.checked[index] = !this.checked[index];
    }
  }

  selectSoloOrInvertOthers(index: number): void {
    if (index < 0 || index >= this.checked.length) {
      return;
    }
    const keepIncluded: boolean = this.checked[index];
    for (let i: number = 0; i < this.checked.length; i++) {
      if (i !== index) {
        this.checked[i] = !keepIncluded;
      }
    }
  }
}

@Component
export struct CategoryTable {
  state: CategoryTableState = new CategoryTableState();
  @Prop themeId: number = -1;
  @State rev: number = 0;
  onChange: (category: number) => void = (): void => {
  };

  private resolvePalette(): ThemePalette {
    if (this.themeId >= 0) {
      return ThemeTokens.of(this.themeId);
    }
    return ThemeTokens.current();
  }

  private labelResourceForBit(bit: number): ResourceStr {
    switch (bit) {
      case CategoryFlags.DOUJINSHI:
        return $r('app.string.doujinshi');
      case CategoryFlags.MANGA:
        return $r('app.string.manga');
      case CategoryFlags.ARTIST_CG:
        return $r('app.string.artist_cg');
      case CategoryFlags.GAME_CG:
        return $r('app.string.game_cg');
      case CategoryFlags.WESTERN:
        return $r('app.string.western');
      case CategoryFlags.NON_H:
        return $r('app.string.non_h');
      case CategoryFlags.IMAGE_SET:
        return $r('app.string.image_set');
      case CategoryFlags.COSPLAY:
        return $r('app.string.cosplay');
      case CategoryFlags.ASIAN_PORN:
        return $r('app.string.asian_porn');
      default:
        return $r('app.string.misc');
    }
  }

  @Builder
  optionCell(index: number): void {
    this.buildOptionCell(index);
  }

  @Builder
  private buildOptionCell(index: number): void {
    CheckTextView({
      text: this.labelResourceForBit(CategoryFlags.OPTIONS[index].bit),
      fontSize: ThemeTypography.TEXT_LITTLE_SMALL,
      fontWeightValue: FontWeight.Bold,
      textColor: this.resolvePalette().white,
      bgColor: CategoryColors.forCategory(CategoryFlags.OPTIONS[index].bit),
      maskColor: this.resolvePalette().checkTextViewMask,
      cornerRadius: ThemeRadius.CATEGORY_BADGE,
      minHeightValue: ThemeDimens.CATEGORY_TABLE_ITEM_HEIGHT,
      maxWidthValue: 0,
      themeId: this.themeId,
      checked: !(this.rev >= 0 && this.state.checked[index]),
      onChange: (_maskChecked: boolean): void => {
        this.state.toggle(index);
        this.rev++;
        this.onChange(this.state.getCategory());
      },
      onLongPress: (): void => {
        this.state.selectSoloOrInvertOthers(index);
        this.rev++;
        this.onChange(this.state.getCategory());
      },
    })
      .layoutWeight(1)
      .height(ThemeDimens.CATEGORY_TABLE_ITEM_HEIGHT)
      .margin(ThemeDimens.CATEGORY_TABLE_ITEM_MARGIN)
  }

  build(): void {
    Column() {
      Row() {
        this.optionCell(0)
        this.optionCell(1)
      }.width('100%')

      Row() {
        this.optionCell(2)
        this.optionCell(3)
      }.width('100%')

      Row() {
        this.optionCell(4)
        this.optionCell(5)
      }.width('100%')

      Row() {
        this.optionCell(6)
        this.optionCell(7)
      }.width('100%')

      Row() {
        this.optionCell(8)
        this.optionCell(9)
      }.width('100%')
    }
    .width('100%')
  }
}
