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

import { TorrentInfo } from '../data/TorrentInfo';
import { ParserUtils } from './ParserUtils';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/parser/TorrentParser.java
 * （inventory S0112，58 行）
 *
 * 种子页：按 `<form>` 分块，每块取一条 `<td colspan="5">&nbsp;<a href="…">名字</a></td>`
 * 和一个 `Posted:` 时间。
 *
 * 三个正则都带 DOTALL（本层用 [\s\S] 等价），逐字符照搬。
 * **行为要点**：URL 里的 `?p=` 之后被截掉（上游注释：Remove ?p= to make torrent redistributable）——
 * 这是为了让种子链接可再分发，别"顺手"保留。
 */
export class TorrentParser {
  private static readonly PATTERN_TORRENT_BLOCK: RegExp = /<form\b[^>]*>[\s\S]*?<\/form>/g;
  private static readonly PATTERN_POSTED: RegExp =
    /<span[^>]*>\s*Posted:\s*<\/span>\s*<span>([^<]+)<\/span>/;
  private static readonly PATTERN_TORRENT: RegExp =
    /<td colspan="5">\s*&nbsp;\s*<a href="([^"]+)"[^<]*>([^<]+)<\/a><\/td>/;

  static parse(body: string): TorrentInfo[] {
    const torrentList: TorrentInfo[] = [];
    const blockRe: RegExp = new RegExp(TorrentParser.PATTERN_TORRENT_BLOCK.source, 'g');
    let blockMatcher: RegExpExecArray | null = blockRe.exec(body);
    while (blockMatcher !== null) {
      const block: string = blockMatcher[0];
      const torrentMatcher: RegExpMatchArray | null = block.match(TorrentParser.PATTERN_TORRENT);
      if (torrentMatcher === null) {
        blockMatcher = blockRe.exec(body);
        continue;
      }
      // Remove ?p= to make torrent redistributable
      let url: string = ParserUtils.trim(torrentMatcher[1]);
      const index: number = url.indexOf('?p=');
      if (index !== -1) {
        url = url.substring(0, index);
      }
      const name: string = ParserUtils.trim(torrentMatcher[2]);
      let posted: string = '';
      const postedMatcher: RegExpMatchArray | null = block.match(TorrentParser.PATTERN_POSTED);
      if (postedMatcher !== null) {
        posted = ParserUtils.trim(postedMatcher[1]);
      }
      torrentList.push(new TorrentInfo(url, name, posted));
      blockMatcher = blockRe.exec(body);
    }
    return torrentList;
  }
}
