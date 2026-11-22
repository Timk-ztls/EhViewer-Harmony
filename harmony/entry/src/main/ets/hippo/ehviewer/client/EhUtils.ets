/*
 * Copyright 2016 Hippo Seven
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

import { GalleryInfo } from './data/GalleryInfo';
import { CategoryFlags } from './data/Flags';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/EhUtils.kt
 * （inventory S0081，182 行）
 *
 * 分类位/颜色/标题清洗/缩略图分辨率。storage-db 的 SpiderQueen 与 ui-scene 的列表项都依赖它，
 * 故优先交付（Lead 要求插在 parser 之前）。
 *
 * ArkTS 映射：
 *   Kotlin `object EhUtils`（单例）      → 本文件全部 static 成员（等价于 Java 里的静态工具类）
 *   Kotlin 两个 `getCategory` 重载        → getCategoryByType(String) / getCategoryByValue(Int)
 *   `when` 分支                          → switch
 *   `Color.BLACK`                        → -0x1000000（ARGB 0xFF000000 的有符号表示，与 Android 一致）
 *
 * 依赖注入（Settings 属 core-runtime，尚未落地）：只影响 3 个函数
 *   getShowJpnTitle / getThumbResolution / signOut & needSignedIn
 * 用 EhUtilsConfig 注入，默认值与上游默认一致（showJpnTitle=false、thumbResolution=0）；
 * core-runtime 的 Settings 落地后接线一次即可，行为与上游一致。
 */
/**
 * EhUtils 的平台依赖注入点（Settings / EhApplication）。
 * 默认实现 = 上游默认值，保证未接线时行为与「用户从未改过设置」一致。
 */
export class EhUtilsConfig {
  getShowJpnTitle(): boolean {
    return false;
  }

  getThumbResolution(): number {
    return 0;
  }

  signOut(): void {
    // 未接线：core-runtime 的 EhCookieStore/Settings 落地后由 setConfig 替换
  }

  needSignedIn(): boolean {
    return false;
  }
}

export class EhUtils {
  /** Use it for homepage（EhUtils.kt:28）。 */
  static readonly NONE: number = -1;
  static readonly UNKNOWN: number = 0x400;
  /** ALL_CATEGORY = UNKNOWN - 1（EhUtils.kt:31）。 */
  static readonly ALL_CATEGORY: number = EhUtils.UNKNOWN - 1;

  static readonly BG_COLOR_DOUJINSHI: number = -0xbbcca;
  static readonly BG_COLOR_MANGA: number = -0x6800;
  static readonly BG_COLOR_ARTIST_CG: number = -0x43fd3;
  static readonly BG_COLOR_GAME_CG: number = -0xb350b0;
  static readonly BG_COLOR_WESTERN: number = -0x743cb6;
  static readonly BG_COLOR_NON_H: number = -0xde690d;
  static readonly BG_COLOR_IMAGE_SET: number = -0xc0ae4b;
  static readonly BG_COLOR_COSPLAY: number = -0x63d850;
  static readonly BG_COLOR_ASIAN_PORN: number = -0x6a8a33;
  static readonly BG_COLOR_MISC: number = -0xf9d6e;
  /** Color.BLACK = 0xFF000000 = -0x1000000 */
  static readonly BG_COLOR_UNKNOWN: number = -0x1000000;

