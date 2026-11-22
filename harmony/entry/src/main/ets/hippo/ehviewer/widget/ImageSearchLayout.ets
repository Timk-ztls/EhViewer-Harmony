/**
 * Material ImageSearchLayout aligned with Android ImageSearchLayout.java & widget_image_search.xml.
 */

import {
  ThemeDimens,
  ThemePalette,
  ThemeRadius,
  ThemeTokens,
  ThemeTypography,
} from '../../../common/theme/ThemeTokens';

export interface Helper {
  onSelectImage(): void;
}

export class HelperImpl implements Helper {
  private readonly fn: () => void;

  constructor(fn: () => void) {
    this.fn = fn;
  }

  onSelectImage(): void {
    this.fn();
  }
}

export interface ImageSearchBuilder {
  setUseSimilarityScan(useSimilarityScan: boolean): void;

  setOnlySearchCovers(onlySearchCovers: boolean): void;

  setShowExpunged(showExpunged: boolean): void;
}

export class ImageSearchSavedState {
  imagePath: string = '';
  useSimilarityScan: boolean = false;
  onlySearchCovers: boolean = false;
  showExpunged: boolean = false;
}

export class ImageSearchLayoutState {
  helper: Helper | null = null;
  imagePath: string = '';
  useSimilarityScan: boolean = false;
  onlySearchCovers: boolean = false;
  showExpunged: boolean = false;

  setHelper(helper: Helper | null): void {
    this.helper = helper;
  }

  setImagePath(path: string): void {
    this.imagePath = path;
  }

  formatListUrlBuilder(builder: ImageSearchBuilder): void {
    builder.setUseSimilarityScan(this.useSimilarityScan);
    builder.setOnlySearchCovers(this.onlySearchCovers);
    builder.setShowExpunged(this.showExpunged);
  }

  onSelectImage(): void {
    if (this.helper !== null) {
      this.helper.onSelectImage();
    }
  }

  saveState(): ImageSearchSavedState {
    const s: ImageSearchSavedState = new ImageSearchSavedState();
    s.imagePath = this.imagePath;
    s.useSimilarityScan = this.useSimilarityScan;
    s.onlySearchCovers = this.onlySearchCovers;
    s.showExpunged = this.showExpunged;
    return s;
  }

  restoreState(s: ImageSearchSavedState): void {
    this.imagePath = s.imagePath;
    this.useSimilarityScan = s.useSimilarityScan;
    this.onlySearchCovers = s.onlySearchCovers;
    this.showExpunged = s.showExpunged;
  }
}

@Component
export struct ImageSearchLayout {
  state: ImageSearchLayoutState = new ImageSearchLayoutState();
  @State rev: number = 0;
  @Prop previewSize: number = 240;
  @Prop themeId: number = -1;
  @Prop labelSelectImage: ResourceStr = $r('app.string.select_image');
  @Prop labelUSS: ResourceStr = $r('app.string.search_uss');
  @Prop labelOSC: ResourceStr = $r('app.string.search_osc');
  @Prop labelSE: ResourceStr = $r('app.string.search_se');

  private resolvePalette(): ThemePalette {
    if (this.themeId >= 0) {
      return ThemeTokens.of(this.themeId);
    }
    return ThemeTokens.current();
  }

  @Builder
  private optionCheckbox(
    name: string,
    label: ResourceStr,
    checked: boolean,
    onToggle: (next: boolean) => void
  ): void {
    Row({ space: ThemeDimens.SPACING_XS }) {
      Checkbox({ name: name, group: 'img_search' })
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
    this.buildContent();
  }

  @Builder
  private buildContent(): void {
    Column({ space: ThemeDimens.SPACING }) {
      if (this.rev >= 0 && this.state.imagePath.length > 0) {
        Image(this.state.imagePath)
          .constraintSize({ maxWidth: this.previewSize, maxHeight: this.previewSize })
          .objectFit(ImageFit.Contain)
          .borderRadius(ThemeRadius.CARD)
      }

      Button({ type: ButtonType.Normal }) {
        Text(this.labelSelectImage)
          .fontSize(ThemeTypography.BUTTON)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.resolvePalette().colorPrimary)
      }
      .backgroundColor(this.resolvePalette().transparent)
      .borderRadius(ThemeRadius.BUTTON)
      .constraintSize({ minWidth: 88, minHeight: ThemeDimens.TOUCH_TARGET_MIN })
      .padding({ left: ThemeDimens.KEYLINE_MARGIN, right: ThemeDimens.KEYLINE_MARGIN })
      .onClick((): void => {
        this.state.onSelectImage();
      })

      Column({ space: ThemeDimens.SPACING }) {
        Row({ space: ThemeDimens.SPACING }) {
          this.optionCheckbox('uss', this.labelUSS, this.rev >= 0 && this.state.useSimilarityScan, (v: boolean): void => {
            this.state.useSimilarityScan = v;
            this.rev++;
          })
          this.optionCheckbox('osc', this.labelOSC, this.rev >= 0 && this.state.onlySearchCovers, (v: boolean): void => {
            this.state.onlySearchCovers = v;
            this.rev++;
          })
        }.width('100%').alignItems(VerticalAlign.Center)

        Row({ space: ThemeDimens.SPACING }) {
          this.optionCheckbox('se', this.labelSE, this.rev >= 0 && this.state.showExpunged, (v: boolean): void => {
            this.state.showExpunged = v;
            this.rev++;
          })
          Blank().layoutWeight(1)
        }.width('100%').alignItems(VerticalAlign.Center)
      }.width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }
}
