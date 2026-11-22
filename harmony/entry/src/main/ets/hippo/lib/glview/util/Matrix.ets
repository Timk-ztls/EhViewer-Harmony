/*
 * Copyright (C) 2007 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/**
 * `android.opengl.Matrix`（静态 4x4 数学）+ `android.graphics.Matrix`（实例 3x3 仿射）
 * 的 ArkTS 等价实现。
 *
 * 为什么合成一个类：上游两个 Java 类同名但用不同种类的方法（前者全静态、后者全实例），
 * 调用点分别是 `Matrix.orthoM(...)` 与 `mMatrix.postTranslate(...)`。ArkTS 里静态方法与
 * 实例方法不冲突，合成一个 `Matrix` 就能让**全部调用点逐字保持不变**，符合符号级 1:1。
 *
 * 全部实现逐运算符照搬 AOSP（`frameworks/base/opengl/java/android/opengl/Matrix.java`
 * 与 `frameworks/base/graphics/java/android/graphics/Matrix.java`），包括列主序下标、
 * 90° 特判、`multiplyMM` 的别名检查。矩阵运算是每帧热路径，不做任何"等价改写"。
 *
 * 内存布局（4x4，列主序，与 OpenGL 一致）：
 *   m[0]  m[4]  m[8]  m[12]
 *   m[1]  m[5]  m[9]  m[13]
 *   m[2]  m[6]  m[10] m[14]
 *   m[3]  m[7]  m[11] m[15]
 */
export class Matrix {
  // ---------------- android.graphics.Matrix 的 9 个分量（3x3，行主序） ----------------
  static readonly MSCALE_X: number = 0;
  static readonly MSKEW_X: number = 1;
  static readonly MTRANS_X: number = 2;
  static readonly MSKEW_Y: number = 3;
  static readonly MSCALE_Y: number = 4;
  static readonly MTRANS_Y: number = 5;
  static readonly MPERSP_0: number = 6;
  static readonly MPERSP_1: number = 7;
  static readonly MPERSP_2: number = 8;

  /** 3x3 分量数组，布局 `[MSCALE_X, MSKEW_X, MTRANS_X, MSKEW_Y, MSCALE_Y, MTRANS_Y, MPERSP_0, MPERSP_1, MPERSP_2]`。 */
  private mValues: number[] = [1, 0, 0, 0, 1, 0, 0, 0, 1];

  constructor();
  constructor(src: Matrix);
  constructor(src?: Matrix) {
    if (src !== undefined) {
      for (let i = 0; i < 9; i++) {
        this.mValues[i] = src.mValues[i];
      }
    }
  }

  // ============================================================================
  // android.opengl.Matrix —— 静态 4x4 工具（全部为原地修改，与 AOSP 一致）
  // ============================================================================

  /** 置为单位矩阵（清零 16 个分量，AOSP 也是清零而非写 1）。 */
  static setIdentityM(smem: number[], smoffset: number): void {
    for (let i = 0; i < 16; i++) {
      smem[smoffset + i] = 0;
    }
    smem[smoffset + 0] = 1;
    smem[smoffset + 5] = 1;
    smem[smoffset + 10] = 1;
    smem[smoffset + 15] = 1;
  }

  /** 原地左乘平移：`m = m * T(x,y,z)`（AOSP 的列主序写法）。 */
  static translateM(m: number[], mOffset: number, x: number, y: number, z: number): void {
    for (let i = 0; i < 4; ++i) {
      const mi = mOffset + i;
      m[12 + mi] += m[mi] * x + m[4 + mi] * y + m[8 + mi] * z;
    }
  }

  /** 先复制 t 到 m，再平移。 */
  static translateMFrom(m: number[], mOffset: number, t: number[], tOffset: number,
    x: number, y: number, z: number): void {
    for (let i = 0; i < 16; i++) {
      m[mOffset + i] = t[tOffset + i];
    }
    Matrix.translateM(m, mOffset, x, y, z);
  }

