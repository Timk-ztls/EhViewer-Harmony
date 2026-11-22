/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0430   上游: com/hippo/lib/yorozuya/Utilities.java（100 行）
 * 目标   : harmony/entry/src/main/ets/hippo/lib/yorozuya/Utilities.ets
 *
 * 平台差异：
 *  1. contain(Object[], Object) / contain(char[], char) 重载 → containObject / containChar。
 *     char[] 在 ArkTS 无对应类型，按"单字符字符串数组" string[] 表达（上游 char[] 的唯一来源是
 *     String.toCharArray()，改写处用 string.split('') 或逐字符数组即可）。
 *  2. android.text.TextUtils.isEmpty → 内联 `s === null || s === undefined || s.length === 0`
 *     （语义相同：null 或空串才算 empty，不 trim）。
 *  3. android.webkit.MimeTypeMap（系统 600+ 条映射）在鸿蒙无等价公开 API → 本类内置覆盖
 *     EhViewer 实际用到的类型表 + Android 原表里的 image/jpg 别名；未知类型返回 undefined
 *     （对应 Java null）。若后续模块需要更多类型，按 MR 反馈补齐该表。
 *  4. java.util.regex.Pattern.matches → ArkTS RegExp.test，正则原文逐字保留。
 *  5. ObjectUtils.equal 已在同批落地（S0417），故直接调用，不再内联（行为与 Java Objects.equals 一致）。
 */

import { ObjectUtils } from './ObjectUtils';

export class Utilities {

  private static readonly MIME_TYPE_ARRAY: string[] = [
    'image/jpg'
  ];

  private static readonly EXTENSION_ARRAY: string[] = [
    'jpg'
  ];

  /** Android MimeTypeMap 常用子集的等价表（见文件头差异 3） */
  private static readonly MIME_TO_EXT: Map<string, string> = Utilities.buildMimeTable();

  private static buildMimeTable(): Map<string, string> {
    const m: Map<string, string> = new Map<string, string>();
    m.set('image/jpeg', 'jpg');
    m.set('image/png', 'png');
    m.set('image/gif', 'gif');
    m.set('image/webp', 'webp');
    m.set('image/bmp', 'bmp');
    m.set('image/x-icon', 'ico');
    m.set('image/svg+xml', 'svg');
    m.set('text/plain', 'txt');
    m.set('text/html', 'html');
    m.set('application/xhtml+xml', 'xhtml');
    m.set('application/json', 'json');
    m.set('application/xml', 'xml');
    m.set('application/zip', 'zip');
    m.set('application/x-bittorrent', 'torrent');
    m.set('application/pdf', 'pdf');
    m.set('video/mp4', 'mp4');
    m.set('audio/mpeg', 'mp3');
    return m;
  }

  /**
   * Whether the array contain the element (against Object[])
   */
  static containObject(array: Array<Object> | null | undefined, obj: Object | null | undefined): boolean {
    if (array === null || array === undefined) {
      return false;
    }
    for (let i = 0; i < array.length; i++) {
      if (ObjectUtils.equal(array[i], obj)) {
        return true;
      }
    }
    return false;
  }

  /**
   * Whether the array contain the element (against char[], 用单字符字符串表达)
   */
  static containChar(array: string[] | null | undefined, ch: string): boolean {
    if (array === null || array === undefined) {
      return false;
    }
    for (let i = 0; i < array.length; i++) {
      if (array[i] === ch) {
        return true;
      }
    }
    return false;
  }

  static getNameFromUrl(url: string): string | undefined {
    if (url !== null && url !== undefined && url.length !== 0) {
      let u: string = url;
      const fragment: number = u.lastIndexOf('#');
      if (fragment > 0) {
        u = u.substring(0, fragment);
      }

      const query: number = u.lastIndexOf('?');
      if (query > 0) {
        u = u.substring(0, query);
      }

      const filenamePos: number = u.lastIndexOf('/');
      const filename: string = 0 <= filenamePos ? u.substring(filenamePos + 1) : u;

      // if the filename contains special characters, we don't
      // consider it valid for our matching purposes:
      if (filename.length !== 0 && new RegExp('^[a-zA-Z_0-9\\.\\-\\(\\)%]+$').test(filename)) {
        const dotPos: number = filename.lastIndexOf('.');
        if (0 < dotPos) {
          return filename.substring(0, dotPos);
        }
      }
    }
    return undefined;
  }

  static getExtensionFromMimeType(mimeType: string): string | undefined {
    if (mimeType === null || mimeType === undefined || mimeType.length === 0) {
      return undefined;
    }

    for (let i = 0, n = Utilities.MIME_TYPE_ARRAY.length; i < n; i++) {
      if (Utilities.MIME_TYPE_ARRAY[i] === mimeType) {
        return Utilities.EXTENSION_ARRAY[i];
      }
    }

    return Utilities.MIME_TO_EXT.get(mimeType);
  }

}