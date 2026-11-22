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

import { EhException } from '../exception/EhException';
import { JsonObject } from './Json';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/parser/GalleryTokenApiParser.java
 * （inventory S0104，44 行）
 *
 * {
 *  "tokenlist": [{ "gid": 618395, "token": "0439fa3666" }]
 * }
 * → token
 *
 * 异常路径照搬：`tokenlist[0]` 里没有 `token` 时抛 `EhException(该对象的 "error" 字段)`。
 * 注意外层 `getJSONArray/getJSONObject` 抛的是 JSONException（→ 本层普通 Error），
 * 只有内层 try 覆盖 token 读取——上游就是这么分的，别扩大 try 范围。
 */
export class GalleryTokenApiParser {
  static parse(body: string): string {
    const jo: JsonObject = JsonObject.parse(body).getJSONArray('tokenlist').getJSONObject(0);
    try {
      return jo.getString('token');
    } catch (e) {
      throw new EhException(jo.getString('error'));
    }
  }
}