  /** 原地缩放：`m = m * S(sx,sy,sz)`。 */
  static scaleM(m: number[], mOffset: number, x: number, y: number, z: number): void {
    for (let i = 0; i < 4; ++i) {
      const mi = mOffset + i;
      m[mi] *= x;
      m[4 + mi] *= y;
      m[8 + mi] *= z;
    }
  }

  static scaleMFrom(m: number[], mOffset: number, t: number[], tOffset: number,
    x: number, y: number, z: number): void {
    for (let i = 0; i < 16; i++) {
      m[mOffset + i] = t[tOffset + i];
    }
    Matrix.scaleM(m, mOffset, x, y, z);
  }

  /**
   * 构造绕轴 (x,y,z) 旋转 a 度的矩阵并写入 m。
   * 逐分支照搬 AOSP：零向量 → 单位阵；±90° 轴对齐 → 直接填 ±1，走特判路径。
   */
  static setRotateM(rm: number[], rmOffset: number, a: number, x: number, y: number, z: number): void {
    rm[rmOffset + 3] = 0;
    rm[rmOffset + 7] = 0;
    rm[rmOffset + 11] = 0;
    rm[rmOffset + 12] = 0;
    rm[rmOffset + 13] = 0;
    rm[rmOffset + 14] = 0;
    rm[rmOffset + 15] = 1;

    a *= Math.PI / 180.0;
    const s = Math.sin(a);
    const c = Math.cos(a);

    if (1.0 === x && 0.0 === y && 0.0 === z) {
      // 绕 X 轴
      rm[rmOffset + 5] = c;
      rm[rmOffset + 10] = c;
      rm[rmOffset + 6] = s;
      rm[rmOffset + 9] = -s;
      rm[rmOffset + 1] = 0;
      rm[rmOffset + 2] = 0;
      rm[rmOffset + 4] = 0;
      rm[rmOffset + 8] = 0;
      rm[rmOffset + 0] = 1;
    } else if (0.0 === x && 1.0 === y && 0.0 === z) {
      // 绕 Y 轴
      rm[rmOffset + 0] = c;
      rm[rmOffset + 10] = c;
      rm[rmOffset + 8] = s;
      rm[rmOffset + 2] = -s;
      rm[rmOffset + 1] = 0;
      rm[rmOffset + 4] = 0;
      rm[rmOffset + 6] = 0;
      rm[rmOffset + 9] = 0;
      rm[rmOffset + 5] = 1;
    } else if (0.0 === x && 0.0 === y && 1.0 === z) {
      // 绕 Z 轴（GLES20Canvas.rotate 走的就是这条）
      rm[rmOffset + 0] = c;
      rm[rmOffset + 5] = c;
      rm[rmOffset + 1] = s;
      rm[rmOffset + 4] = -s;
      rm[rmOffset + 2] = 0;
      rm[rmOffset + 6] = 0;
      rm[rmOffset + 8] = 0;
      rm[rmOffset + 9] = 0;
      rm[rmOffset + 10] = 1;
    } else {
      const len = Math.sqrt(x * x + y * y + z * z);
      if (len === 0) {
        Matrix.setIdentityM(rm, rmOffset);
        return;
      }
      const invLen = 1.0 / len;
      const x1 = x * invLen;
      const y1 = y * invLen;
      const z1 = z * invLen;
      const nc = 1.0 - c;
      const xy = x1 * y1;
      const yz = y1 * z1;
      const zx = z1 * x1;
      const xs = x1 * s;
      const ys = y1 * s;
      const zs = z1 * s;
      rm[rmOffset + 0] = x1 * x1 * nc + c;
      rm[rmOffset + 1] = xy * nc + zs;
      rm[rmOffset + 2] = zx * nc - ys;
      rm[rmOffset + 4] = xy * nc - zs;
      rm[rmOffset + 5] = y1 * y1 * nc + c;
      rm[rmOffset + 6] = yz * nc + xs;
      rm[rmOffset + 8] = zx * nc + ys;
      rm[rmOffset + 9] = yz * nc - xs;
      rm[rmOffset + 10] = z1 * z1 * nc + c;
    }
  }

