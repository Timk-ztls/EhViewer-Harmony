/*
 * Copyright 2024 Hippo Seven
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

import { GLCommand } from './GLNativeBridge';

/** 解码后的一条命令（单测与 native 侧调试输出共用）。 */
export class GLCommandRecord {
  op: number;
  args: number[];

  constructor(op: number, args: number[]) {
    this.op = op;
    this.args = args;
  }

  toString(): string {
    return `GLCommand(${GLCommand[this.op] ?? this.op}, [${this.args.join(', ')}])`;
  }
}

/**
 * GL 命令流编码器。
 *
 * 布局：`Float32Array`，每条记录 `[opcode, argc, arg0, ..., arg(argc-1)]`。
 * 顺序即语义（GL 是状态机），native 侧 `nativeReplay()` 单趟顺序执行。
 *
 * 为什么整数也用 float 承载：单缓冲、无对齐问题、无两套游标。
 * 精度上限 2^24 ≈ 1677 万，远大于任何 GL 句柄（纹理 id 通常 < 10^4）。
 * **约束**：调用方不得把 > 2^24 的整数值放进参数（`cmd()` 会做防御性检查并抛错）。
 *
 * 容量策略：初始 4096 float，按 2 倍增长；`reset()` 只重置游标，不释放内存
 * （每帧复用同一块，避免 GC 抖动）。
 */
/**
 * ## 金样本（native 侧解析器的手工验算基准）
 *
 * 下面这一帧是单测实际产出的字节序列，`setSize(100,200) + clearBuffer() +
 * fillRect(10,20,30,40,0xFF00FF00)`，共 13 条记录 / 69 个 float。
 * native 侧实现完 `nativeReplay` 后，用同样输入打印解析结果，逐条对上即通过：
 * ```
 * { 1, 2, 100, 200 }                                   // SET_VIEWPORT(100,200)
 * { 2, 4, 0, 0, 0, 1 }                                 // CLEAR(0,0,0,1)
 * { 3, 1, 0 }                                          // USE_PROGRAM(draw)
 * { 4, 1, 0 }                                          // BLEND_ENABLE(0) 绿色不透明
 * { 7, 5, 0, 0, 1, 0, 1 }                              // UNIFORM_COLOR(draw, 0,1,0,1) 预乘
 * { 10, 1, 5 }                                         // BIND_ARRAY_BUFFER(boxVbo=5)
 * { 11, 4, 0, 0, 2, 0 }                                // VERTEX_ATTRIB_POINTER(draw, slot0, 2, off0)
 * { 10, 1, 0 }                                         // BIND_ARRAY_BUFFER(0)
 * { 8, 17, 0, 0.6,0,0,0, 0,-0.4,0,0, 0,0,-1,0, -0.8,0.8,0,1 }  // UNIFORM_MATRIX(draw, 4x4)
 * { 15, 2, 0, 0 }                                      // ENABLE_ATTRIB(draw, slot0)
 * { 17, 3, 5, 0, 4 }                                   // DRAW_ARRAYS(TRIANGLE_STRIP, 0, 4)
 * { 16, 2, 0, 0 }                                      // DISABLE_ATTRIB(draw, slot0)
 * { 22, 0 }                                            // END_FRAME
 * ```
 * 矩阵那一行的 16 个值 = `ortho(0..100, 0..200) * translate(10,20) * scale(30,40)`，
 * y 分量取负是因为屏幕路径在 `setSize` 里做了 `translate(0,h)+scale(1,-1,1)` 翻转。
 */
export class GLCommandBuffer {
  private buf: Float32Array = new Float32Array(4096);
  private used: number = 0;

  /** 每帧开头调用。 */
  reset(): void {
    this.used = 0;
  }

  /** 当前已写入的 float 个数。 */
  size(): number {
    return this.used;
  }

  private ensure(extra: number): void {
    if (this.used + extra <= this.buf.length) {
      return;
    }
    let cap = this.buf.length;
    while (cap < this.used + extra) {
      cap *= 2;
    }
    const next = new Float32Array(cap);
    next.set(this.buf.subarray(0, this.used));
    this.buf = next;
  }

  /** 写入一条命令。 */
  cmd(op: GLCommand, args: number[]): void {
    for (let i = 0; i < args.length; i++) {
      const v = args[i];
      if (v > 16777216 || v < -16777216) {
        throw new Error(`GLCommandBuffer: arg ${i} of op ${op} exceeds float24 precision: ${v}`);
      }
    }
    this.ensure(2 + args.length);
    this.buf[this.used++] = op;
    this.buf[this.used++] = args.length;
    for (let i = 0; i < args.length; i++) {
      this.buf[this.used++] = args[i];
    }
  }

  /** 无参命令的简写。 */
  cmd0(op: GLCommand): void {
    this.cmd(op, []);
  }

  /** 取本帧的有效区间（零拷贝视图，仅在 reset 前有效）。 */
  view(): Float32Array {
    return this.buf.subarray(0, this.used);
  }

  /** 取精确长度副本（跨线程/跨 NAPI 传参用，避免持有整块容量）。 */
  toFloat32(): Float32Array {
    const out = new Float32Array(this.used);
    out.set(this.buf.subarray(0, this.used));
    return out;
  }

  /**
   * 解码命令流。用于单测断言"命令字序列 == 上游 GL 调用序列"，
   * 也用于 native 侧排查问题时打印。
   */
  static decode(data: Float32Array): GLCommandRecord[] {
    const out: GLCommandRecord[] = [];
    let i = 0;
    while (i < data.length) {
      const op = data[i];
      const argc = data[i + 1];
      if (!Number.isInteger(op) || !Number.isInteger(argc) || argc < 0) {
        throw new Error(`GLCommandBuffer.decode: malformed record at ${i}: op=${op} argc=${argc}`);
      }
      const args: number[] = [];
      for (let k = 0; k < argc; k++) {
        args.push(data[i + 2 + k]);
      }
      out.push(new GLCommandRecord(op, args));
      i += 2 + argc;
    }
    return out;
  }
}
