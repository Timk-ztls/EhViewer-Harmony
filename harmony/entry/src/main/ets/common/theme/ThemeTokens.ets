/*
 * Copyright 2026 ehviewer-harmony contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { Settings } from '../../hippo/ehviewer/Settings';
import { CategoryFlags } from '../../hippo/ehviewer/client/data/Flags';

const DOMAIN: number = 0x0000;
const TAG: string = 'ThemeTokens';

export class ThemeMode {
  static readonly LIGHT: number = 0;
  static readonly DARK: number = 1;
  static readonly BLACK: number = 2;
}

class PaletteSpec {
  colorPrimary: string = '#FF009688';
  colorPrimaryDark: string = '#FF00796B';
  colorAccent: string = '#FFE040FB';
  controlActivated: string = '#FF009688';
  toolbarColor: string = '#FF009688';
  toolbarTitleColor: string = '#FFFFFFFF';
  toolbarIconColor: string = '#FFFFFFFF';

  windowBackground: string = '#FFFFFFFF';
  surfaceBackground: string = '#FFFAFAFA';
  cardBackground: string = '#FFF5F5F5';
  cardActivatedBackground: string = '#FFE0E0E0';
  cardWhiteSurface: string = '#FFFFFFFF';
  popupBackground: string = '#FFF2F2F2';
  widgetBackground: string = '#FFEEEEEE';
  divider: string = '#20000000';
  shadowLight: string = '#38000000';

  textPrimary: string = '#DE000000';
  textSecondary: string = '#8A000000';
  textHint: string = '#61000000';
  textDisabled: string = '#61000000';
  textPrimaryInverse: string = '#FFFFFFFF';
  textSecondaryInverse: string = '#B3FFFFFF';
  textThemePrimary: string = '#FF009688';
  textThemePrimary2: string = '#FF1D87E4';
  textThemeAccent: string = '#FFE040FB';

  drawablePrimary: string = '#8A000000';
  drawableSecondary: string = '#42000000';
  drawableThemePrimary: string = '#FF009688';
  widgetThemePrimary: string = '#FF009688';
  widgetThemeAccent: string = '#FFE040FB';
  progressColor: string = '#FFE040FB';

  tagGroupBackground: string = '#FFE040FB';
  tagBackground: string = '#FF009688';
  galleryDetailHeaderBackground: string = '#FF009688';
  galleryDetailHeaderTitle: string = '#FFFFFFFF';
  galleryDetailButtonBackground: string = '#FFF5F5F5';
  gallerySliderBackground: string = '#FF424242';
  readerBackground: string = '#FF000000';
  readerOverlayScrim: string = '#CC000000';
  readerControlBg: string = '#33FFFFFF';
  readerControlDisabledBg: string = '#1AFFFFFF';
  drawerBackground: string = '#FFFFFFFF';
  drawerScrim: string = '#66000000';
  statusBarScrim: string = '#44000000';
  drawerActiveBackground: string = '#1F009688';
  drawerActiveColor: string = '#FF009688';
  themeChangeButtonText: string = '#FFE040FB';
  themeChangeButtonBg: string = '#FFFFFFFF';
  ratingStarColor: string = '#FFF9A825';
  errorColor: string = '#FFF44336';
  errorBannerBg: string = '#FFFDECEA';
  checkTextViewMask: string = '#8A000000';
  thumbPlaceholder: string = '#22000000';
  newVersionBg: string = '#E6FFEB3B';
  limitCountBg: string = '#FF009688';
  limitCountFill: string = '#4D009688';
  limitCountWarningFill: string = '#4DE53935';
  homeShadow: string = '#FFCFCFCF';
  dialogScrim: string = '#66000000';
  searchBarBackground: string = '#FFFFFFFF';
  fabIconColor: string = '#FFF5F5F5';
  rippleOverlay: string = '#1F000000';
  readerBackgroundDark: string = '#FF323232';
  readerSliderTrack: string = '#4DFFFFFF';
  readerTextShadow: string = '#CC000000';
  white: string = '#FFFFFFFF';
  black: string = '#FF000000';
  transparent: string = '#00000000';
}

export class ThemePalette {
  readonly colorPrimary: string;
  readonly colorPrimaryDark: string;
  readonly colorAccent: string;
  readonly controlActivated: string;
  readonly toolbarColor: string;
  readonly toolbarTitleColor: string;
  readonly toolbarIconColor: string;

  readonly windowBackground: string;
  readonly surfaceBackground: string;
  readonly cardBackground: string;
  readonly cardActivatedBackground: string;
  readonly cardWhiteSurface: string;
  readonly popupBackground: string;
  readonly widgetBackground: string;
  readonly divider: string;
  readonly shadowLight: string;

  readonly textPrimary: string;
  readonly textSecondary: string;
  readonly textHint: string;
  readonly textDisabled: string;
  readonly textPrimaryInverse: string;
  readonly textSecondaryInverse: string;
  readonly textThemePrimary: string;
  readonly textThemePrimary2: string;
  readonly textThemeAccent: string;

  readonly drawablePrimary: string;
  readonly drawableSecondary: string;
  readonly drawableThemePrimary: string;
  readonly widgetThemePrimary: string;
  readonly widgetThemeAccent: string;
  readonly progressColor: string;

  readonly tagGroupBackground: string;
  readonly tagBackground: string;
  readonly galleryDetailHeaderBackground: string;
  readonly galleryDetailHeaderTitle: string;
  readonly galleryDetailButtonBackground: string;
  readonly gallerySliderBackground: string;
  readonly readerBackground: string;
  readonly readerOverlayScrim: string;
  readonly readerControlBg: string;
  readonly readerControlDisabledBg: string;
  readonly drawerBackground: string;
  readonly drawerScrim: string;
  readonly statusBarScrim: string;
  readonly drawerActiveBackground: string;
  readonly drawerActiveColor: string;
  readonly themeChangeButtonText: string;
  readonly themeChangeButtonBg: string;
  readonly ratingStarColor: string;
  readonly errorColor: string;
  readonly errorBannerBg: string;
  readonly checkTextViewMask: string;
  readonly thumbPlaceholder: string;
  readonly newVersionBg: string;
  readonly limitCountBg: string;
  readonly limitCountFill: string;
  readonly limitCountWarningFill: string;
  readonly homeShadow: string;
  readonly dialogScrim: string;
  readonly searchBarBackground: string;
  readonly fabIconColor: string;
  readonly rippleOverlay: string;
  readonly readerBackgroundDark: string;
  readonly readerSliderTrack: string;
  readonly readerTextShadow: string;
  readonly white: string;
  readonly black: string;
  readonly transparent: string;

  private constructor(spec: PaletteSpec) {
    this.colorPrimary = spec.colorPrimary;
    this.colorPrimaryDark = spec.colorPrimaryDark;
    this.colorAccent = spec.colorAccent;
    this.controlActivated = spec.controlActivated;
    this.toolbarColor = spec.toolbarColor;
    this.toolbarTitleColor = spec.toolbarTitleColor;
    this.toolbarIconColor = spec.toolbarIconColor;

    this.windowBackground = spec.windowBackground;
    this.surfaceBackground = spec.surfaceBackground;
    this.cardBackground = spec.cardBackground;
    this.cardActivatedBackground = spec.cardActivatedBackground;
    this.cardWhiteSurface = spec.cardWhiteSurface;
    this.popupBackground = spec.popupBackground;
    this.widgetBackground = spec.widgetBackground;
    this.divider = spec.divider;
    this.shadowLight = spec.shadowLight;

    this.textPrimary = spec.textPrimary;
    this.textSecondary = spec.textSecondary;
    this.textHint = spec.textHint;
    this.textDisabled = spec.textDisabled;
    this.textPrimaryInverse = spec.textPrimaryInverse;
    this.textSecondaryInverse = spec.textSecondaryInverse;
    this.textThemePrimary = spec.textThemePrimary;
    this.textThemePrimary2 = spec.textThemePrimary2;
    this.textThemeAccent = spec.textThemeAccent;

    this.drawablePrimary = spec.drawablePrimary;
    this.drawableSecondary = spec.drawableSecondary;
    this.drawableThemePrimary = spec.drawableThemePrimary;
    this.widgetThemePrimary = spec.widgetThemePrimary;
    this.widgetThemeAccent = spec.widgetThemeAccent;
    this.progressColor = spec.progressColor;

    this.tagGroupBackground = spec.tagGroupBackground;
    this.tagBackground = spec.tagBackground;
    this.galleryDetailHeaderBackground = spec.galleryDetailHeaderBackground;
    this.galleryDetailHeaderTitle = spec.galleryDetailHeaderTitle;
    this.galleryDetailButtonBackground = spec.galleryDetailButtonBackground;
    this.gallerySliderBackground = spec.gallerySliderBackground;
    this.readerBackground = spec.readerBackground;
    this.readerOverlayScrim = spec.readerOverlayScrim;
    this.readerControlBg = spec.readerControlBg;
    this.readerControlDisabledBg = spec.readerControlDisabledBg;
    this.drawerBackground = spec.drawerBackground;
    this.drawerScrim = spec.drawerScrim;
    this.statusBarScrim = spec.statusBarScrim;
    this.drawerActiveBackground = spec.drawerActiveBackground;
    this.drawerActiveColor = spec.drawerActiveColor;
    this.themeChangeButtonText = spec.themeChangeButtonText;
    this.themeChangeButtonBg = spec.themeChangeButtonBg;
    this.ratingStarColor = spec.ratingStarColor;
    this.errorColor = spec.errorColor;
    this.errorBannerBg = spec.errorBannerBg;
    this.checkTextViewMask = spec.checkTextViewMask;
    this.thumbPlaceholder = spec.thumbPlaceholder;
    this.newVersionBg = spec.newVersionBg;
    this.limitCountBg = spec.limitCountBg;
    this.limitCountFill = spec.limitCountFill;
    this.limitCountWarningFill = spec.limitCountWarningFill;
    this.homeShadow = spec.homeShadow;
    this.dialogScrim = spec.dialogScrim;
    this.searchBarBackground = spec.searchBarBackground;
    this.fabIconColor = spec.fabIconColor;
    this.rippleOverlay = spec.rippleOverlay;
    this.readerBackgroundDark = spec.readerBackgroundDark;
    this.readerSliderTrack = spec.readerSliderTrack;
    this.readerTextShadow = spec.readerTextShadow;
    this.white = spec.white;
    this.black = spec.black;
    this.transparent = spec.transparent;
  }

  static createLight(): ThemePalette {
    const spec: PaletteSpec = new PaletteSpec();
    return new ThemePalette(spec);
  }

  static createDark(): ThemePalette {
    const spec: PaletteSpec = new PaletteSpec();
    spec.colorPrimary = '#FF009688';
    spec.colorPrimaryDark = '#FF212121';
    spec.colorAccent = '#FF009688';
    spec.controlActivated = '#FF009688';
    spec.toolbarColor = '#FF323232';
    spec.toolbarTitleColor = '#FFFFFFFF';
    spec.toolbarIconColor = '#FFFFFFFF';

    spec.windowBackground = '#FF323232';
    spec.surfaceBackground = '#FF303030';
    spec.cardBackground = '#FF3A3A3A';
    spec.cardActivatedBackground = '#FF757575';
    spec.cardWhiteSurface = '#FF3A3A3A';
    spec.popupBackground = '#FF2E2E2E';
    spec.widgetBackground = '#FF616161';
    spec.divider = '#20FFFFFF';

    spec.textPrimary = '#FFFFFFFF';
    spec.textSecondary = '#B3FFFFFF';
    spec.textHint = '#80FFFFFF';
    spec.textDisabled = '#4DFFFFFF';
    spec.textPrimaryInverse = '#DE000000';
    spec.textSecondaryInverse = '#8A000000';
    spec.textThemePrimary = '#B3FFFFFF';
    spec.textThemeAccent = '#B3FFFFFF';

    spec.drawablePrimary = '#FFFFFFFF';
    spec.drawableSecondary = '#4DFFFFFF';
    spec.drawableThemePrimary = '#FFFFFFFF';
    spec.widgetThemePrimary = '#FF616161';
    spec.widgetThemeAccent = '#FF616161';
    spec.progressColor = '#FF757575';

    spec.tagGroupBackground = '#FF4A4A4A';
    spec.tagBackground = '#FF4A4A4A';
    spec.galleryDetailHeaderBackground = '#FF3A3A3A';
    spec.galleryDetailHeaderTitle = '#FFFFFFFF';
    spec.galleryDetailButtonBackground = '#FF424242';
    spec.gallerySliderBackground = '#FF424242';
    spec.drawerBackground = '#FF323232';
    spec.drawerActiveBackground = '#33009688';
    spec.themeChangeButtonText = '#FF009688';
    spec.themeChangeButtonBg = '#FF323232';
    spec.errorBannerBg = '#FF3E2723';
    spec.thumbPlaceholder = '#22FFFFFF';
    spec.limitCountFill = '#66009688';
    spec.limitCountWarningFill = '#66E53935';
    spec.homeShadow = '#FF3A3A3A';
    spec.searchBarBackground = '#FF3A3A3A';
    spec.rippleOverlay = '#26FFFFFF';
    return new ThemePalette(spec);
  }

  static createBlack(): ThemePalette {
    const spec: PaletteSpec = new PaletteSpec();
    spec.colorPrimary = '#FF009688';
    spec.colorPrimaryDark = '#FF000000';
    spec.colorAccent = '#FF009688';
    spec.controlActivated = '#FF009688';
    spec.toolbarColor = '#FF000000';
    spec.toolbarTitleColor = '#D9FFFFFF';
    spec.toolbarIconColor = '#CCFFFFFF';

    spec.windowBackground = '#FF000000';
    spec.surfaceBackground = '#FF000000';
    spec.cardBackground = '#FF191919';
    spec.cardActivatedBackground = '#FF616161';
    spec.cardWhiteSurface = '#FF191919';
    spec.popupBackground = '#FF151515';
    spec.widgetBackground = '#FF323232';
    spec.divider = '#20FFFFFF';

    spec.textPrimary = '#D9FFFFFF';
    spec.textSecondary = '#99FFFFFF';
    spec.textHint = '#4DFFFFFF';
    spec.textDisabled = '#4DFFFFFF';
    spec.textPrimaryInverse = '#DE000000';
    spec.textSecondaryInverse = '#8A000000';
    spec.textThemePrimary = '#99FFFFFF';
    spec.textThemeAccent = '#99FFFFFF';

    spec.drawablePrimary = '#CCFFFFFF';
    spec.drawableSecondary = '#3DFFFFFF';
    spec.drawableThemePrimary = '#CCFFFFFF';
    spec.widgetThemePrimary = '#FF323232';
    spec.widgetThemeAccent = '#FF323232';
    spec.progressColor = '#FF616161';

    spec.tagGroupBackground = '#FF292929';
    spec.tagBackground = '#FF292929';
    spec.galleryDetailHeaderBackground = '#FF000000';
    spec.galleryDetailHeaderTitle = '#D9FFFFFF';
    spec.galleryDetailButtonBackground = '#FF212121';
    spec.gallerySliderBackground = '#FF212121';
    spec.drawerBackground = '#FF000000';
    spec.drawerActiveBackground = '#33009688';
    spec.themeChangeButtonText = '#FF009688';
    spec.themeChangeButtonBg = '#FF000000';
    spec.errorBannerBg = '#FF2B1111';
    spec.thumbPlaceholder = '#22FFFFFF';
    spec.limitCountFill = '#66009688';
    spec.limitCountWarningFill = '#66E53935';
    spec.homeShadow = '#FF3A3A3A';
    spec.searchBarBackground = '#FF191919';
    spec.rippleOverlay = '#26FFFFFF';
    return new ThemePalette(spec);
  }
}

export class CategoryColors {
  static readonly DOUJINSHI: string = '#FFF44336';
  static readonly MANGA: string = '#FFFF9800';
  static readonly ARTIST_CG: string = '#FFFBC02D';
  static readonly GAME_CG: string = '#FF4CAF50';
  static readonly WESTERN: string = '#FF8BC34A';
  static readonly NON_H: string = '#FF2196F3';
  static readonly IMAGE_SET: string = '#FF3F51B5';
  static readonly COSPLAY: string = '#FF9C27B0';
  static readonly ASIAN_PORN: string = '#FF9575CD';
  static readonly MISC: string = '#FFF06292';
  static readonly UNKNOWN: string = '#FF000000';

  static forCategory(category: number): string {
    switch (category) {
      case CategoryFlags.DOUJINSHI:
        return CategoryColors.DOUJINSHI;
      case CategoryFlags.MANGA:
        return CategoryColors.MANGA;
      case CategoryFlags.ARTIST_CG:
        return CategoryColors.ARTIST_CG;
      case CategoryFlags.GAME_CG:
        return CategoryColors.GAME_CG;
      case CategoryFlags.WESTERN:
        return CategoryColors.WESTERN;
      case CategoryFlags.NON_H:
        return CategoryColors.NON_H;
      case CategoryFlags.IMAGE_SET:
        return CategoryColors.IMAGE_SET;
      case CategoryFlags.COSPLAY:
        return CategoryColors.COSPLAY;
      case CategoryFlags.ASIAN_PORN:
        return CategoryColors.ASIAN_PORN;
      case CategoryFlags.MISC:
        return CategoryColors.MISC;
      default:
        return CategoryColors.UNKNOWN;
    }
  }
}

export class ThemeDimens {
  static readonly TOOLBAR_HEIGHT: number = 56;
  static readonly TOUCH_TARGET_MIN: number = 48;
  static readonly KEYLINE_MARGIN: number = 16;
  static readonly SPACING: number = 8;
  static readonly SPACING_XS: number = 4;
  static readonly SPACING_SM: number = 6;
  static readonly SPACING_MD: number = 12;
  static readonly DRAWER_MAX_WIDTH: number = 280;
  static readonly NAV_HEADER_HEIGHT: number = 160;
  static readonly NAV_AVATAR_SIZE: number = 64;

  static readonly GALLERY_LIST_THUMB_WIDTH: number = 80;
  static readonly GALLERY_LIST_THUMB_HEIGHT: number = 120;
  static readonly GALLERY_LIST_MARGIN_H: number = 4;
  static readonly GALLERY_LIST_MARGIN_V: number = 4;
  static readonly GALLERY_GRID_MARGIN_H: number = 4;
  static readonly GALLERY_GRID_MARGIN_V: number = 4;

  static readonly GALLERY_SEARCH_BAR_HEIGHT: number = 48;
  static readonly GALLERY_SEARCH_BAR_MARGIN_H: number = 6;
  static readonly GALLERY_SEARCH_BAR_MARGIN_V: number = 8;
  static readonly GALLERY_PADDING_TOP_SEARCH_BAR: number = 64;
  static readonly GALLERY_PADDING_BOTTOM_FAB: number = 80;

  static readonly GALLERY_DETAIL_THUMB_WIDTH: number = 128;
  static readonly GALLERY_DETAIL_THUMB_HEIGHT: number = 192;

  static readonly FAB_SIZE: number = 56;
  static readonly FAB_MINI_SIZE: number = 40;
  static readonly CORNER_FAB_MARGIN: number = 16;
  static readonly CORNER_FAB_MARGIN_DOWNLOAD_BOTTOM: number = 70;
  static readonly CORNER_FAB_MARGIN_DOWNLOAD_RIGHT: number = 3;
  static readonly FAB_LAYOUT_PRIMARY_MARGIN: number = 24;
  static readonly FAB_LAYOUT_SECONDARY_MARGIN: number = 16;

  static readonly CATEGORY_TABLE_ITEM_HEIGHT: number = 40;
  static readonly CATEGORY_TABLE_ITEM_MARGIN: number = 4;
  static readonly ADVANCE_SEARCH_TABLE_ITEM_MARGIN: number = 4;

  static readonly RATING_SIZE: number = 16;
  static readonly RATING_INTERVAL: number = 1;
  static readonly SEARCH_ITEM_INTERVAL: number = 8;
  static readonly SEARCH_CATEGORY_TITLE_HEIGHT: number = 48;
  static readonly PROGRESS_BAR_HEIGHT: number = 24;
  static readonly DIVIDER_HEIGHT: number = 1;
  static readonly TOOLBAR_SHADOW_HEIGHT: number = 8;

  static readonly GALLERY_WIDGET_MARGIN_H: number = 12;
  static readonly GALLERY_WIDGET_MARGIN_V: number = 12;

  static readonly GALLERY_LIST_COL_LONG: number = 480;
  static readonly GALLERY_LIST_COL_SHORT: number = 320;
  static readonly GALLERY_GRID_COL_LARGE: number = 160;
  static readonly GALLERY_GRID_COL_MIDDLE: number = 120;
  static readonly GALLERY_GRID_COL_SMALL: number = 80;

  static readonly ICON_SIZE_STANDARD: number = 24;
  static readonly ICON_SIZE_SMALL: number = 16;
  static readonly ICON_SIZE_LARGE: number = 48;

  static readonly PREF_ROW_MIN_HEIGHT: number = 48;
  static readonly PREF_TWO_LINE_MIN_HEIGHT: number = 64;

  static readonly IMAGE_SEARCH_MAX_SIZE: number = 240;
  static readonly GALLERY_PAGE_TEXT: number = 56;
  static readonly GALLERY_PROGRESS_SIZE: number = 56;
  static readonly GALLERY_ERROR_TEXT_SIZE: number = 24;
  static readonly GALLERY_PAGER_INTERVAL: number = 48;
  static readonly GALLERY_SCROLL_INTERVAL: number = 28;
  static readonly SEEK_BAR_PANEL_HEIGHT: number = 48;
  static readonly SEEK_BAR_PAGE_LABEL_WIDTH: number = 32;
  static readonly AUTO_TRANSFER_BUTTON_SIZE: number = 45;
  static readonly DIALOG_MAX_WIDTH: number = 340;
  static readonly DIALOG_PADDING_H: number = 24;
  static readonly DIALOG_ACTION_MIN_HEIGHT: number = 36;
  static readonly DOWNLOAD_ACTION_SIZE: number = 40;
  static readonly PROGRESS_LINEAR_HEIGHT: number = 4;
}

export class ThemeRadius {
  static readonly NONE: number = 0;
  static readonly CARD: number = 2;
  static readonly CARD_MATERIAL: number = 4;
  static readonly BUTTON: number = 4;
  static readonly SEARCH_BAR: number = 2;
  static readonly TAG: number = 2;
  static readonly CATEGORY_BADGE: number = 2;
  static readonly DIALOG: number = 4;
  static readonly NEW_VERSION_BADGE: number = 9;
  static readonly FAB_PRIMARY: number = 28;
  static readonly FAB_MINI: number = 20;
  static readonly AVATAR: number = 32;
}

export class ThemeTypography {
  static readonly TEXT_SUPER_LARGE: number = 24;
  static readonly TEXT_LARGE: number = 22;
  static readonly TEXT_LITTLE_LARGE: number = 20;
  static readonly TEXT_MEDIUM: number = 18;
  static readonly TEXT_LITTLE_SMALL: number = 16;
  static readonly TEXT_SMALL: number = 14;
  static readonly TEXT_SUPER_SMALL: number = 12;
  static readonly TEXT_GRID_LANG: number = 10;

  static readonly TOOLBAR_TITLE: number = 20;
  static readonly CARD_TITLE: number = 16;
  static readonly CARD_MESSAGE: number = 14;
  static readonly BUTTON: number = 14;
  static readonly PREF_TITLE: number = 16;
  static readonly PREF_SUMMARY: number = 14;
  static readonly PREF_CATEGORY: number = 14;
  static readonly DIALOG_TITLE: number = 20;
}

export class ThemeShadowOptions implements ShadowOptions {
  readonly radius: number;
  readonly color: string;
  readonly offsetX: number;
  readonly offsetY: number;

  constructor(radius: number, color: string, offsetX: number, offsetY: number) {
    this.radius = radius;
    this.color = color;
    this.offsetX = offsetX;
    this.offsetY = offsetY;
  }
}

export class ThemeElevation {
  static none(): ShadowOptions {
    return new ThemeShadowOptions(0, '#00000000', 0, 0);
  }

  static card(): ShadowOptions {
    return new ThemeShadowOptions(4, '#2E000000', 0, 1);
  }

  static searchBar(): ShadowOptions {
    return new ThemeShadowOptions(6, '#33000000', 0, 2);
  }

  static toolbar(): ShadowOptions {
    return new ThemeShadowOptions(8, '#38000000', 0, 2);
  }

  static fab(): ShadowOptions {
    return new ThemeShadowOptions(12, '#42000000', 0, 3);
  }

  static dialog(): ShadowOptions {
    return new ThemeShadowOptions(24, '#52000000', 0, 8);
  }
}

export class ThemeTokens {
  static readonly LIGHT: ThemePalette = ThemePalette.createLight();
  static readonly DARK: ThemePalette = ThemePalette.createDark();
  static readonly BLACK: ThemePalette = ThemePalette.createBlack();

  static of(themeId: number): ThemePalette {
    if (themeId === ThemeMode.DARK) {
      return ThemeTokens.DARK;
    }
    if (themeId === ThemeMode.BLACK) {
      return ThemeTokens.BLACK;
    }
    return ThemeTokens.LIGHT;
  }

  static getThemeId(): number {
    try {
      if (Settings.isAttached()) {
        const raw: number = Settings.getTheme();
        if (raw === ThemeMode.DARK || raw === ThemeMode.BLACK) {
          return raw;
        }
      }
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'getThemeId failed, fallback to LIGHT: %{public}s', msg);
    }
    return ThemeMode.LIGHT;
  }

  static current(): ThemePalette {
    return ThemeTokens.of(ThemeTokens.getThemeId());
  }
}