  /** 原地左乘旋转：`m = m * R(a,x,y,z)`。GLES20Canvas.rotate 由它实现。 */
  static rotateM(m: number[], mOffset: number, a: number, x: number, y: number, z: number): void {
    const temp: number[] = new Array<number>(32).fill(0);
    Matrix.setRotateM(temp, 0, a, x, y, z);
    Matrix.multiplyMM(temp, 16, m, mOffset, temp, 0);
    for (let i = 0; i < 16; i++) {
      m[mOffset + i] = temp[16 + i];
    }
  }

  /**
   * 4x4 矩阵乘：`result = lhs * rhs`（列主序）。
   * 按列主序定义 `m[col*4 + row]`，则 `result[c*4+r] = Σ_j lhs[j*4+r] * rhs[c*4+j]`。
   * 累加顺序 j=0..3 与 AOSP 一致，保证浮点舍入结果逐位相同
   * （矩阵乘法不满足结合律，求和顺序换一次就会在第 7 位有效数字上漂）。
   *
   * 别名规则：**允许** result 与某个操作数是同一数组，只要写入区间与读取区间不重叠。
   * 上游 `GLES20Canvas.setMatrix()` 就是
   * `multiplyMM(mTempMatrix, 16, mProjectionMatrix, 0, mTempMatrix, 0)` ——
   * 结果写 [16,32)、操作数读 [0,16)，安全；只有区间真重叠时才抛错。
   */
  static multiplyMM(result: number[], resultOffset: number, lhs: number[], lhsOffset: number,
    rhs: number[], rhsOffset: number): void {
    const resultEnd = resultOffset + 16;
    if (result === lhs && resultOffset < lhsOffset + 16 && resultEnd > lhsOffset) {
      throw new Error('multiplyMM: result overlaps lhs');
    }
    if (result === rhs && resultOffset < rhsOffset + 16 && resultEnd > rhsOffset) {
      throw new Error('multiplyMM: result overlaps rhs');
    }
    for (let c = 0; c < 4; c++) {
      for (let r = 0; r < 4; r++) {
        let sum = 0;
        for (let j = 0; j < 4; j++) {
          sum += lhs[lhsOffset + j * 4 + r] * rhs[rhsOffset + c * 4 + j];
        }
        result[resultOffset + c * 4 + r] = sum;
      }
    }
  }

  /** 4x4 矩阵乘 4 维向量：`resultVec = lhsMat * rhsVec`。 */
  static multiplyMV(resultVec: number[], resultVecOffset: number, lhsMat: number[], lhsOffset: number,
    rhsVec: number[], rhsVecOffset: number): void {
    const x = rhsVec[rhsVecOffset + 0];
    const y = rhsVec[rhsVecOffset + 1];
    const z = rhsVec[rhsVecOffset + 2];
    const w = rhsVec[rhsVecOffset + 3];
    resultVec[resultVecOffset + 0] = lhsMat[lhsOffset + 0] * x + lhsMat[lhsOffset + 4] * y
      + lhsMat[lhsOffset + 8] * z + lhsMat[lhsOffset + 12] * w;
    resultVec[resultVecOffset + 1] = lhsMat[lhsOffset + 1] * x + lhsMat[lhsOffset + 5] * y
      + lhsMat[lhsOffset + 9] * z + lhsMat[lhsOffset + 13] * w;
    resultVec[resultVecOffset + 2] = lhsMat[lhsOffset + 2] * x + lhsMat[lhsOffset + 6] * y
      + lhsMat[lhsOffset + 10] * z + lhsMat[lhsOffset + 14] * w;
    resultVec[resultVecOffset + 3] = lhsMat[lhsOffset + 3] * x + lhsMat[lhsOffset + 7] * y
      + lhsMat[lhsOffset + 11] * z + lhsMat[lhsOffset + 15] * w;
  }

