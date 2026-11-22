/*
 * Copyright 2017 Hippo Seven
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

import fileIo from '@ohos.file.fs';

/**
 * 等价层：com.hippo.streampipe.InputStreamPipe（上游 Maven 依赖 `com.hippo:streampipe`，
 * 不在 app 源码树内，因此没有 inventory 编号；登记请求见 MR 描述与
 * `inventory/net-parse.extra.txt`）。
 *
 * 上游契约（BeerBelly / SimpleDiskCache / ImageBitmapHelper 都依赖）：
 *   void obtain();          // 占位（加锁/引用计数）
 *   void release();         // 释放占位
 *   InputStream open();     // 取流（每次 obtain 后只能开一次，close 后才能再开）
 *   void close();           // 关闭流（不释放占位）
 *
 * ArkTS 映射：java.io.InputStream → fileIo.File（同步句柄，配合 fileIo.readSync）。
 */
export interface InputStreamPipe {
  obtain(): void;

  release(): void;

  open(): fileIo.File;

  close(): void;
}
