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

/** Mirrors `ThemeMode` / `Settings.THEME_*` numeric constants without UI-only `ShadowOptions` imports. */
export const THEME_MODE_LIGHT: number = 0;
export const THEME_MODE_DARK: number = 1;
export const THEME_MODE_BLACK: number = 2;

/** Mirrors `ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET`. */
export const SYSTEM_COLOR_MODE_NOT_SET: number = -1;
/** Mirrors `ConfigurationConstant.ColorMode.COLOR_MODE_DARK`. */
export const SYSTEM_COLOR_MODE_DARK: number = 0;
/** Mirrors `ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT`. */
export const SYSTEM_COLOR_MODE_LIGHT: number = 1;

export class CachedThemeStartup {
  readonly themeId: number;
  readonly autoSwitch: boolean;
  readonly darkVariant: number;

  constructor(themeId: number, autoSwitch: boolean, darkVariant: number) {
    this.themeId = themeId;
    this.autoSwitch = autoSwitch;
    this.darkVariant = darkVariant;
  }
}

/**
 * Pure TypeScript helper for resolving system color mode, three-state theme mapping,
 * startup cache serialization, and `applicationContext.setColorMode` targets.
 */
export class ThemeAutoSwitchHelper {
  private static sSystemColorMode: number = SYSTEM_COLOR_MODE_NOT_SET;

  static setSystemColorMode(mode: number | undefined): number {
    if (mode === SYSTEM_COLOR_MODE_DARK || mode === SYSTEM_COLOR_MODE_LIGHT) {
      ThemeAutoSwitchHelper.sSystemColorMode = mode;
    } else if (
      mode === SYSTEM_COLOR_MODE_NOT_SET &&
      ThemeAutoSwitchHelper.sSystemColorMode === SYSTEM_COLOR_MODE_NOT_SET
    ) {
      ThemeAutoSwitchHelper.sSystemColorMode = SYSTEM_COLOR_MODE_NOT_SET;
    }
    return ThemeAutoSwitchHelper.sSystemColorMode;
  }

  static getSystemColorMode(): number {
    return ThemeAutoSwitchHelper.sSystemColorMode;
  }

  static isSystemDark(): boolean {
    return ThemeAutoSwitchHelper.sSystemColorMode === SYSTEM_COLOR_MODE_DARK;
  }

  static resetForTest(): void {
    ThemeAutoSwitchHelper.sSystemColorMode = SYSTEM_COLOR_MODE_NOT_SET;
  }

  static normalizeThemeId(themeId: number): number {
    if (themeId === THEME_MODE_DARK || themeId === THEME_MODE_BLACK) {
      return themeId;
    }
    return THEME_MODE_LIGHT;
  }

  static normalizeDarkVariant(themeId: number): number {
    return themeId === THEME_MODE_BLACK ? THEME_MODE_BLACK : THEME_MODE_DARK;
  }

  static resolveEffectiveTheme(
    savedTheme: number,
    autoSwitch: boolean,
    systemColorMode: number,
    darkVariant: number = THEME_MODE_DARK
  ): number {
    const normSaved: number = ThemeAutoSwitchHelper.normalizeThemeId(savedTheme);
    if (!autoSwitch) {
      return normSaved;
    }
    if (systemColorMode === SYSTEM_COLOR_MODE_DARK) {
      return (darkVariant === THEME_MODE_BLACK || normSaved === THEME_MODE_BLACK)
        ? THEME_MODE_BLACK
        : THEME_MODE_DARK;
    }
    if (systemColorMode === SYSTEM_COLOR_MODE_LIGHT) {
      return THEME_MODE_LIGHT;
    }
    return normSaved;
  }

  /**
   * Resolves the target `ConfigurationConstant.ColorMode` for `applicationContext.setColorMode(...)`.
   * CRITICAL: When `autoSwitch` is enabled, ALWAYS return `COLOR_MODE_NOT_SET (-1)` so ArkUI
   * continues delivering `EntryAbility.onConfigurationUpdate` callbacks on system dark-mode switches.
   */
  static resolveApplicationColorMode(effectiveThemeId: number, autoSwitch: boolean): number {
    if (autoSwitch) {
      return SYSTEM_COLOR_MODE_NOT_SET;
    }
    return effectiveThemeId === THEME_MODE_LIGHT
      ? SYSTEM_COLOR_MODE_LIGHT
      : SYSTEM_COLOR_MODE_DARK;
  }

  static shouldDisableAutoSwitchOnManualTheme(
    chosenTheme: number,
    autoSwitch: boolean,
    systemColorMode: number
  ): boolean {
    if (!autoSwitch) {
      return false;
    }
    const normalized: number = ThemeAutoSwitchHelper.normalizeThemeId(chosenTheme);
    if (systemColorMode === SYSTEM_COLOR_MODE_DARK) {
      return normalized === THEME_MODE_LIGHT;
    }
    if (systemColorMode === SYSTEM_COLOR_MODE_LIGHT) {
      return normalized !== THEME_MODE_LIGHT;
    }
    return true;
  }

  static resolveSystemThemeStringKey(systemColorMode: number): string {
    if (systemColorMode === SYSTEM_COLOR_MODE_DARK) {
      return 'settings_eh_theme_dark';
    }
    if (systemColorMode === SYSTEM_COLOR_MODE_LIGHT) {
      return 'settings_eh_theme_light';
    }
    return '';
  }

  static encodeThemeCache(themeId: number, autoSwitch: boolean, darkVariant: number): string {
    const normTheme: number = ThemeAutoSwitchHelper.normalizeThemeId(themeId);
    const autoFlag: number = autoSwitch ? 1 : 0;
    const normDark: number = ThemeAutoSwitchHelper.normalizeDarkVariant(darkVariant);
    return `${normTheme}|${autoFlag}|${normDark}`;
  }

  static decodeThemeCache(raw: string, systemColorMode: number): CachedThemeStartup {
    const trimmed: string = raw.trim();
    if (trimmed.length === 0) {
      return new CachedThemeStartup(THEME_MODE_LIGHT, false, THEME_MODE_DARK);
    }
    const parts: string[] = trimmed.split('|');
    const savedTheme: number = ThemeAutoSwitchHelper.normalizeThemeId(Number(parts[0]));
    const autoSwitch: boolean = parts.length >= 2 && parts[1] === '1';
    const rawDark: number = parts.length >= 3 ? Number(parts[2]) : savedTheme;
    const darkVariant: number = ThemeAutoSwitchHelper.normalizeDarkVariant(rawDark);
    const effective: number = ThemeAutoSwitchHelper.resolveEffectiveTheme(
      savedTheme,
      autoSwitch,
      systemColorMode,
      darkVariant
    );
    return new CachedThemeStartup(effective, autoSwitch, darkVariant);
  }
}
