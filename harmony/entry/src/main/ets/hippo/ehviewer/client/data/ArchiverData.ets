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

/**
 * 1:1 对位 upstream: .../client/data/ArchiverData.java（inventory S0042，11 行）
 *
 * Archiver 原图下载页的金额/体积/地址。上游全部是 String（页面上的文本原样保留，
 * 含 "GP" 单位），不做数值转换。
 */
export class ArchiverData {
  funds: string = '';
  originalCost: string = '';
  originalSize: string = '';
  originalUrl: string = '';
  resampleCost: string = '';
  resampleSize: string = '';
  resampleUrl: string = '';

  constructor() {
  }
}
