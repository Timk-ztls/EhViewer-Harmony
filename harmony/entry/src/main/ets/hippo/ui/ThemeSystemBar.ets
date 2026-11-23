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

import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ColorMetrics, window } from '@kit.ArkUI';
import { ThemeMode, ThemePalette, ThemeTokens } from '../../common/theme/ThemeTokens';
import { Settings } from '../ehviewer/Settings';
import { PrivacySettingsRules } from '../ehviewer/ui/fragment/PrivacySettingsRules';
import {
  CachedThemeStartup,
  SYSTEM_COLOR_MODE_DARK,
  SYSTEM_COLOR_MODE_NOT_SET,
  ThemeAutoSwitchHelper
} from './ThemeAutoSwitchHelper';

const DOMAIN: number = 0x0000;
const TAG: string = 'ThemeSystemBar';
const THEME_CACHE_FILE: string = 'theme_id.cache';
const PRIVACY_CACHE_FILE: string = 'privacy_mode.cache';

export const APP_THEME_STORAGE_KEY: string = 'appThemeId';
export const APP_SYSTEM_COLOR_MODE_STORAGE_KEY: string = 'appSystemColorMode';
export const APP_SHOW_JPN_TITLE_STORAGE_KEY: string = 'appShowJpnTitle';
export const APP_SHOW_GALLERY_PAGES_STORAGE_KEY: string = 'appShowGalleryPages';
export const APP_SHOW_READ_PROGRESS_STORAGE_KEY: string = 'appShowReadProgress';

function themeStartBackgroundNumeric(themeId: number): number {
  if (themeId === ThemeMode.BLACK) {
    return 0xFF000000;
  }
  if (themeId === ThemeMode.DARK) {
    return 0xFF212121;
  }
  return 0xFFFFFFFF;
}

export function readCachedThemeStartup(
  ctx: common.Context | undefined,
  systemColorMode: number = ThemeAutoSwitchHelper.getSystemColorMode()
): CachedThemeStartup {
  if (ctx !== undefined) {
    try {
      const path: string = ctx.filesDir + '/' + THEME_CACHE_FILE;
      if (fs.accessSync(path)) {
        const raw: string = fs.readTextSync(path).trim();
        if (raw.length > 0) {
          return ThemeAutoSwitchHelper.decodeThemeCache(raw, systemColorMode);
        }
      }
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'readCachedThemeStartup failed: %{public}s', msg);
    }
  }
  return new CachedThemeStartup(ThemeTokens.getThemeId(), false, ThemeMode.DARK);
}

export function readCachedThemeId(ctx: common.Context | undefined): number {
  return readCachedThemeStartup(ctx, ThemeAutoSwitchHelper.getSystemColorMode()).themeId;
}

function writeCachedThemeStartup(
  ctx: common.Context | undefined,
  themeId: number,
  autoSwitch: boolean,
  darkVariant: number
): void {
  if (ctx === undefined) {
    return;
  }
  const path: string = ctx.filesDir + '/' + THEME_CACHE_FILE;
  const payload: string = ThemeAutoSwitchHelper.encodeThemeCache(themeId, autoSwitch, darkVariant);
  fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC)
    .then(async (file: fs.File): Promise<void> => {
      try {
        await fs.write(file.fd, payload);
      } finally {
        await fs.close(file);
      }
    })
    .catch((e: Error): void => {
      hilog.warn(DOMAIN, TAG, 'writeCachedThemeStartup failed: %{public}s', e.message);
    });
}

export function resolveActiveThemeId(): number {
  try {
    if (Settings.isAttached()) {
      return ThemeAutoSwitchHelper.resolveEffectiveTheme(
        Settings.getTheme(),
        Settings.isThemeAutoSwitchAvailable(),
        ThemeAutoSwitchHelper.getSystemColorMode(),
        Settings.getThemeDarkVariant()
      );
    }
  } catch (e) {
    const msg: string = e instanceof Error ? e.message : String(e);
    hilog.warn(DOMAIN, TAG, 'resolveActiveThemeId failed: %{public}s', msg);
  }
  return ThemeTokens.getThemeId();
}

