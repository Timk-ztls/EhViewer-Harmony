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

/**
 * 1:1 移植上游 DownloadTorrentFileNameTest.kt（commit 243c39b3）：
 * 验证 DownloadTorrentManager.createTorrentFileName 与 TorrentDownloadController.buildTorrentFileName。
 */

import { DownloadTorrentManager } from '../../main/ets/hippo/ehviewer/download/DownloadTorrentManager';
import {
  TorrentDownloadController,
  TorrentInfoLike
} from '../../main/ets/hippo/ehviewer/ui/scene/gallery/detail/TorrentDownloadController';

let passed: number = 0;
let failed: number = 0;

function ok(name: string, cond: boolean): void {
  if (cond) {
    console.log('PASS ' + name);
    passed++;
  } else {
    console.error('FAIL ' + name);
    failed++;
  }
}

function eq<T>(name: string, actual: T, expected: T): void {
  const a: string = JSON.stringify(actual);
  const e: string = JSON.stringify(expected);
  if (a === e) {
    console.log('PASS ' + name);
    passed++;
  } else {
    console.error(`FAIL ${name}: actual=${a} expected=${e}`);
    failed++;
  }
}

function utf8ByteLength(s: string): number {
  let bytes: number = 0;
  for (let i = 0; i < s.length; i++) {
    const code: number = s.charCodeAt(i);
    if (code <= 0x7F) {
      bytes += 1;
    } else if (code <= 0x7FF) {
      bytes += 2;
    } else if (code >= 0xD800 && code <= 0xDBFF) {
      bytes += 4;
      i++;
    } else {
      bytes += 3;
    }
  }
  return bytes;
}

const FALLBACK_URL: string =
  'https://ehtracker.org/get/4307852/olx4xjefmwq52sfd5z/bb3837ff9d57f15caa3cb35a226ac2c8dca2b01a.torrent';
const TORRENT_LIST_1_TITLE: string =
  '[DDK00] 蛇之仆·樱 Vol 1-Vol 6合集上 （Vol 1-Vol 3 ）+番外:小樱的洗脑调教  [DDK00] Servant of the Serpent: Sakura – Vol 1–6 Collection (Part 1) (Vol 1 -Vol 3).zip';
const FORBIDDEN: string[] = ['\\', '/', ':', '*', '?', '"', '<', '>', '|'];

function hasForbidden(name: string): boolean {
  for (let i = 0; i < FORBIDDEN.length; i++) {
    if (name.indexOf(FORBIDDEN[i]) >= 0) {
      return true;
    }
  }
  return false;
}

// 1) 上游 torrentList1TitleDropsColonAndKeepsTorrentSuffix
{
  ok('样本标题含冒号', TORRENT_LIST_1_TITLE.indexOf(':') >= 0);
  const fileName: string = DownloadTorrentManager.createTorrentFileName(TORRENT_LIST_1_TITLE, FALLBACK_URL);
  ok('torrentList1 保留 .zip.torrent 后缀', fileName.endsWith('.zip.torrent'));
  ok('torrentList1 保留中文前缀', fileName.indexOf('番外小樱') >= 0);
  ok('torrentList1 保留英文段落', fileName.indexOf('Serpent Sakura') >= 0);
  ok('torrentList1 去除冒号', fileName.indexOf(':') < 0);
  ok('torrentList1 不含任何非法文件名字符', !hasForbidden(fileName));
  ok('torrentList1 UTF-8 字节 <= 255', utf8ByteLength(fileName) <= 255);
}

// 2) 上游 longTitleStaysWithinUtf8Limit（200 个中文字符 → 82*3 + 8 = 254 字节）
{
  const title: string = '画'.repeat(200) + ':*?"<>|';
  const fileName: string = DownloadTorrentManager.createTorrentFileName(title, FALLBACK_URL);
  ok('超长中文标题保留 .torrent 后缀', fileName.endsWith('.torrent'));
  ok('超长中文标题无非法字符', !hasForbidden(fileName));
  const byteSize: number = utf8ByteLength(fileName);
  ok('超长中文标题 UTF-8 字节 <= 255', byteSize <= 255);
  eq('超长中文标题精确截断字节数 82*3 + 8 = 254', byteSize, 82 * 3 + '.torrent'.length);
}

// 3) 4 字节 UTF-8 代理对不被劈裂（247 = 61 * 4 + 3 → 最多留 61 个 emoji = 244 字节）
{
  const emojiTitle: string = '😀'.repeat(70);
  const fileName: string = DownloadTorrentManager.createTorrentFileName(emojiTitle, FALLBACK_URL);
  ok('emoji 标题以 .torrent 结尾', fileName.endsWith('.torrent'));
  ok('emoji 标题 UTF-8 字节 <= 255', utf8ByteLength(fileName) <= 255);
  eq('emoji 标题字节数 61*4 + 8 = 252', utf8ByteLength(fileName), 61 * 4 + 8);
  const base: string = fileName.substring(0, fileName.length - '.torrent'.length);
  // 验证无孤立高/低代理码元
  let hasLoneSurrogate: boolean = false;
  for (let i = 0; i < base.length; i++) {
    const c: number = base.charCodeAt(i);
    if (c >= 0xD800 && c <= 0xDBFF) {
      if (i + 1 >= base.length || base.charCodeAt(i + 1) < 0xDC00 || base.charCodeAt(i + 1) > 0xDFFF) {
        hasLoneSurrogate = true;
      }
      i++;
    } else if (c >= 0xDC00 && c <= 0xDFFF) {
      hasLoneSurrogate = true;
    }
  }
  ok('emoji 标题截断无孤立代理码元', !hasLoneSurrogate);
}

// 4) 上游 blankTitleFallsBackToUrlFileName
{
  const expected: string = 'bb3837ff9d57f15caa3cb35a226ac2c8dca2b01a.torrent';
  eq('全冒号标题回退 URL 末段', DownloadTorrentManager.createTorrentFileName(':::', FALLBACK_URL), expected);
  eq('空白与非法字符组合回退 URL 末段',
    DownloadTorrentManager.createTorrentFileName(' \\/:*?\"<>| ', FALLBACK_URL), expected);
  eq('null 标题回退 URL 末段', DownloadTorrentManager.createTorrentFileName(null, FALLBACK_URL), expected);
  eq('undefined 标题回退 URL 末段', DownloadTorrentManager.createTorrentFileName(undefined, FALLBACK_URL), expected);
}

// 5) TorrentDownloadController.buildTorrentFileName 委托一致
{
  const info: TorrentInfoLike = {
    name: 'Test: Torrent? <1>',
    size: '10 MB',
    seeders: 3,
    peers: 1,
    url: FALLBACK_URL,
    hash: 'bb3837ff9d57f15caa3cb35a226ac2c8dca2b01a'
  };
  eq('TorrentDownloadController.buildTorrentFileName 委托 createTorrentFileName',
    TorrentDownloadController.buildTorrentFileName(info),
    'Test Torrent 1.torrent');
}

console.log(`\ntorrent-filename: ${passed} passed, ${failed} failed`);
if (failed > 0) {
  throw new Error(`torrent-filename failed: ${failed}`);
}
