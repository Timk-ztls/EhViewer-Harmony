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
 * 1:1 对位 upstream: .../client/data/TorrentInfo.java（inventory S0064，26 行）
 *
 * 种子信息。上游三个字段全是 final（构造后不可变），本层同样用 readonly 语义。
 */
export class TorrentInfo {
  readonly url: string;
  readonly name: string;
  readonly posted: string;

  constructor(url: string, name: string, posted: string) {
    this.url = url;
    this.name = name;
    this.posted = posted;
  }
}
