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

import { Document, Element, Elements, Jsoup } from '../../../jsoup/index';
import { HomeDetail } from '../data/HomeDetail';
import { EhException } from '../exception/EhException';
import { ParserUtils } from './ParserUtils';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/parser/EhHomeParser.java
 * （inventory S0093，109 行）
 *
 * 首页面板：`.homebox` 的第 0/2/4 个分别是「图片配额」「GP 收益」「管理权限」。
 *
 * 三个旧/新正则（配额文案改过版），新旧都试，都失败就**静默跳过**（return，不抛）。
 * 整段解析外层 `catch (Exception)` 只记日志，仍然返回已填好的部分 —— 这是上游的容错策略：
 * **首页面板数据可以缺，页面不能崩**。
 */
export class EhHomeParser {
  private static readonly PATTERN_IMAGE_LIMIT: RegExp =
    /<p>You are currently at\s*<strong>([\d,]+)<\/strong>\s*towards a limit of\s*<strong>([\d,]+)<\/strong>\.?<\/p>[\s\S]*?<p>Reset Cost:\s*<strong>([\d,]+)<\/strong>\s*GP<\/p>/i;
  // 鸿蒙自研 jsoup Element.html() 子节点直接拼接无 `\n`，且真实页面数字常带千分位逗号。
  private static readonly PATTERN_IMAGE_LIMIT_NEW: RegExp =
    /<p>You are currently at\s*<strong>([^<]+)<\/strong>\s*towards your account limit of\s*<strong>([^<]+)<\/strong>\.?<\/p>\s*<p>You can reset your image quota by spending\s*<strong>([^<]+)<\/strong>\s*GP\.?<\/p>/i;
  private static readonly PATTERN_IMAGE_LIMIT_FALLBACK: RegExp =
    /You are currently at\s*<strong>([\d,]+)<\/strong>\s*towards (?:your account |a )?limit of\s*<strong>([\d,]+)<\/strong>/i;
  private static readonly PATTERN_RESET_COST_FALLBACK: RegExp =
    /(?:spending|Reset Cost:)\s*<strong>([\d,]+)<\/strong>\s*GP/i;
  private static readonly HOME_BOX: string = 'homebox';

  static parse(body: string): HomeDetail {
    const homeDetail: HomeDetail = new HomeDetail();
    try {
      const document: Document = Jsoup.parse(body);
      const homeBoxes: Elements = document.getElementsByClass(EhHomeParser.HOME_BOX);
      if (homeBoxes.size() === 0) {
        return homeDetail;
      }
      EhHomeParser.parseImageLimits(homeBoxes.get(0), homeDetail);
      if (homeBoxes.size() > 2) {
        EhHomeParser.parseTotalGpGained(homeBoxes.get(2), homeDetail);
      }
      if (homeBoxes.size() > 4) {
        EhHomeParser.parseModerationPower(homeBoxes.get(4), homeDetail);
      }
    } catch (e) {
      // 上游 Log.e("数据结构错误") + Analytics.recordException —— 首页面板可缺
    }
    return homeDetail;
  }

  private static parseModerationPower(moderationPower: Element, homeDetail: HomeDetail): void {
    const all: Elements = moderationPower.getAllElements();
    if (all.size() === 0) {
      return;
    }
    const tableRow: Element | null = all.get(0).child(0);
    if (tableRow === null) {
      return;
    }
    const rows: Elements = tableRow.children();
    const r0: Element | null = rows.get(0).child(0);
    const r1: Element | null = r0 === null ? null : r0.child(0);
    const r2: Element | null = r1 === null ? null : r1.child(1);
    if (r2 === null) {
      return;
    }
    const power: number = ParserUtils.parseLong(r2.text().replace(/,/g, ''), -1);
    homeDetail.setCurrentModerationPower(power);
  }

  private static parseTotalGpGained(totalGpGained: Element, homeDetail: HomeDetail): void {
    const all: Elements = totalGpGained.getAllElements();
    if (all.size() === 0) {
      return;
    }
    const table: Element = all.get(0);
    const c0: Element | null = table.child(0);
    const rows: Element | null = c0 === null ? null : c0.child(0);
    if (rows === null) {
      return;
    }
    homeDetail.setFromGalleryVisits(EhHomeParser.rowValue(rows, 0));
    homeDetail.setFromTorrentCompletions(EhHomeParser.rowValue(rows, 1));
    homeDetail.setFromArchiveDownloads(EhHomeParser.rowValue(rows, 2));
    homeDetail.setFromHentaiAtHome(EhHomeParser.rowValue(rows, 3));
  }

  private static rowValue(rows: Element, index: number): number {
    const row: Element | null = rows.child(index);
    const cell: Element | null = row === null ? null : row.child(0);
    if (cell === null) {
      return -1;
    }
    return ParserUtils.parseLong(cell.text().replace(/,/g, ''), -1);
  }

  private static parseImageLimits(imageLimits: Element, homeDetail: HomeDetail): void {
    const imageListsString: string = imageLimits.html();
    let matcher: RegExpMatchArray | null = imageListsString.match(EhHomeParser.PATTERN_IMAGE_LIMIT_NEW);
    if (matcher === null) {
      matcher = imageListsString.match(EhHomeParser.PATTERN_IMAGE_LIMIT);
    }
    if (matcher !== null) {
      homeDetail.setUsed(ParserUtils.parseLong(EhHomeParser.groupIntString(1, matcher), -1));
      homeDetail.setTotal(ParserUtils.parseLong(EhHomeParser.groupIntString(2, matcher), -1));
      homeDetail.setResetCost(ParserUtils.parseLong(EhHomeParser.groupIntString(3, matcher), -1));
      return;
    }
    const baseMatch: RegExpMatchArray | null = imageListsString.match(EhHomeParser.PATTERN_IMAGE_LIMIT_FALLBACK);
    if (baseMatch === null) {
      return;
    }
    homeDetail.setUsed(ParserUtils.parseLong(EhHomeParser.groupIntString(1, baseMatch), -1));
    homeDetail.setTotal(ParserUtils.parseLong(EhHomeParser.groupIntString(2, baseMatch), -1));
    const resetMatch: RegExpMatchArray | null = imageListsString.match(EhHomeParser.PATTERN_RESET_COST_FALLBACK);
    homeDetail.setResetCost(resetMatch === null ? 0 : ParserUtils.parseLong(EhHomeParser.groupIntString(1, resetMatch), 0));
  }

  private static groupIntString(index: number, matcher: RegExpMatchArray): string {
    const groupS: string | undefined = matcher[index];
    if (groupS !== null && groupS !== undefined) {
      return groupS.replace(/,/g, '');
    }
    return '0';
  }
}
