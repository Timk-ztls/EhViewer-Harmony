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

import { GalleryInfo } from '../data/GalleryInfo';
import { EhUtils } from '../EhUtils';
import { JsonArray, JsonObject } from './Json';
import { ParserUtils } from './ParserUtils';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/parser/GalleryApiParser.java
 * （inventory S0096，71 行）
 *
 * 列表页的 `gmetadata` API 回填：按 gid 在**已有列表**里找到对应项，逐字段覆盖
 * （title / titleJpn / category / thumb / uploader / posted / rating / simpleTags / pages），
 * 最后 `generateSLang()`。
 *
 * 关键行为：**只回填已存在的项**（`getGalleryInfoByGid` 找不到就 continue），不新建对象；
 * posted 是「秒级时间戳 × 1000 → `yyyy-MM-dd HH:mm`」，且**不负责**刷新 `postedAt`
 * （那是 C-7 派生字段，回填后由调用方或本层补一次 refreshPostedAt —— 见下）。
 */
export class GalleryApiParser {
  /**
   * 对齐 `parse(String body, List<GalleryInfo> galleryInfoList)`。
   * 注意上游直接改写传入的 list（Java 引用语义）；本层同样原地改写数组元素。
   */
  static parse(body: string, galleryInfoList: GalleryInfo[]): void {
    const jo: JsonObject = JsonObject.parse(body);
    const ja: JsonArray = jo.getJSONArray('gmetadata');
    for (let i = 0; i < ja.length(); i++) {
      const g: JsonObject = ja.getJSONObject(i);
      const gid: number = g.getLong('gid');
      const gi: GalleryInfo | null = GalleryApiParser.getGalleryInfoByGid(galleryInfoList, gid);
      if (gi === null) {
        continue;
      }
      gi.title = ParserUtils.trim(g.getString('title'));
      gi.titleJpn = ParserUtils.trim(g.getString('title_jpn'));
      gi.category = EhUtils.getCategoryByType(g.getString('category'));
      gi.thumb = EhUtils.handleThumbUrlResolution(g.getString('thumb')) as string;
      gi.uploader = g.getString('uploader');
      gi.posted = ParserUtils.formatDate(ParserUtils.parseLong(g.getString('posted'), 0) * 1000);
      gi.rating = ParserUtils.parseFloat(g.getString('rating'), 0.0);
      // tags
      const tagJa: JsonArray = g.getJSONArray('tags');
      const tags: string[] = [];
      for (let j = 0; j < tagJa.length(); j++) {
        tags.push(tagJa.getString(j));
      }
      gi.simpleTags = tags;
      gi.pages = ParserUtils.parseInt(g.getString('filecount'), 0);
      gi.generateSLang();
      // C-7 补充第 3 条：posted 被覆盖后必须刷新派生字段
      gi.refreshPostedAt();
    }
  }

  private static getGalleryInfoByGid(list: GalleryInfo[], gid: number): GalleryInfo | null {
    for (let i = 0; i < list.length; i++) {
      if (list[i].gid === gid) {
        return list[i];
      }
    }
    return null;
  }
}
