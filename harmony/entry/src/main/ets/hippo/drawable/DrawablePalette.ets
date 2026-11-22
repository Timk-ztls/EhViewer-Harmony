/**
 * ui-widget · XML Drawable 重绘支撑层
 * 登记：inventory/ui-widget.extra.txt → harmony/entry/src/main/ets/hippo/drawable/
 *
 * 上游依据（只做值搬运，不做近似）：
 *   - app/src/main/res/values/colors.xml        具名颜色 156 条，本文件只列被 drawable 直接/间接引用的条目
 *   - app/src/main/res/values/themes.xml        BaseTheme(light) / DarkTheme / BlackTheme 三态属性取值
 *   - app/src/main/res/values/dimens.xml        appWidgetRadius=16dp / appWidgetInnerRadius=8dp 等
 *
 * 为什么要有这一层：Android 的 `?attr/xxx` 是主题属性，运行时按当前主题解析；ArkUI 没有主题属性体系，
 * 因此把三态取值显式展开成 LIGHT / DARK / BLACK 三个常量，由调用方（ui-scene）按当前主题传入，
 * 语义与上游一致，只是解析时机从"运行时读主题"变成"调用方显式给"。
 */

export enum ThemeMode {
  LIGHT = 0,
  DARK = 1,
  BLACK = 2
}

/** 与上游 themes.xml 三态一一对应的一组主题色 */
export interface DrawableTheme {
  readonly drawableColorPrimary: string;
  readonly drawableColorSecondary: string;
  readonly drawableColorThemePrimary: string;
  readonly colorAccent: string;
  readonly colorBackground: string;
  readonly textColorSecondary: string;
  readonly tagBackgroundColor: string;
  readonly limitsShapeColor: string;
  readonly popupWindow: string;
  readonly iconColor: string;
  readonly textColorThemePrimary: string;
}

export class DrawablePalette {
  /** 当前主题，由 ui-scene 在 AbilityStage/页面入口设置；drawable 组件的默认色取自 of(current) 的 LIGHT 常量 */
  static current: ThemeMode = ThemeMode.LIGHT;

  // ============================ 上游 colors.xml 具名色 ============================
  static readonly WHITE: string = '#FFFFFFFF';                       // @color/white
  static readonly BLACK: string = '#FF000000';                       // @android:color/black
  static readonly TRANSPARENT: string = '#00000000';                 // @android:color/transparent
  static readonly YELLOW_800: string = '#FFF9A825';                  // @color/yellow_800
  static readonly TEAL_500: string = '#FF009688';                    // @color/teal_500
  static readonly RED_500: string = '#FFF44336';                     // @color/red_500
  static readonly BROWN_500: string = '#FF795548';                   // @color/brown_500
  static readonly PURPLE_A200: string = '#FFE040FB';                 // @color/purple_a200
  static readonly GREY_100: string = '#FFF5F5F5';                    // @color/grey_100
  static readonly GREY_200: string = '#FFEEEEEE';                    // @color/grey_200
  static readonly GREY_800: string = '#FF424242';                    // @color/grey_800
  static readonly GREY_850: string = '#FF323232';                    // @color/grey_850
  static readonly GREY_900: string = '#FF212121';                    // @color/grey_900
  static readonly SHADOW_LIGHT: string = '#38000000';                // @color/shadow_light
  static readonly DIVIDER_LIGHT: string = '#20000000';               // @color/divider_light
  static readonly DIVIDER_DARK: string = '#20FFFFFF';                // @color/divider_dark
  static readonly NEW_VERSION_BG_COLOR: string = '#E6FFEB3B';        // @color/new_version_bg_color
  static readonly SHORTCUT_BG: string = '#FFF5F5F5';                 // @color/shortcut_bg
  static readonly TILE_BACKGROUND_ACTIVATED: string = '#7F9C27B0';   // values/drawables.xml <drawable name="tile_background_activated">
  static readonly PRIMARY_TEXT_DEFAULT_BLACK: string = '#D9FFFFFF';  // @color/primary_text_default_material_black
  static readonly PRIMARY_TEXT_DISABLED_BLACK: string = '#4DFFFFFF'; // @color/primary_text_disabled_material_black

