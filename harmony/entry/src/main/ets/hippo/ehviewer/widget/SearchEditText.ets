/**
 * Material borderless SearchEditText aligned with Android SearchEditText.java & widget_search_bar.xml.
 */

import {
  ThemeDimens,
  ThemePalette,
  ThemeRadius,
  ThemeTokens,
  ThemeTypography,
} from '../../../common/theme/ThemeTokens';

export interface SearchEditTextListener {
  onClick(): void;

  onBackPressed(): void;
}

export class SearchEditTextListenerImpl implements SearchEditTextListener {
  private readonly onClickFn: () => void;
  private readonly onBackFn: () => void;

  constructor(clickFn: () => void, backFn: () => void) {
    this.onClickFn = clickFn;
    this.onBackFn = backFn;
  }

  onClick(): void {
    this.onClickFn();
  }

  onBackPressed(): void {
    this.onBackFn();
  }
}

@Component
export struct SearchEditText {
  @Prop text: string = '';
  @Prop placeholder: string = '';
  @Prop themeId: number = -1;
  listener: SearchEditTextListener | null = null;
  onTextChange: (value: string) => void = (): void => {
  };
  onSubmitAction: (value: string) => void = (): void => {
  };

  private resolvePalette(): ThemePalette {
    if (this.themeId >= 0) {
      return ThemeTokens.of(this.themeId);
    }
    return ThemeTokens.current();
  }

  build(): void {
    this.buildEditor();
  }

  @Builder
  private buildEditor(): void {
    TextInput({ text: this.text, placeholder: this.placeholder })
      .width('100%')
      .height(ThemeDimens.GALLERY_SEARCH_BAR_HEIGHT)
      .padding({ left: 0, right: 0, top: 0, bottom: 0 })
      .backgroundColor(this.resolvePalette().transparent)
      .borderRadius(ThemeRadius.NONE)
      .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
      .fontColor(this.resolvePalette().textPrimary)
      .placeholderColor(this.resolvePalette().textHint)
      .placeholderFont({ size: ThemeTypography.TEXT_LITTLE_SMALL })
      .caretColor(this.resolvePalette().controlActivated)
      .enterKeyType(EnterKeyType.Search)
      .maxLines(1)
      .onChange((value: string): void => {
        this.onTextChange(value);
      })
      .onSubmit((_enterKey: EnterKeyType): void => {
        this.onSubmitAction(this.text);
      })
      .onClick((): void => {
        if (this.listener !== null) {
          this.listener.onClick();
        }
      })
  }
}
