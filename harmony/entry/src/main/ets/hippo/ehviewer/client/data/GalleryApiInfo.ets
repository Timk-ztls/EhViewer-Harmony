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
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/data/GalleryApiInfo.java
 * （inventory S0046）
 *
 * API 返回的画廊元数据（`gmetadata` 的一项）。字段名与上游完全一致（含 `torrentcount` 全小写、
 * `filecount`/`filesize` 无下划线），因为它是 API 契约的一部分。
 */
export class GalleryApiInfo {
  gid: number = 0;
  token: string = '';
  archiverKey: string = '';
  title: string = '';
  titleJpn: string = '';
  category: number = 0;
  thumb: string = '';
  uploader: string = '';
  posted: number = 0;
  filecount: number = 0;
  filesize: number = 0;
  expunged: boolean = false;
  rating: number = 0;
  torrentcount: number = 0;
  tags: string[] | null = null;
}