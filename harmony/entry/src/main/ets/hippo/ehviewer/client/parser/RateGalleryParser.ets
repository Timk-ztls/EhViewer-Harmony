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

import { ParseException } from '../exception/ParseException';
import { JsonObject } from './Json';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/parser/RateGalleryParser.java
 * （inventory S0109，44 行）
 *
 * `{"rating_avg":4.5,"rating_cnt":123}` → Result
 *
 * 容错：任何 JSON 异常 → `ParseException("Can't parse rate gallery", body)`，
 * 并把原始异常挂在 cause 上（上游 `exception.initCause(e)`）。
 */
export class RateGalleryParser {
  static parse(body: string): RateGalleryResult {
    try {
      const jsonObject: JsonObject = JsonObject.parse(body);
      const result: RateGalleryResult = new RateGalleryResult();
      result.rating = jsonObject.getDouble('rating_avg');
      result.ratingCount = jsonObject.getInt('rating_cnt');
      result.ratingCls = jsonObject.optString('rating_cls', '');
      return result;
    } catch (e) {
      throw new ParseException("Can't parse rate gallery", body, e as Error);
    }
  }
}

/** 对齐 RateGalleryParser.Result。 */
export class RateGalleryResult {
  rating: number = 0;
  ratingCount: number = 0;
  ratingCls: string = '';

  isRatedHighlight(): boolean {
    return this.ratingCls === 'irg' || this.ratingCls === 'irb' || this.ratingCls === 'irr';
  }
}