  // ============================ ?attr/* 三态展开 ============================
  // ?attr/drawableColorPrimary ← light:@color/primary_drawable_light dark:@color/primary_drawable_dark black:@color/primary_drawable_black
  static readonly DRAWABLE_PRIMARY_LIGHT: string = '#8A000000';
  static readonly DRAWABLE_PRIMARY_DARK: string = '#FFFFFFFF';
  static readonly DRAWABLE_PRIMARY_BLACK: string = '#CCFFFFFF';
  // ?attr/drawableColorSecondary
  static readonly DRAWABLE_SECONDARY_LIGHT: string = '#42000000';
  static readonly DRAWABLE_SECONDARY_DARK: string = '#4DFFFFFF';
  static readonly DRAWABLE_SECONDARY_BLACK: string = '#3DFFFFFF';
  // ?attr/drawableColorThemePrimary ← light:@color/colorPrimary(=teal_500) dark:@color/primary_drawable_dark black:@color/primary_drawable_black
  static readonly DRAWABLE_THEME_PRIMARY_LIGHT: string = '#FF009688';
  static readonly DRAWABLE_THEME_PRIMARY_DARK: string = '#FFFFFFFF';
  static readonly DRAWABLE_THEME_PRIMARY_BLACK: string = '#CCFFFFFF';
  // ?attr/colorAccent ← light:@color/colorAccent(=purple_a200) dark:@color/colorPrimary(=teal_500) black:@android:color/white
  static readonly COLOR_ACCENT_LIGHT: string = '#FFE040FB';
  static readonly COLOR_ACCENT_DARK: string = '#FF009688';
  static readonly COLOR_ACCENT_BLACK: string = '#FFFFFFFF';
  // ?android:attr/colorBackground ← light:@color/white dark:@color/grey_850 black:@android:color/black
  static readonly COLOR_BACKGROUND_LIGHT: string = '#FFFFFFFF';
  static readonly COLOR_BACKGROUND_DARK: string = '#FF323232';
  static readonly COLOR_BACKGROUND_BLACK: string = '#FF000000';
  // ?android:attr/textColorSecondary ← MaterialComponents 默认三态
  static readonly TEXT_COLOR_SECONDARY_LIGHT: string = '#8A000000';
  static readonly TEXT_COLOR_SECONDARY_DARK: string = '#B3FFFFFF';
  static readonly TEXT_COLOR_SECONDARY_BLACK: string = '#B3FFFFFF';
  // ?attr/textColorThemePrimary ← light:@color/colorPrimary(=teal_500) dark/black:?android:attr/textColorSecondary
  static readonly TEXT_COLOR_THEME_PRIMARY_LIGHT: string = '#FF009688';
  static readonly TEXT_COLOR_THEME_PRIMARY_DARK: string = '#B3FFFFFF';
  static readonly TEXT_COLOR_THEME_PRIMARY_BLACK: string = '#B3FFFFFF';
  // ?attr/tagBackgroundColor ← light:@color/tag_background_light(=colorPrimary) dark:grey_775 black:grey_875
  static readonly TAG_BACKGROUND_LIGHT: string = '#FF009688';
  static readonly TAG_BACKGROUND_DARK: string = '#FF4A4A4A';
  static readonly TAG_BACKGROUND_BLACK: string = '#FF292929';
  // ?attr/limits_shape_color ← light:@color/shape_color_limits(=teal_500) dark:@color/shape_color_limits_dart(=grey_675) black:grey_675
  static readonly LIMITS_SHAPE_LIGHT: string = '#FF009688';
  static readonly LIMITS_SHAPE_DARK: string = '#FF666666';
  static readonly LIMITS_SHAPE_BLACK: string = '#FF666666';
  // ?attr/popupWindowStyle ← light:popupWindow_background_light dark:_dark black:_black
  static readonly POPUP_WINDOW_LIGHT: string = '#FFF2F2F2';
  static readonly POPUP_WINDOW_DARK: string = '#FF2E2E2E';
  static readonly POPUP_WINDOW_BLACK: string = '#FF151515';
  // ?attr/iconColor ← light:@color/icon_color dark:@color/icon_color_dark black:@color/icon_color_black，三者均为 @color/grey_100
  static readonly ICON_COLOR_LIGHT: string = '#FFF5F5F5';
  static readonly ICON_COLOR_DARK: string = '#FFF5F5F5';
  static readonly ICON_COLOR_BLACK: string = '#FFF5F5F5';

