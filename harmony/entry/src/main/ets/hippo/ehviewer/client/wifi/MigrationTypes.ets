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
 * 迁移载荷的数据结构（对应 upstream `WiFiDownloadMigrationHelper` 的四个静态内嵌类）。
 * 与 `WiFiDownloadMigrationHelper.ets` 分开文件是为了避免 codec 反向依赖 helper 的 IO 逻辑。
 */
export class FileMeta {
  name: string = '';
  md5: string = '';
  size: number = 0;
}

export class DirManifest {
  gid: number = 0;
  dirname: string = '';
  files: FileMeta[] = [];
  pageIndex: number = 0;
  pageSize: number = 0;
}

export class DirAck {
  gid: number = 0;
  dirname: string = '';
  filesNeeded: string[] = [];
}

export class FileChunk {
  gid: number = 0;
  name: string = '';
  fileMd5: string = '';
  chunkIndex: number = 0;
  chunkTotal: number = 0;
  data: ArrayBuffer | null = null;
  lastChunk: boolean = false;
}

/** 画廊目录扫描条目（`scanGalleryDirs` 的返回元素）。 */
export class GalleryDirEntry {
  gid: number = 0;
  dirname: string = '';
}