export function syncAppThemeStorage(themeId?: number): number {
  const resolved: number = themeId !== undefined ? themeId : resolveActiveThemeId();
  try {
    AppStorage.setOrCreate<number>(APP_THEME_STORAGE_KEY, resolved);
  } catch (e) {
    const msg: string = e instanceof Error ? e.message : String(e);
    hilog.warn(DOMAIN, TAG, 'AppStorage sync failed: %{public}s', msg);
  }
  return resolved;
}

export function syncSystemColorModeStorage(colorMode: number): number {
  try {
    AppStorage.setOrCreate<number>(APP_SYSTEM_COLOR_MODE_STORAGE_KEY, colorMode);
  } catch (e) {
    const msg: string = e instanceof Error ? e.message : String(e);
    hilog.warn(DOMAIN, TAG, 'AppStorage systemColorMode sync failed: %{public}s', msg);
  }
  return colorMode;
}

export function syncAppShowJpnTitleStorage(enabled: boolean): boolean {
  try {
    AppStorage.setOrCreate<boolean>(APP_SHOW_JPN_TITLE_STORAGE_KEY, enabled);
  } catch (e) {
    const msg: string = e instanceof Error ? e.message : String(e);
    hilog.warn(DOMAIN, TAG, 'AppStorage showJpnTitle sync failed: %{public}s', msg);
  }
  return enabled;
}

export function syncAppShowGalleryPagesStorage(enabled: boolean): boolean {
  try {
    AppStorage.setOrCreate<boolean>(APP_SHOW_GALLERY_PAGES_STORAGE_KEY, enabled);
  } catch (e) {
    const msg: string = e instanceof Error ? e.message : String(e);
    hilog.warn(DOMAIN, TAG, 'AppStorage showGalleryPages sync failed: %{public}s', msg);
  }
  return enabled;
}

export function syncAppShowReadProgressStorage(enabled: boolean): boolean {
  try {
    AppStorage.setOrCreate<boolean>(APP_SHOW_READ_PROGRESS_STORAGE_KEY, enabled);
  } catch (e) {
    const msg: string = e instanceof Error ? e.message : String(e);
    hilog.warn(DOMAIN, TAG, 'AppStorage showReadProgress sync failed: %{public}s', msg);
  }
  return enabled;
}

export function applyWindowTheme(win: window.Window, themeId: number): void {
  const palette: ThemePalette = ThemeTokens.of(themeId);
  try {
    win.setWindowBackgroundColor(palette.windowBackground);
  } catch (e) {
    const msg: string = e instanceof Error ? e.message : String(e);
    hilog.warn(DOMAIN, TAG, 'setWindowBackgroundColor failed: %{public}s', msg);
  }
  const props: window.SystemBarProperties = {
    statusBarColor: palette.colorPrimaryDark,
    statusBarContentColor: '#FFFFFFFF',
    navigationBarColor: palette.drawerBackground,
    navigationBarContentColor: themeId === ThemeMode.LIGHT ? '#FF000000' : '#FFFFFFFF'
  };
  win.setWindowSystemBarProperties(props).catch((e: Error): void => {
    hilog.warn(DOMAIN, TAG, 'setWindowSystemBarProperties failed: %{public}s', e.message);
  });
}

export function applySystemBarTheme(
  ctx: common.Context | undefined,
  themeId: number,
  persistStartWindow: boolean = true,
  autoSwitchOverride?: boolean,
  updateAppColorMode: boolean = true
): void {
  if (ctx === undefined) {
    return;
  }
  window.getLastWindow(ctx).then((win: window.Window): void => {
    applyWindowTheme(win, themeId);
  }).catch((e: Error): void => {
    hilog.warn(DOMAIN, TAG, 'getLastWindow failed: %{public}s', e.message);
  });
  if (!persistStartWindow) {
    return;
  }
  const autoSwitch: boolean = autoSwitchOverride !== undefined
    ? autoSwitchOverride
    : (Settings.isAttached() ? Settings.isThemeAutoSwitchAvailable() : false);
  const darkVariant: number = Settings.isAttached()
    ? Settings.getThemeDarkVariant()
    : ThemeAutoSwitchHelper.normalizeDarkVariant(themeId);
  writeCachedThemeStartup(ctx, themeId, autoSwitch, darkVariant);
  if (updateAppColorMode) {
    try {
      const targetMode: number = ThemeAutoSwitchHelper.resolveApplicationColorMode(themeId, autoSwitch);
      let mode: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
      if (targetMode === SYSTEM_COLOR_MODE_NOT_SET) {
        mode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
      } else if (targetMode === SYSTEM_COLOR_MODE_DARK) {
        mode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      }
      ctx.getApplicationContext().setColorMode(mode);
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'setColorMode failed: %{public}s', msg);
    }
  }
  try {
    window.setStartWindowBackgroundColor(
      'entry',
      'EntryAbility',
      ColorMetrics.numeric(themeStartBackgroundNumeric(themeId))
    ).catch((e: Error): void => {
      hilog.warn(DOMAIN, TAG, 'setStartWindowBackgroundColor failed: %{public}s', e.message);
    });
  } catch (e) {
    const msg: string = e instanceof Error ? e.message : String(e);
    hilog.warn(DOMAIN, TAG, 'setStartWindowBackgroundColor threw: %{public}s', msg);
  }
}