  // ============================ appWidget dimens（themes.xml 内联 dp） ============================
  static readonly APP_WIDGET_RADIUS: number = 16;       // ?attr/appWidgetRadius   = 16dp
  static readonly APP_WIDGET_INNER_RADIUS: number = 8;  // ?attr/appWidgetInnerRadius = 8dp

  /** 按主题取整组颜色（ui-scene 切换主题时调用，等价上游 Resources.getTheme() 的属性解析） */
  static of(mode: ThemeMode): DrawableTheme {
    let t: DrawableTheme;
    if (mode === ThemeMode.DARK) {
      t = {
        drawableColorPrimary: DrawablePalette.DRAWABLE_PRIMARY_DARK,
        drawableColorSecondary: DrawablePalette.DRAWABLE_SECONDARY_DARK,
        drawableColorThemePrimary: DrawablePalette.DRAWABLE_THEME_PRIMARY_DARK,
        colorAccent: DrawablePalette.COLOR_ACCENT_DARK,
        colorBackground: DrawablePalette.COLOR_BACKGROUND_DARK,
        textColorSecondary: DrawablePalette.TEXT_COLOR_SECONDARY_DARK,
        tagBackgroundColor: DrawablePalette.TAG_BACKGROUND_DARK,
        limitsShapeColor: DrawablePalette.LIMITS_SHAPE_DARK,
        popupWindow: DrawablePalette.POPUP_WINDOW_DARK,
        iconColor: DrawablePalette.ICON_COLOR_DARK,
        textColorThemePrimary: DrawablePalette.TEXT_COLOR_THEME_PRIMARY_DARK
      };
    } else if (mode === ThemeMode.BLACK) {
      t = {
        drawableColorPrimary: DrawablePalette.DRAWABLE_PRIMARY_BLACK,
        drawableColorSecondary: DrawablePalette.DRAWABLE_SECONDARY_BLACK,
        drawableColorThemePrimary: DrawablePalette.DRAWABLE_THEME_PRIMARY_BLACK,
        colorAccent: DrawablePalette.COLOR_ACCENT_BLACK,
        colorBackground: DrawablePalette.COLOR_BACKGROUND_BLACK,
        textColorSecondary: DrawablePalette.TEXT_COLOR_SECONDARY_BLACK,
        tagBackgroundColor: DrawablePalette.TAG_BACKGROUND_BLACK,
        limitsShapeColor: DrawablePalette.LIMITS_SHAPE_BLACK,
        popupWindow: DrawablePalette.POPUP_WINDOW_BLACK,
        iconColor: DrawablePalette.ICON_COLOR_BLACK,
        textColorThemePrimary: DrawablePalette.TEXT_COLOR_THEME_PRIMARY_BLACK
      };
    } else {
      t = {
        drawableColorPrimary: DrawablePalette.DRAWABLE_PRIMARY_LIGHT,
        drawableColorSecondary: DrawablePalette.DRAWABLE_SECONDARY_LIGHT,
        drawableColorThemePrimary: DrawablePalette.DRAWABLE_THEME_PRIMARY_LIGHT,
        colorAccent: DrawablePalette.COLOR_ACCENT_LIGHT,
        colorBackground: DrawablePalette.COLOR_BACKGROUND_LIGHT,
        textColorSecondary: DrawablePalette.TEXT_COLOR_SECONDARY_LIGHT,
        tagBackgroundColor: DrawablePalette.TAG_BACKGROUND_LIGHT,
        limitsShapeColor: DrawablePalette.LIMITS_SHAPE_LIGHT,
        popupWindow: DrawablePalette.POPUP_WINDOW_LIGHT,
        iconColor: DrawablePalette.ICON_COLOR_LIGHT,
        textColorThemePrimary: DrawablePalette.TEXT_COLOR_THEME_PRIMARY_LIGHT
      };
    }
    return t;
  }

  /** 当前主题 */
  static theme(): DrawableTheme {
    return DrawablePalette.of(DrawablePalette.current);
  }
}