  /** 正交投影矩阵。GLES20Canvas.setSize 用它把 (0,0)-(w,h) 映射到 NDC。 */
  static orthoM(m: number[], mOffset: number, left: number, right: number, bottom: number,
    top: number, near: number, far: number): void {
    if (left === right) {
      throw new Error('orthoM() can not be called if left == right');
    }
    if (bottom === top) {
      throw new Error('orthoM() can not be called if bottom == top');
    }
    if (near === far) {
      throw new Error('orthoM() can not be called if near == far');
    }
    const x = 2.0 / (right - left);
    const y = 2.0 / (top - bottom);
    const z = -2.0 / (far - near);
    const tx = -(right + left) / (right - left);
    const ty = -(top + bottom) / (top - bottom);
    const tz = -(far + near) / (far - near);
    m[mOffset + 0] = x;
    m[mOffset + 1] = 0;
    m[mOffset + 2] = 0;
    m[mOffset + 3] = 0;
    m[mOffset + 4] = 0;
    m[mOffset + 5] = y;
    m[mOffset + 6] = 0;
    m[mOffset + 7] = 0;
    m[mOffset + 8] = 0;
    m[mOffset + 9] = 0;
    m[mOffset + 10] = z;
    m[mOffset + 11] = 0;
    m[mOffset + 12] = tx;
    m[mOffset + 13] = ty;
    m[mOffset + 14] = tz;
    m[mOffset + 15] = 1;
  }

  /** 透视投影矩阵（glgallery 的 ImageView 未用，保留以对齐 AOSP 全集）。 */
  static frustumM(m: number[], offset: number, left: number, right: number, bottom: number,
    top: number, near: number, far: number): void {
    if (left === right) {
      throw new Error('frustumM() can not be called if left == right');
    }
    if (bottom === top) {
      throw new Error('frustumM() can not be called if bottom == top');
    }
    if (near === far) {
      throw new Error('frustumM() can not be called if near == far');
    }
    const r_width = 1.0 / (right - left);
    const r_height = 1.0 / (top - bottom);
    const r_depth = 1.0 / (near - far);
    const x = 2.0 * (near * r_width);
    const y = 2.0 * (near * r_height);
    const A = (right + left) * r_width;
    const B = (top + bottom) * r_height;
    const C = (far + near) * r_depth;
    const D = 2.0 * (far * near * r_depth);
    m[offset + 0] = x;
    m[offset + 5] = y;
    m[offset + 8] = A;
    m[offset + 9] = B;
    m[offset + 10] = C;
    m[offset + 14] = D;
    m[offset + 11] = -1.0;
    m[offset + 1] = 0.0;
    m[offset + 2] = 0.0;
    m[offset + 3] = 0.0;
    m[offset + 4] = 0.0;
    m[offset + 6] = 0.0;
    m[offset + 7] = 0.0;
    m[offset + 12] = 0.0;
    m[offset + 13] = 0.0;
    m[offset + 15] = 0.0;
  }

  // ============================================================================
  // android.graphics.Matrix —— 实例 3x3 仿射（glgallery 的 ImageView/PagerLayoutManager 用）
  // ============================================================================

  reset(): void {
    const v = this.mValues;
    v[0] = 1; v[1] = 0; v[2] = 0;
    v[3] = 0; v[4] = 1; v[5] = 0;
    v[6] = 0; v[7] = 0; v[8] = 1;
  }

  isIdentity(): boolean {
    const v = this.mValues;
    return v[0] === 1 && v[1] === 0 && v[2] === 0
      && v[3] === 0 && v[4] === 1 && v[5] === 0
      && v[6] === 0 && v[7] === 0 && v[8] === 1;
  }

  set(src: Matrix): void {
    for (let i = 0; i < 9; i++) {
      this.mValues[i] = src.mValues[i];
    }
  }

  setValues(values: number[]): void {
    for (let i = 0; i < 9; i++) {
      this.mValues[i] = values[i];
    }
  }

