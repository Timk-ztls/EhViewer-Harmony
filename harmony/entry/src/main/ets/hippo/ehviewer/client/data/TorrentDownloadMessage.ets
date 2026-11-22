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
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/data/TorrentDownloadMessage.kt
 * （inventory S0063）
 *
 * 种子下载的进度消息（Parcelable → 本层无 Parcel，纯字段）。
 * 字段：failed/name/path/dir/progress，全部保持 upstream 命名。
 */
export class TorrentDownloadMessage {
  failed: boolean = false;
  name: string = '';
  path: string = '';
  dir: string = '';
  progress: number = 0;
}