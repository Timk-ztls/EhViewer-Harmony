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

/**
 * 等价层：com.hippo.streampipe.OutputStreamPipe（同 InputStreamPipe 的来源说明）。
 *
 * 上游契约：
 *   void obtain();
 *   void release();
 *   OutputStream open();
 *   void close();     // 注意：SimpleDiskCache 的实现在 close() 里 commit editor
 *
 * ArkTS 映射：java.io.OutputStream → ByteSink（本文件定义的最小写端抽象），
 * 因为 ArkTS 没有 OutputStream 基类，而 BeerBelly.write() 需要一个能 write(byte[]) 的形参。
 */
export interface OutputStreamPipe {
  obtain(): void;

  release(): void;

  open(): ByteSink;

  close(): void;
}

/**
 * 最小写端：对应 java.io.OutputStream 的 write(byte[], int, int) / flush() / close()。
 * 由 beerbelly 的 FaultHidingWriter 与 SimpleDiskCache 的 CacheOutputStreamPipe 实现。
 */
export interface ByteSink {
  write(data: ArrayBuffer): void;

  close(): void;
}