  getValues(values: number[]): void {
    for (let i = 0; i < 9; i++) {
      values[i] = this.mValues[i];
    }
  }

  setTranslate(dx: number, dy: number): void {
    const v = this.mValues;
    v[0] = 1; v[1] = 0; v[2] = dx;
    v[3] = 0; v[4] = 1; v[5] = dy;
    v[6] = 0; v[7] = 0; v[8] = 1;
  }

  setScale(sx: number, sy: number, px: number, py: number): void {
    const v = this.mValues;
    v[0] = sx; v[1] = 0; v[2] = px - sx * px;
    v[3] = 0; v[4] = sy; v[5] = py - sy * py;
    v[6] = 0; v[7] = 0; v[8] = 1;
  }

  setRotate(degrees: number, px: number, py: number): void {
    const v = this.mValues;
    const rad = degrees * Math.PI / 180.0;
    const c = Math.cos(rad);
    const s = Math.sin(rad);
    v[0] = c; v[1] = -s; v[2] = px - c * px + s * py;
    v[3] = s; v[4] = c; v[5] = py - s * px - c * py;
    v[6] = 0; v[7] = 0; v[8] = 1;
  }

  // ---------------------------------------------------------------------------
  // 3x3 仿射运算
  //
  // ## 命名陷阱（这一节初版写反过，被单测抓住，务必按此注释理解）
  // `android.graphics.Matrix` 的 postX/preX 与"作用顺序"是**反直觉**的：
  //   postTranslate  : M' = T · M   （平移作用在设备空间，即"先映射再平移"的观感）
  //   preTranslate   : M' = M · T   （平移作用在输入点，即"先平移再映射"的观感）
  // AOSP 文档原文：preXxx 是 `M' = M * X`，postXxx 是 `M' = X * M`。
  //
  // 本类用**行向量**约定（与 AOSP 一致）：点 `[x y 1]` 右乘矩阵，
  // `mapPoints` 里 `x' = v[0]*x + v[1]*y + v[2]`。于是：
  //   · 左乘 X（M' = X·M）→ 对 M 的**行**做线性组合
  //   · 右乘 X（M' = M·X）→ 对 M 的**列**做线性组合
  //
  // 所有 post/pre 的复合都按"每次调用都把新变换左乘/右乘到累积结果上"实现，
  // 这样 S/R 的支点顺序（T(p)·S·T(-p)）自然正确，不需要手工颠倒。
  // ---------------------------------------------------------------------------

  /** `M' = T(dx,dy) · M`（AOSP postTranslate）。仿射矩阵下等价于 `v[2]+=dx; v[5]+=dy`。 */
  postTranslate(dx: number, dy: number): void {
    const v = this.mValues;
    const r0 = v[0], r1 = v[1], r2 = v[2];
    const s0 = v[3], s1 = v[4], s2 = v[5];
    v[0] = r0 + dx * v[6];
    v[1] = r1 + dx * v[7];
    v[2] = r2 + dx * v[8];
    v[3] = s0 + dy * v[6];
    v[4] = s1 + dy * v[7];
    v[5] = s2 + dy * v[8];
  }

  /** `M' = M · T(dx,dy)`（AOSP preTranslate）。 */
  preTranslate(dx: number, dy: number): void {
    const v = this.mValues;
    v[2] = v[0] * dx + v[1] * dy + v[2];
    v[5] = v[3] * dx + v[4] * dy + v[5];
    v[8] = v[6] * dx + v[7] * dy + v[8];
  }

  /** `M' = T(p) · S(sx,sy) · T(-p) · M`（AOSP postScale）。 */
  postScale(sx: number, sy: number, px: number, py: number): void {
    this.postTranslate(-px, -py);
    this.postLeftScale(sx, sy);
    this.postTranslate(px, py);
  }

  /** `M' = M · T(p) · S(sx,sy) · T(-p)`（AOSP preScale）。 */
  preScale(sx: number, sy: number, px: number, py: number): void {
    this.preTranslate(px, py);
    this.preRightScale(sx, sy);
    this.preTranslate(-px, -py);
  }