  /** Remove [XXX], (XXX), {XXX}, ~XXX~ stuff（逐字符照搬 EhUtils.kt:46-48）。 */
  private static readonly PATTERN_TITLE_PREFIX: RegExp =
    /^(?:(?:\([^\)]*\))|(?:\[[^\]]*\])|(?:\{[^\}]*\})|(?:~[^~]*~)|\s+)*/;

  /** 同上去掉尾部，并去掉 `ch. 1-23` 这类（EhUtils.kt:51-54，CASE_INSENSITIVE）。 */
  private static readonly PATTERN_TITLE_SUFFIX: RegExp =
    /(?:\s+ch.[\s\d-]+)?(?:(?:\([^\)]*\))|(?:\[[^\]]*\])|(?:\{[^\}]*\})|(?:~[^~]*~)|\s+)*$/i;

  private static readonly CATEGORY_VALUES: number[] = [
    CategoryFlags.MISC,
    CategoryFlags.DOUJINSHI,
    CategoryFlags.MANGA,
    CategoryFlags.ARTIST_CG,
    CategoryFlags.GAME_CG,
    CategoryFlags.IMAGE_SET,
    CategoryFlags.COSPLAY,
    CategoryFlags.ASIAN_PORN,
    CategoryFlags.NON_H,
    CategoryFlags.WESTERN,
    EhUtils.UNKNOWN
  ];

  private static readonly CATEGORY_STRINGS: string[][] = [
    ['misc'],
    ['doujinshi'],
    ['manga'],
    ['artistcg', 'Artist CG Sets', 'Artist CG'],
    ['gamecg', 'Game CG Sets', 'Game CG'],
    ['imageset', 'Image Sets', 'Image Set'],
    ['cosplay'],
    ['asianporn', 'Asian Porn'],
    ['non-h'],
    ['western'],
    ['unknown']
  ];

  private static _config: EhUtilsConfig = new EhUtilsConfig();

  /** core-runtime 的 Settings 落地后接线：setConfig(new SettingsBackedConfig(...))。 */
  static setConfig(config: EhUtilsConfig): void {
    EhUtils._config = config;
  }

  /** 对齐 getCategory(String? type)：字符串 → 分类位，未知 → UNKNOWN。 */
  static getCategoryByType(type: string | null): number {
    let i: number = 0;
    while (i < EhUtils.CATEGORY_STRINGS.length - 1) {
      const candidates: string[] = EhUtils.CATEGORY_STRINGS[i];
      for (let k = 0; k < candidates.length; k++) {
        if (type !== null && candidates[k].toLowerCase() === type.toLowerCase()) {
          return EhUtils.CATEGORY_VALUES[i];
        }
      }
      i++;
    }
    return EhUtils.CATEGORY_VALUES[i];
  }

  /** 对齐 getCategory(Int type)：分类位 → 规范字符串（取第一项），未知 → "unknown"。 */
  static getCategoryByValue(type: number): string {
    let i: number = 0;
    while (i < EhUtils.CATEGORY_VALUES.length - 1) {
      if (EhUtils.CATEGORY_VALUES[i] === type) {
        break;
      }
      i++;
    }
    return EhUtils.CATEGORY_STRINGS[i][0];
  }

  /** 对齐 getCategoryColor(Int)。 */
  static getCategoryColor(category: number): number {
    switch (category) {
      case CategoryFlags.DOUJINSHI:
        return EhUtils.BG_COLOR_DOUJINSHI;
      case CategoryFlags.MANGA:
        return EhUtils.BG_COLOR_MANGA;
      case CategoryFlags.ARTIST_CG:
        return EhUtils.BG_COLOR_ARTIST_CG;
      case CategoryFlags.GAME_CG:
        return EhUtils.BG_COLOR_GAME_CG;
      case CategoryFlags.WESTERN:
        return EhUtils.BG_COLOR_WESTERN;
      case CategoryFlags.NON_H:
        return EhUtils.BG_COLOR_NON_H;
      case CategoryFlags.IMAGE_SET:
        return EhUtils.BG_COLOR_IMAGE_SET;
      case CategoryFlags.COSPLAY:
        return EhUtils.BG_COLOR_COSPLAY;
      case CategoryFlags.ASIAN_PORN:
        return EhUtils.BG_COLOR_ASIAN_PORN;
      case CategoryFlags.MISC:
        return EhUtils.BG_COLOR_MISC;
      default:
        return EhUtils.BG_COLOR_UNKNOWN;
    }
  }

  /** 对齐 signOut(Context)：依赖 EhApplication/CookieStore/Settings（core-runtime）。 */
  static signOut(): void {
    EhUtils._config.signOut();
  }

  /** 对齐 needSignedIn(Context)。 */
  static needSignedIn(): boolean {
    return EhUtils._config.needSignedIn();
  }

  /** 对齐 getSuitableTitle(GalleryInfo)。 */
  static getSuitableTitle(gi: GalleryInfo): string | null {
    if (EhUtils._config.getShowJpnTitle()) {
      return gi.titleJpn.length === 0 ? gi.title : gi.titleJpn;
    }
    return gi.title.length === 0 ? gi.titleJpn : gi.title;
  }

  /** 对齐 judgeSuitableTitle(GalleryInfo, String)。 */
  static judgeSuitableTitle(gi: GalleryInfo, key: string): boolean {
    const titleB: string = gi.titleJpn + '' + gi.title;
    return titleB.indexOf(key) >= 0;
  }

  /** 对齐 extractTitle(String?)：去前后缀装饰 + 取 '|' 之前的罗马字部分。 */
  static extractTitle(titleIn: string | null): string | null {
    let title: string = titleIn === null || titleIn === undefined ? '' : titleIn;
    if (titleIn === null || titleIn === undefined) {
      return null;
    }
    title = title.replace(EhUtils.PATTERN_TITLE_PREFIX, '');
    title = title.replace(EhUtils.PATTERN_TITLE_SUFFIX, '');
    const index: number = title.indexOf('|');
    if (index >= 0) {
      title = title.substring(0, index);
    }
    return title.length === 0 ? null : title;
  }

  /**
   * 对齐 handleThumbUrlResolution(String?)：把 `<prefix>_<res>.<ext>` 里的分辨率换掉。
   * 上游只有 250 / 300 两档（Settings.getThumbResolution() 0=不改）。
   */
  static handleThumbUrlResolution(url: string | null): string | null {
    if (url === null || url === undefined) {
      return null;
    }
    let resolution: string;
    switch (EhUtils._config.getThumbResolution()) {
      case 0:
        return url;
      case 1:
        resolution = '250';
        break;
      case 2:
        resolution = '300';
        break;
      default:
        return url;
    }
    const index1: number = url.lastIndexOf('_');
    const index2: number = url.lastIndexOf('.');
    if (index1 >= 0 && index2 >= 0 && index1 < index2) {
      return url.substring(0, index1 + 1) + resolution + url.substring(index2);
    }
    return url;
  }
}

