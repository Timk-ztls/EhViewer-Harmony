/*
 * Copyright 2014 Qihoo Inc.
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

import { Rect } from '../util/Rect';

/**
 * `com.hippo.lib.glview.glrenderer.NinePatchChunk` 的 ArkTS 等价实现（inventory S0353）。
 *
 * 解析 Android **已编译**的 nine-patch 块（`*.9.png` 编译进 apk 后的 chunk 数据）。
 * 格式见 `frameworks/base/include/utils/ResourceTypes.h`（上游注释指向处）。
 *
 * 字节布局（**大端/小端由平台 native order 决定**；Android 上是小端）：
 * ```
 * u8   wasSerialized       0 => 无 chunk（返回 null）
 * u8   divXCount           必须偶数且非 0
 * u8   divYCount           必须偶数且非 0
 * u8   colorCount
 * i32  (skip)              ← 两个 int
 * i32  padLeft / padRight / padTop / padBottom
 * i32  (skip)              ← 一个 int
 * i32[divXCount]
 * i32[divYCount]
 * i32[colorCount]
 * ```
 *
 * 三处容易写错、必须照搬：
 *   1. 三个 count 都是 **u8**，而随后的数组是 **i32**
 *   2. `checkDivCount` 只对 divX/divY 校验（**colorCount 不校验**）
 *   3. 校验不过抛 `RuntimeException("invalid nine-patch: N")` —— ArkTS 无 RuntimeException，
 *      用 Error 且**保留同样的消息文本**
 */
export class NinePatchChunk {
  static readonly NO_COLOR: number = 0x00000001;
  static readonly TRANSPARENT_COLOR: number = 0x00000000;

  mPaddings: Rect = new Rect();
  mDivX: number[] = [];
  mDivY: number[] = [];
  mColor: number[] = [];

  /**
   * 对齐 `deserialize(byte[] data)`。
   * `littleEndian` 默认 true（与 Android 平台原生序一致）；测试可显式指定。
   */
  static deserialize(data: ArrayBuffer, littleEndian: boolean = true): NinePatchChunk | null {
    const view = new DataView(data);
    let offset: number = 0;

    const wasSerialized: number = view.getUint8(offset);
    offset += 1;
    if (wasSerialized === 0) {
      return null;
    }

    const chunk: NinePatchChunk = new NinePatchChunk();
    const divXCount: number = view.getUint8(offset); offset += 1;
    const divYCount: number = view.getUint8(offset); offset += 1;
    const colorCount: number = view.getUint8(offset); offset += 1;

    chunk.mDivX = new Array<number>(divXCount);
    chunk.mDivY = new Array<number>(divYCount);
    chunk.mColor = new Array<number>(colorCount);

    NinePatchChunk.checkDivCount(chunk.mDivX.length);
    NinePatchChunk.checkDivCount(chunk.mDivY.length);

    // skip 8 bytes（两个 int）
    offset += 8;

    chunk.mPaddings.left = view.getInt32(offset, littleEndian); offset += 4;
    chunk.mPaddings.right = view.getInt32(offset, littleEndian); offset += 4;
    chunk.mPaddings.top = view.getInt32(offset, littleEndian); offset += 4;
    chunk.mPaddings.bottom = view.getInt32(offset, littleEndian); offset += 4;

    // skip 4 bytes（一个 int）
    offset += 4;

    offset = NinePatchChunk.readIntArray(chunk.mDivX, view, offset, littleEndian);
    offset = NinePatchChunk.readIntArray(chunk.mDivY, view, offset, littleEndian);
    NinePatchChunk.readIntArray(chunk.mColor, view, offset, littleEndian);

    return chunk;
  }

  private static readIntArray(data: number[], view: DataView, offset: number,
    littleEndian: boolean): number {
    let o: number = offset;
    for (let i = 0; i < data.length; i++) {
      data[i] = view.getInt32(o, littleEndian);
      o += 4;
    }
    return o;
  }

  /** 对齐 `checkDivCount`：0 或奇数都非法（**色块数组不校验**）。 */
  private static checkDivCount(length: number): void {
    if (length === 0 || (length & 0x01) !== 0) {
      throw new Error('invalid nine-patch: ' + length);
    }
  }
}