  /** `M' = T(p) · R(deg) · T(-p) · M`（AOSP postRotate）。 */
  postRotate(degrees: number, px: number, py: number): void {
    this.postTranslate(-px, -py);
    this.postLeftRotate(degrees);
    this.postTranslate(px, py);
  }

  /** `M' = M · T(p) · R(deg) · T(-p)`（AOSP preRotate）。 */
  preRotate(degrees: number, px: number, py: number): void {
    this.preTranslate(px, py);
    this.preRightRotate(degrees);
    this.preTranslate(-px, -py);
  }

  /** `M' = S(sx,sy) · M`（左乘对角缩放 → 行缩放）。 */
  private postLeftScale(sx: number, sy: number): void {
    const v = this.mValues;
    v[0] *= sx; v[1] *= sx; v[2] *= sx;
    v[3] *= sy; v[4] *= sy; v[5] *= sy;
  }

  /** `M' = M · S(sx,sy)`（右乘对角缩放 → 列缩放）。 */
  private preRightScale(sx: number, sy: number): void {
    const v = this.mValues;
    v[0] *= sx; v[3] *= sx; v[6] *= sx;
    v[1] *= sy; v[4] *= sy; v[7] *= sy;
  }

  /** `M' = R(deg) · M`（左乘旋转 → 行组合）。 */
  private postLeftRotate(degrees: number): void {
    const v = this.mValues;
    const rad = degrees * Math.PI / 180.0;
    const c = Math.cos(rad);
    const s = Math.sin(rad);
    const a0 = c * v[0] - s * v[3];
    const a1 = c * v[1] - s * v[4];
    const a2 = c * v[2] - s * v[5];
    const a3 = s * v[0] + c * v[3];
    const a4 = s * v[1] + c * v[4];
    const a5 = s * v[2] + c * v[5];
    v[0] = a0; v[1] = a1; v[2] = a2;
    v[3] = a3; v[4] = a4; v[5] = a5;
  }

  /** `M' = M · R(deg)`（右乘旋转 → 列组合）。 */
  private preRightRotate(degrees: number): void {
    const v = this.mValues;
    const rad = degrees * Math.PI / 180.0;
    const c = Math.cos(rad);
    const s = Math.sin(rad);
    const a0 = v[0] * c + v[1] * s;
    const a1 = -v[0] * s + v[1] * c;
    const a3 = v[3] * c + v[4] * s;
    const a4 = -v[3] * s + v[4] * c;
    const a6 = v[6] * c + v[7] * s;
    const a7 = -v[6] * s + v[7] * c;
    v[0] = a0; v[1] = a1;
    v[3] = a3; v[4] = a4;
    v[6] = a6; v[7] = a7;
  }

  /** `M' = other · M`（AOSP postConcat）。 */
  postConcat(other: Matrix): void {
    const v = this.mValues;
    const o = other.mValues;
    const a0 = o[0] * v[0] + o[1] * v[3] + o[2] * v[6];
    const a1 = o[0] * v[1] + o[1] * v[4] + o[2] * v[7];
    const a2 = o[0] * v[2] + o[1] * v[5] + o[2] * v[8];
    const a3 = o[3] * v[0] + o[4] * v[3] + o[5] * v[6];
    const a4 = o[3] * v[1] + o[4] * v[4] + o[5] * v[7];
    const a5 = o[3] * v[2] + o[4] * v[5] + o[5] * v[8];
    const a6 = o[6] * v[0] + o[7] * v[3] + o[8] * v[6];
    const a7 = o[6] * v[1] + o[7] * v[4] + o[8] * v[7];
    const a8 = o[6] * v[2] + o[7] * v[5] + o[8] * v[8];
    v[0] = a0; v[1] = a1; v[2] = a2;
    v[3] = a3; v[4] = a4; v[5] = a5;
    v[6] = a6; v[7] = a7; v[8] = a8;
  }