function formatWindowError(err: BusinessError): string {
  const codePart: string = err.code !== undefined ? `code=${err.code}` : '';
  const msgPart: string = err.message !== undefined && err.message.length > 0 ? err.message : '';
  if (codePart.length > 0 && msgPart.length > 0) {
    return `${codePart} ${msgPart}`;
  }
  if (codePart.length > 0) {
    return codePart;
  }
  if (msgPart.length > 0) {
    return msgPart;
  }
  return String(err);
}

export function readCachedPrivacyMode(ctx: common.Context | undefined, fallback: boolean = false): boolean {
  if (ctx !== undefined) {
    try {
      const path: string = ctx.filesDir + '/' + PRIVACY_CACHE_FILE;
      if (fs.accessSync(path)) {
        const raw: string = fs.readTextSync(path);
        return PrivacySettingsRules.decodePrivacyCache(raw, fallback);
      }
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'readCachedPrivacyMode failed: %{public}s', msg);
    }
  }
  return fallback;
}

export function writeCachedPrivacyMode(ctx: common.Context | undefined, enabled: boolean): void {
  if (ctx === undefined) {
    return;
  }
  const path: string = ctx.filesDir + '/' + PRIVACY_CACHE_FILE;
  try {
    const file: fs.File = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, PrivacySettingsRules.encodePrivacyCache(enabled));
    } finally {
      fs.closeSync(file);
    }
  } catch (e) {
    const msg: string = e instanceof Error ? e.message : String(e);
    hilog.warn(DOMAIN, TAG, 'writeCachedPrivacyMode(%{public}s) failed: %{public}s', String(enabled), msg);
  }
}

export function applyWindowPrivacyToWindow(
  win: window.Window,
  enabled: boolean,
  onError?: (detail: string) => void
): void {
  win.setWindowPrivacyMode(enabled).then((): void => {
    hilog.info(DOMAIN, TAG, 'setWindowPrivacyMode(%{public}s) succeeded', String(enabled));
  }).catch((err: BusinessError): void => {
    const detail: string = formatWindowError(err);
    hilog.error(DOMAIN, TAG, 'setWindowPrivacyMode(%{public}s) failed: %{public}s',
      String(enabled), detail);
    if (onError !== undefined) {
      onError(detail);
    }
  });
}

export function applyWindowPrivacyMode(
  ctx: common.Context | undefined,
  enabled: boolean,
  persistCache: boolean = true,
  onError?: (detail: string) => void
): void {
  if (ctx === undefined) {
    hilog.warn(DOMAIN, TAG, 'applyWindowPrivacyMode(%{public}s): context is undefined', String(enabled));
    if (onError !== undefined) {
      onError('context unavailable');
    }
    return;
  }
  if (persistCache) {
    writeCachedPrivacyMode(ctx, enabled);
  }
  window.getLastWindow(ctx).then((win: window.Window): void => {
    applyWindowPrivacyToWindow(win, enabled, onError);
  }).catch((err: BusinessError): void => {
    const detail: string = formatWindowError(err);
    hilog.error(DOMAIN, TAG, 'getLastWindow for privacyMode(%{public}s) failed: %{public}s',
      String(enabled), detail);
    if (onError !== undefined) {
      onError(detail);
    }
  });
}