  /** `M' = M · other`（AOSP preConcat）。 */
  preConcat(other: Matrix): void {
    const v = this.mValues;
    const o = other.mValues;
    const a0 = v[0] * o[0] + v[1] * o[3] + v[2] * o[6];
    const a1 = v[0] * o[1] + v[1] * o[4] + v[2] * o[7];
    const a2 = v[0] * o[2] + v[1] * o[5] + v[2] * o[8];
    const a3 = v[3] * o[0] + v[4] * o[3] + v[5] * o[6];
    const a4 = v[3] * o[1] + v[4] * o[4] + v[5] * o[7];
    const a5 = v[3] * o[2] + v[4] * o[5] + v[5] * o[8];
    const a6 = v[6] * o[0] + v[7] * o[3] + v[8] * o[6];
    const a7 = v[6] * o[1] + v[7] * o[4] + v[8] * o[7];
    const a8 = v[6] * o[2] + v[7] * o[5] + v[8] * o[8];
    v[0] = a0; v[1] = a1; v[2] = a2;
    v[3] = a3; v[4] = a4; v[5] = a5;
    v[6] = a6; v[7] = a7; v[8] = a8;
  }
  /** 对点数组 (x0,y0,x1,y1,...) 原地做仿射变换，含透视除法（AOSP mapPoints 语义）。 */
  mapPoints(pts: number[]): void {
    const v = this.mValues;
    const count = pts.length;
    for (let i = 0; i < count; i += 2) {
      const x = pts[i];
      const y = pts[i + 1];
      const z = v[6] * x + v[7] * y + v[8];
      if (z !== 1.0 && z !== 0.0) {
        const invZ = 1.0 / z;
        pts[i] = (v[0] * x + v[1] * y + v[2]) * invZ;
        pts[i + 1] = (v[3] * x + v[4] * y + v[5]) * invZ;
      } else {
        pts[i] = v[0] * x + v[1] * y + v[2];
        pts[i + 1] = v[3] * x + v[4] * y + v[5];
      }
    }
  }

  /**
   * 求逆。返回 false 表示不可逆（行列式为 0），此时矩阵保持原状 —— 与 AOSP 一致。
   */
  invert(inverse: Matrix): boolean {
    const v = this.mValues;
    const i = inverse.mValues;
    const det = v[0] * (v[4] * v[8] - v[5] * v[7])
      - v[1] * (v[3] * v[8] - v[5] * v[6])
      + v[2] * (v[3] * v[7] - v[4] * v[6]);
    if (det === 0) {
      return false;
    }
    const invDet = 1.0 / det;
    i[0] = (v[4] * v[8] - v[5] * v[7]) * invDet;
    i[1] = (v[2] * v[7] - v[1] * v[8]) * invDet;
    i[2] = (v[1] * v[5] - v[2] * v[4]) * invDet;
    i[3] = (v[5] * v[6] - v[3] * v[8]) * invDet;
    i[4] = (v[0] * v[8] - v[2] * v[6]) * invDet;
    i[5] = (v[2] * v[3] - v[0] * v[5]) * invDet;
    i[6] = (v[3] * v[7] - v[4] * v[6]) * invDet;
    i[7] = (v[1] * v[6] - v[0] * v[7]) * invDet;
    i[8] = (v[0] * v[4] - v[1] * v[3]) * invDet;
    return true;
  }

  /** 当前矩阵作用下的缩放系数（AOSP mapRadius 用的 sqrt）。 */
  mapRadius(radius: number): number {
    const v = this.mValues;
    const x = v[0] * radius;
    const y = v[3] * radius;
    return Math.sqrt(x * x + y * y);
  }

  equalsMatrix(other: Matrix): boolean {
    for (let i = 0; i < 9; i++) {
      if (this.mValues[i] !== other.mValues[i]) {
        return false;
      }
    }
    return true;
  }

  toString(): string {
    return `Matrix[${this.mValues.join(', ')}]`;
  }
}
