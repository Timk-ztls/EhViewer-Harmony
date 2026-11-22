/*
 * Copyright (C) 2012 The Android Open Source Project
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
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Rect } from '../util/Rect';
import { RectF } from '../util/RectF';
import { Color } from '../util/Color';
import { Matrix } from '../util/Matrix';
import { GLMath } from '../util/GLMath';
import { PixelMapUtils, Size2D } from '../util/PixelMapUtils';
import { GLCanvas } from './GLCanvas';
import { GLPaint } from './GLPaint';
import { GLId } from './GLId';
import { BasicTexture } from './BasicTexture';
import { RawTexture } from './RawTexture';
import { GLES20IdImpl } from './GLES20IdImpl';
import { GLConst } from '../native/GLConst';
import { GLErr, GLCommand, GLNative } from '../native/GLNativeBridge';
import { GLCommandBuffer } from '../native/GLCommandBuffer';

const TAG = 'GLES20Canvas';
const DOMAIN = 0x0000;

/**
 * `com.hippo.lib.glview.glrenderer.GLES20Canvas` 的 ArkTS 等价实现。
 *
 * ## 移植口径
 * 结构与状态机 **逐方法照搬**（矩阵栈/alpha 栈/save-restore 位/纹理坐标换算/统计计数器）。
 * 唯一的实质改动是 GL 调用的落地方式：
 *
 * ```
 * 上游：  GLES20.glUniformMatrix4fv(handle, 1, false, m, 0);   // 进程内静态绑定
 * 鸿蒙：  this.mCmd.cmd(GLCommand.UNIFORM_MATRIX, [kind, ...m]);  // 录制，每帧一次 replay
 * ```
 *
 * 为什么不能逐调用跨界：见 `native/GLNativeBridge.ets` 的类注释（300 quad/帧 × 20 次 ≈ 30ms+）。
 *
 * ## 与上游的行为等价点（逐条自查）
 * - `translate(x,y)` 用与上游相同的**内联优化**（不调 Matrix.translateM），并把两者
 *   的一致性用单测固定（`inline translate parity`）
 * - `getColor()` 的预乘 alpha 顺序、`OPAQUE_ALPHA = 0.95` 阈值、`enableBlending` 条件不变
 * - `convertCoordinate()` 里对源/目标矩形的裁剪顺序不变（先 x 后 y，先改 target 再改 source）
 * - `setSize()` 只在**没有 render target** 时才写 mScreenWidth/Height 并做 y 翻转
 * - `drawMixed()` 的 save(SAVE_FLAG_ALPHA) / cappedRatio / 0 != Color.alpha(toColor) 分支不变
 *
 * ## 差异（登记在 MR 对照表）
 * 1. `checkError()` 不再每次 GL 调用后立即查错：批处理下一帧只查一次（`flush()` 里由
 *    native 返回 GLErr）。开发期可开 `DETAILED_ERROR_CHECK` 逐命令查，但会掉帧。
 * 2. `dumpStatisticsAndClear()` 用 hilog 输出（上游用 `android.util.Log`）。
 * 3. `uploadBuffer()` 的两个重载合成 `uploadBufferFloat` / `uploadBufferByte`（ArkTS 无重载）。
 */
export class GLES20Canvas extends GLCanvas {
  private static readonly FLOAT_SIZE: number = 4;
  private static readonly OPAQUE_ALPHA: number = 0.95;

  private static readonly COORDS_PER_VERTEX: number = 2;
  private static readonly VERTEX_STRIDE: number = GLES20Canvas.COORDS_PER_VERTEX
    * GLES20Canvas.FLOAT_SIZE;

  private static readonly COUNT_FILL_VERTEX: number = 4;
  private static readonly COUNT_LINE_VERTEX: number = 2;
  private static readonly COUNT_RECT_VERTEX: number = 4;
  private static readonly COUNT_CIRCLE_VERTEX: number = 120; // 4 的倍数
  private static readonly OFFSET_FILL_RECT: number = 0;
  private static readonly OFFSET_DRAW_LINE: number = GLES20Canvas.OFFSET_FILL_RECT
    + GLES20Canvas.COUNT_FILL_VERTEX;
  private static readonly OFFSET_DRAW_RECT: number = GLES20Canvas.OFFSET_DRAW_LINE
    + GLES20Canvas.COUNT_LINE_VERTEX;
  private static readonly OFFSET_FILL_CIRCLE: number = GLES20Canvas.OFFSET_DRAW_RECT
    + GLES20Canvas.COUNT_RECT_VERTEX;
  private static readonly OFFSET_DRAW_CIRCLE: number = GLES20Canvas.OFFSET_FILL_CIRCLE + 1;
  private static readonly OFFSET_LAST: number = GLES20Canvas.OFFSET_DRAW_CIRCLE
    + GLES20Canvas.COUNT_CIRCLE_VERTEX + 1;

  /** 顶点表：填充矩形 / 线段 / 矩形描边 / 圆（扇形）。构造时按上游公式一次性生成。 */
  private static readonly BOX_COORDINATES: number[] = GLES20Canvas.buildBoxCoordinates();

  private static readonly BOUNDS_COORDINATES: number[] = [0, 0, 0, 1, 1, 1, 0, 1];

  // shader 属性/统一变量名（与上游逐字一致，native 侧按同名查 location）
  private static readonly POSITION_ATTRIBUTE: string = 'aPosition';
  private static readonly COLOR_UNIFORM: string = 'uColor';
  private static readonly MATRIX_UNIFORM: string = 'uMatrix';
  private static readonly TEXTURE_MATRIX_UNIFORM: string = 'uTextureMatrix';
  private static readonly TEXTURE_SAMPLER_UNIFORM: string = 'uTextureSampler';
  private static readonly ALPHA_UNIFORM: string = 'uAlpha';
  private static readonly TEXTURE_COORD_ATTRIBUTE: string = 'aTextureCoordinate';

  static readonly DRAW_VERTEX_SHADER: string = ''
    + 'uniform mat4 ' + GLES20Canvas.MATRIX_UNIFORM + ';\n'
    + 'attribute vec2 ' + GLES20Canvas.POSITION_ATTRIBUTE + ';\n'
    + 'void main() {\n'
    + '  vec4 pos = vec4(' + GLES20Canvas.POSITION_ATTRIBUTE + ', 0.0, 1.0);\n'
    + '  gl_Position = ' + GLES20Canvas.MATRIX_UNIFORM + ' * pos;\n'
    + '}\n';

  static readonly DRAW_FRAGMENT_SHADER: string = ''
    + 'precision mediump float;\n'
    + 'uniform vec4 ' + GLES20Canvas.COLOR_UNIFORM + ';\n'
    + 'void main() {\n'
    + '  gl_FragColor = ' + GLES20Canvas.COLOR_UNIFORM + ';\n'
    + '}\n';

  static readonly TEXTURE_VERTEX_SHADER: string = ''
    + 'uniform mat4 ' + GLES20Canvas.MATRIX_UNIFORM + ';\n'
    + 'uniform mat4 ' + GLES20Canvas.TEXTURE_MATRIX_UNIFORM + ';\n'
    + 'attribute vec2 ' + GLES20Canvas.POSITION_ATTRIBUTE + ';\n'
    + 'varying vec2 vTextureCoord;\n'
    + 'void main() {\n'
    + '  vec4 pos = vec4(' + GLES20Canvas.POSITION_ATTRIBUTE + ', 0.0, 1.0);\n'
    + '  gl_Position = ' + GLES20Canvas.MATRIX_UNIFORM + ' * pos;\n'
    + '  vTextureCoord = (' + GLES20Canvas.TEXTURE_MATRIX_UNIFORM + ' * pos).xy;\n'
    + '}\n';

  static readonly MESH_VERTEX_SHADER: string = ''
    + 'uniform mat4 ' + GLES20Canvas.MATRIX_UNIFORM + ';\n'
    + 'attribute vec2 ' + GLES20Canvas.POSITION_ATTRIBUTE + ';\n'
    + 'attribute vec2 ' + GLES20Canvas.TEXTURE_COORD_ATTRIBUTE + ';\n'
    + 'varying vec2 vTextureCoord;\n'
    + 'void main() {\n'
    + '  vec4 pos = vec4(' + GLES20Canvas.POSITION_ATTRIBUTE + ', 0.0, 1.0);\n'
    + '  gl_Position = ' + GLES20Canvas.MATRIX_UNIFORM + ' * pos;\n'
    + '  vTextureCoord = ' + GLES20Canvas.TEXTURE_COORD_ATTRIBUTE + ';\n'
    + '}\n';

  static readonly TEXTURE_FRAGMENT_SHADER: string = ''
    + 'precision mediump float;\n'
    + 'varying vec2 vTextureCoord;\n'
    + 'uniform float ' + GLES20Canvas.ALPHA_UNIFORM + ';\n'
    + 'uniform sampler2D ' + GLES20Canvas.TEXTURE_SAMPLER_UNIFORM + ';\n'
    + 'void main() {\n'
    + '  gl_FragColor = texture2D(' + GLES20Canvas.TEXTURE_SAMPLER_UNIFORM + ', vTextureCoord);\n'
    + '  gl_FragColor *= ' + GLES20Canvas.ALPHA_UNIFORM + ';\n'
    + '}\n';

  static readonly OES_TEXTURE_FRAGMENT_SHADER: string = ''
    + '#extension GL_OES_EGL_image_external : require\n'
    + 'precision mediump float;\n'
    + 'varying vec2 vTextureCoord;\n'
    + 'uniform float ' + GLES20Canvas.ALPHA_UNIFORM + ';\n'
    + 'uniform samplerExternalOES ' + GLES20Canvas.TEXTURE_SAMPLER_UNIFORM + ';\n'
    + 'void main() {\n'
    + '  gl_FragColor = texture2D(' + GLES20Canvas.TEXTURE_SAMPLER_UNIFORM + ', vTextureCoord);\n'
    + '  gl_FragColor *= ' + GLES20Canvas.ALPHA_UNIFORM + ';\n'
    + '}\n';

  /** program 种类，命令流里用它替代 GL program handle（location 是 native 的实现细节）。 */
  static readonly PROGRAM_DRAW: number = 0;
  static readonly PROGRAM_TEXTURE: number = 1;
  static readonly PROGRAM_OES_TEXTURE: number = 2;
  static readonly PROGRAM_MESH: number = 3;

  /** 属性槽位：0=aPosition，1=aTextureCoordinate（mesh 用）。 */
  private static readonly ATTR_POSITION: number = 0;
  private static readonly ATTR_TEXTURE_COORD: number = 1;

  private static readonly INITIAL_RESTORE_STATE_SIZE: number = 8;
  private static readonly MATRIX_SIZE: number = 16;

  // ---- 状态栈 ----
  private mMatrices: number[] = new Array<number>(
    GLES20Canvas.INITIAL_RESTORE_STATE_SIZE * GLES20Canvas.MATRIX_SIZE).fill(0);
  private mAlphas: number[] = new Array<number>(GLES20Canvas.INITIAL_RESTORE_STATE_SIZE).fill(0);
  private mSaveFlags: number[] = [];
  private mCurrentAlphaIndex: number = 0;
  private mCurrentMatrixIndex: number = 0;

  // ---- 视口 ----
  private mWidth: number = 0;
  private mHeight: number = 0;
  private mProjectionMatrix: number[] = new Array<number>(GLES20Canvas.MATRIX_SIZE).fill(0);
  private mScreenWidth: number = 0;
  private mScreenHeight: number = 0;

  /** BOX_COORDINATES 的 VBO id（构造时上传一次）。 */
  private mBoxCoordinates: number = -1;

  // ---- 回收队列 ----
  private mUnboundTextures: number[] = [];
  private mDeleteBuffers: number[] = [];

  // ---- 统计（调试） ----
  private mCountDrawMesh: number = 0;
  private mCountTextureRect: number = 0;
  private mCountFillRect: number = 0;
  private mCountDrawLine: number = 0;

  // ---- framebuffer ----
  private mFrameBuffer: number = -1;
  private mTargetTextures: (RawTexture | null)[] = [null];

  // ---- 临时变量（每帧复用，避免分配） ----
  private mTempMatrix: number[] = new Array<number>(32).fill(0);
  private mTempColor: number[] = new Array<number>(4).fill(0);
  private mTempSourceRect: RectF = new RectF();
  private mTempTargetRect: RectF = new RectF();
  private mTempTextureMatrix: number[] = new Array<number>(GLES20Canvas.MATRIX_SIZE).fill(0);

  private static readonly mGLId: GLId = new GLES20IdImpl();

  /** 命令流编码器（每帧复用）。 */
  private mCmd: GLCommandBuffer = new GLCommandBuffer();

  /** 本帧是否已 flush（防重复提交）。 */
  private mFrameOpen: boolean = false;

  /** 最近一次 `bindTextureForUpload` 绑定的纹理 id（-1 表示无）。见 `getBoundTextureId()`。 */
  private mCurrentBoundTextureId: number = -1;
  private mLastFrameError: GLErr = GLErr.OK;

  constructor() {
    super();
    Matrix.setIdentityM(this.mTempTextureMatrix, 0);
    Matrix.setIdentityM(this.mMatrices, this.mCurrentMatrixIndex);
    this.mAlphas[this.mCurrentAlphaIndex] = 1.0;
    this.mTargetTextures = [null];

    const backend = GLNative.backend();
    const initErr = backend.init();
    if (initErr !== GLErr.OK) {
      hilog.error(DOMAIN, TAG, 'GLES20Canvas init failed: %{public}d', initErr as number);
      throw new Error(`GLES20Canvas init failed: ${initErr}`);
    }

    const boxData = new Float32Array(GLES20Canvas.BOX_COORDINATES.length);
    for (let i = 0; i < GLES20Canvas.BOX_COORDINATES.length; i++) {
      boxData[i] = GLES20Canvas.BOX_COORDINATES[i];
    }
    this.mBoxCoordinates = backend.genBuffer(GLConst.GL_ARRAY_BUFFER);
    if (this.mBoxCoordinates < 0) {
      throw new Error('GLES20Canvas: glGenBuffers for BOX_COORDINATES failed');
    }
    if (backend.bufferDataF32(this.mBoxCoordinates, boxData) !== GLErr.OK) {
      throw new Error('GLES20Canvas: glBufferData for BOX_COORDINATES failed');
    }
  }

  /**
   * 生成顶点表。逐行照抄上游静态块：
   * 前 11 个点手写，圆环部分用 `sin(radians(90 / n * i)) / 2` 铺 4 个象限。
   */
  private static buildBoxCoordinates(): number[] {
    const coords = new Array<number>(GLES20Canvas.OFFSET_LAST * 2).fill(0);
    const temp: number[] = [
      0, 0, // 填充矩形
      1, 0,
      0, 1,
      1, 1,
      0, 0, // 线段
      1, 1,
      0, 0, // 矩形描边
      0, 1,
      1, 1,
      1, 0,
      0.5, 0.5 // 圆心
    ];
    for (let i = 0; i < temp.length; i++) {
      coords[i] = temp[i];
    }

    const arrayOffset = GLES20Canvas.OFFSET_DRAW_CIRCLE * 2;
    const n = Math.trunc(GLES20Canvas.COUNT_CIRCLE_VERTEX / 4);
    for (let i = 0; i <= n; i++) {
      const value = Math.sin(GLMath.radians(90.0 / n * i)) / 2;
      const positive = value + 0.5;
      const negative = -value + 0.5;
      coords[arrayOffset + n * 0 + i * 2 + 1] = positive;
      coords[arrayOffset + n * 2 - i * 2 + 0] = positive;
      coords[arrayOffset + n * 2 + i * 2 + 0] = negative;
      coords[arrayOffset + n * 4 - i * 2 + 1] = positive;
      coords[arrayOffset + n * 4 + i * 2 + 1] = negative;
      coords[arrayOffset + n * 6 - i * 2 + 0] = negative;
      coords[arrayOffset + n * 6 + i * 2 + 0] = positive;
      coords[arrayOffset + n * 8 - i * 2 + 1] = negative;
    }
    return coords;
  }

  // ==========================================================================
  // GLId / 帧
  // ==========================================================================

  getGLId(): GLId {
    return GLES20Canvas.mGLId;
  }

  /**
   * 提交本帧：先执行剩余命令流，再 present（替换上游 `GLSurfaceView` 的自动 swap）。
   * `GLRootView.draw()` 末尾调用。
   */
  getLastFrameError(): GLErr {
    return this.mLastFrameError;
  }

  flush(): void {
    if (!this.mFrameOpen) {
      return;
    }
    this.mCmd.cmd0(GLCommand.END_FRAME);
    const backend = GLNative.backend();
    const err = backend.replay(this.mCmd.toFloat32());
    this.mCmd.reset();
    if (err !== GLErr.OK) {
      this.mLastFrameError = err;
      hilog.error(DOMAIN, TAG, 'replay failed: %{public}d', err as number);
    }
    const presentErr = backend.present();
    if (presentErr !== GLErr.OK) {
      this.mLastFrameError = presentErr;
      hilog.error(DOMAIN, TAG, 'present failed: %{public}d', presentErr as number);
    } else if (err === GLErr.OK) {
      this.mLastFrameError = GLErr.OK;
    }
    this.mFrameOpen = false;
  }

  /**
   * 把已录制的命令立即执行掉（**不上屏**），用于"必须跨独立 NAPI 的纹理上传"之前。
   *
   * 存在意义：`texImage2D`/`texSubImage2D` 要带 PixelMap 走独立接口，无法编码进命令流；
   * 若不先冲刷，`BIND_TEXTURE` 会在上传之后才执行，纹理就绑错了目标。
   * 这是批处理架构唯一的顺序陷阱，用单测"上传前后的命令顺序"固定住。
   */
  private flushPending(): void {
    if (this.mCmd.size() === 0) {
      return;
    }
    const err = GLNative.backend().replay(this.mCmd.toFloat32());
    this.mCmd.reset();
    if (err !== GLErr.OK) {
      this.mLastFrameError = err;
      hilog.error(DOMAIN, TAG, 'flushPending failed: %{public}d', err as number);
    }
  }

  /** 每帧开头调用（`GLRootView` 的 onDrawFrame 入口）。 */
  beginFrame(): void {
    this.mCmd.reset();
    this.mFrameOpen = true;
  }

  setSize(width: number, height: number): void {
    this.mWidth = width;
    this.mHeight = height;
    this.mCmd.cmd(GLCommand.SET_VIEWPORT, [width, height]);
    // 只有画到屏幕时才需要同步 EGLSurface 尺寸；画到 render target 时仅改 viewport
    if (this.getTargetTexture() === null) {
      GLNative.backend().setSurface(width, height);
    }
    Matrix.setIdentityM(this.mMatrices, this.mCurrentMatrixIndex);
    Matrix.orthoM(this.mProjectionMatrix, 0, 0, width, 0, height, -1, 1);
    if (this.getTargetTexture() === null) {
      this.mScreenWidth = width;
      this.mScreenHeight = height;
      Matrix.translateM(this.mMatrices, this.mCurrentMatrixIndex, 0, height, 0);
      Matrix.scaleM(this.mMatrices, this.mCurrentMatrixIndex, 1, -1, 1);
    }
  }

  clearBuffer(): void {
    this.mCmd.cmd(GLCommand.CLEAR, [0, 0, 0, 1]);
  }

  clearBufferArgb(argb: number[]): void {
    this.mCmd.cmd(GLCommand.CLEAR, [argb[1], argb[2], argb[3], argb[0]]);
  }

  // ==========================================================================
  // alpha / 矩阵
  // ==========================================================================

  getAlpha(): number {
    return this.mAlphas[this.mCurrentAlphaIndex];
  }

  setAlpha(alpha: number): void {
    this.mAlphas[this.mCurrentAlphaIndex] = alpha;
  }

  multiplyAlpha(alpha: number): void {
    this.setAlpha(this.getAlpha() * alpha);
  }

  translate(x: number, y: number, z?: number): void {
    if (z === undefined) {
      // 上游的快速路径：z 已知为 0，内联展开 Matrix.translateM 并去掉循环
      const index = this.mCurrentMatrixIndex;
      const m = this.mMatrices;
      m[index + 12] += m[index + 0] * x + m[index + 4] * y;
      m[index + 13] += m[index + 1] * x + m[index + 5] * y;
      m[index + 14] += m[index + 2] * x + m[index + 6] * y;
      m[index + 15] += m[index + 3] * x + m[index + 7] * y;
      return;
    }
    Matrix.translateM(this.mMatrices, this.mCurrentMatrixIndex, x, y, z);
  }

  scale(sx: number, sy: number, sz: number): void {
    Matrix.scaleM(this.mMatrices, this.mCurrentMatrixIndex, sx, sy, sz);
  }

  rotate(angle: number, x: number, y: number, z: number): void {
    if (angle === 0) {
      return;
    }
    const temp = this.mTempMatrix;
    Matrix.setRotateM(temp, 0, angle, x, y, z);
    const matrix = this.mMatrices;
    const index = this.mCurrentMatrixIndex;
    Matrix.multiplyMM(temp, GLES20Canvas.MATRIX_SIZE, matrix, index, temp, 0);
    for (let i = 0; i < GLES20Canvas.MATRIX_SIZE; i++) {
      matrix[index + i] = temp[GLES20Canvas.MATRIX_SIZE + i];
    }
  }

  multiplyMatrix(matrix: number[], offset: number): void {
    const temp = this.mTempMatrix;
    const currentMatrix = this.mMatrices;
    const index = this.mCurrentMatrixIndex;
    Matrix.multiplyMM(temp, 0, currentMatrix, index, matrix, offset);
    for (let i = 0; i < 16; i++) {
      currentMatrix[index + i] = temp[i];
    }
  }

  save(saveFlags?: number): void {
    const flags: number = saveFlags === undefined ? GLCanvas.SAVE_FLAG_ALL : saveFlags;
    const saveAlpha: boolean = (flags & GLCanvas.SAVE_FLAG_ALPHA) === GLCanvas.SAVE_FLAG_ALPHA;
    if (saveAlpha) {
      const currentAlpha = this.getAlpha();
      this.mCurrentAlphaIndex++;
      if (this.mAlphas.length <= this.mCurrentAlphaIndex) {
        const grown = new Array<number>(this.mAlphas.length * 2).fill(0);
        for (let i = 0; i < this.mAlphas.length; i++) {
          grown[i] = this.mAlphas[i];
        }
        this.mAlphas = grown;
      }
      this.mAlphas[this.mCurrentAlphaIndex] = currentAlpha;
    }
    const saveMatrix: boolean = (flags & GLCanvas.SAVE_FLAG_MATRIX) === GLCanvas.SAVE_FLAG_MATRIX;
    if (saveMatrix) {
      const currentIndex = this.mCurrentMatrixIndex;
      this.mCurrentMatrixIndex += GLES20Canvas.MATRIX_SIZE;
      if (this.mMatrices.length <= this.mCurrentMatrixIndex) {
        const grown = new Array<number>(this.mMatrices.length * 2).fill(0);
        for (let i = 0; i < this.mMatrices.length; i++) {
          grown[i] = this.mMatrices[i];
        }
        this.mMatrices = grown;
      }
      for (let i = 0; i < GLES20Canvas.MATRIX_SIZE; i++) {
        this.mMatrices[this.mCurrentMatrixIndex + i] = this.mMatrices[currentIndex + i];
      }
    }
    this.mSaveFlags.push(flags);
  }

  restore(): void {
    if (this.mSaveFlags.length === 0) {
      throw new Error('restore() without matching save()');
    }
    const restoreFlags = this.mSaveFlags.pop() as number;
    const restoreAlpha: boolean = (restoreFlags & GLCanvas.SAVE_FLAG_ALPHA) === GLCanvas.SAVE_FLAG_ALPHA;
    if (restoreAlpha) {
      this.mCurrentAlphaIndex--;
    }
    const restoreMatrix: boolean = (restoreFlags & GLCanvas.SAVE_FLAG_MATRIX) === GLCanvas.SAVE_FLAG_MATRIX;
    if (restoreMatrix) {
      this.mCurrentMatrixIndex -= GLES20Canvas.MATRIX_SIZE;
    }
  }

  // ==========================================================================
  // 线/矩形/椭圆/扇形
  // ==========================================================================

  drawLine(x1: number, y1: number, x2: number, y2: number, paint: GLPaint): void {
    this.drawWithPaint(GLConst.GL_LINE_STRIP, GLES20Canvas.OFFSET_DRAW_LINE,
      GLES20Canvas.COUNT_LINE_VERTEX, x1, y1, x2 - x1, y2 - y1, paint);
    this.mCountDrawLine++;
  }

  drawRect(x: number, y: number, width: number, height: number, paint: GLPaint): void {
    this.drawWithPaint(GLConst.GL_LINE_LOOP, GLES20Canvas.OFFSET_DRAW_RECT,
      GLES20Canvas.COUNT_RECT_VERTEX, x, y, width, height, paint);
    this.mCountDrawLine++;
  }

  drawOval(cx: number, cy: number, radiusX: number, radiusY: number, paint: GLPaint): void {
    const halfLineWidth = paint.getLineWidth() / 2;
    this.fillOval(cx, cy, radiusX + halfLineWidth, radiusY + halfLineWidth, paint.getColor());
    this.fillOval(cx, cy, radiusX - halfLineWidth, radiusY - halfLineWidth,
      paint.getBackgroundColor());
  }

  drawArc(cx: number, cy: number, radiusX: number, radiusY: number, sweepAngle: number,
    paint: GLPaint): void {
    const halfLineWidth = paint.getLineWidth() / 2;
    this.fillSector(cx, cy, radiusX + halfLineWidth, radiusY + halfLineWidth, sweepAngle,
      paint.getColor());
    this.fillOval(cx, cy, radiusX - halfLineWidth, radiusY - halfLineWidth,
      paint.getBackgroundColor());
  }

  /** 上游 `draw(type, offset, count, x, y, w, h, GLPaint)`。 */
  private drawWithPaint(type: number, offset: number, count: number, x: number, y: number,
    width: number, height: number, paint: GLPaint): void {
    this.drawSolid(type, offset, count, x, y, width, height, paint.getColor(),
      paint.getLineWidth());
  }

  private drawSolid(type: number, offset: number, count: number, x: number, y: number, width: number,
    height: number, color: number, lineWidth: number): void {
    this.prepareDraw(offset, color, lineWidth);
    this.drawProgram(GLES20Canvas.PROGRAM_DRAW, type, count, x, y, width, height);
  }

  private prepareDraw(offset: number, color: number, lineWidth: number): void {
    this.mCmd.cmd(GLCommand.USE_PROGRAM, [GLES20Canvas.PROGRAM_DRAW]);
    if (lineWidth > 0) {
      this.mCmd.cmd(GLCommand.LINE_WIDTH, [lineWidth]);
    }
    const colorArray = this.getColor(color);
    const blendingEnabled = colorArray[3] < 1.0;
    this.enableBlending(blendingEnabled);
    if (blendingEnabled) {
      this.mCmd.cmd(GLCommand.BLEND_COLOR,
        [colorArray[0], colorArray[1], colorArray[2], colorArray[3]]);
    }
    this.mCmd.cmd(GLCommand.UNIFORM_COLOR,
      [GLES20Canvas.PROGRAM_DRAW, colorArray[0], colorArray[1], colorArray[2], colorArray[3]]);
    this.setPosition(GLES20Canvas.PROGRAM_DRAW, offset);
  }

  /**
   * ARGB → 预乘 alpha 的 RGBA 数组。
   * 注意上游先算 alpha 再乘进 RGB，得到的是**预乘**值，配合
   * `glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA)` 才是正确的半透明叠加。
   */
  private getColor(color: number): number[] {
    const alpha = ((color >>> 24) & 0xFF) / 255.0 * this.getAlpha();
    const red = ((color >>> 16) & 0xFF) / 255.0 * alpha;
    const green = ((color >>> 8) & 0xFF) / 255.0 * alpha;
    const blue = (color & 0xFF) / 255.0 * alpha;
    this.mTempColor[0] = red;
    this.mTempColor[1] = green;
    this.mTempColor[2] = blue;
    this.mTempColor[3] = alpha;
    return this.mTempColor;
  }

  private enableBlending(enable: boolean): void {
    this.mCmd.cmd(GLCommand.BLEND_ENABLE, [enable ? 1 : 0]);
  }

  /**
   * `offset` 是**顶点下标**（OFFSET_FILL_RECT=0 / OFFSET_DRAW_LINE=4 / OFFSET_DRAW_RECT=6 /
   * OFFSET_FILL_CIRCLE=10 / OFFSET_DRAW_CIRCLE=11），这里换算成字节再写进命令：
   * `offset * VERTEX_STRIDE`（VERTEX_STRIDE = 2 float = 8 字节）。
   * stride 本身在命令里不传（恒 = COORDS_PER_VERTEX * 4），见 `GLCommand.VERTEX_ATTRIB_POINTER`。
   */
  private setPosition(program: number, offset: number): void {
    this.mCmd.cmd(GLCommand.BIND_ARRAY_BUFFER, [this.mBoxCoordinates]);
    this.mCmd.cmd(GLCommand.VERTEX_ATTRIB_POINTER,
      [program, GLES20Canvas.ATTR_POSITION, GLES20Canvas.COORDS_PER_VERTEX,
        offset * GLES20Canvas.VERTEX_STRIDE]);
    this.mCmd.cmd(GLCommand.BIND_ARRAY_BUFFER, [0]);
  }

  private drawProgram(program: number, type: number, count: number, x: number, y: number,
    width: number, height: number): void {
    this.setMatrix(program, x, y, width, height);
    this.mCmd.cmd(GLCommand.ENABLE_ATTRIB, [program, GLES20Canvas.ATTR_POSITION]);
    this.mCmd.cmd(GLCommand.DRAW_ARRAYS, [type, 0, count]);
    this.mCmd.cmd(GLCommand.DISABLE_ATTRIB, [program, GLES20Canvas.ATTR_POSITION]);
  }

  private setMatrix(program: number, x: number, y: number, width: number, height: number): void {
    Matrix.translateMFrom(this.mTempMatrix, 0, this.mMatrices, this.mCurrentMatrixIndex, x, y, 0);
    Matrix.scaleM(this.mTempMatrix, 0, width, height, 1);
    Matrix.multiplyMM(this.mTempMatrix, GLES20Canvas.MATRIX_SIZE, this.mProjectionMatrix, 0,
      this.mTempMatrix, 0);
    const args: number[] = [program];
    for (let i = 0; i < 16; i++) {
      args.push(this.mTempMatrix[GLES20Canvas.MATRIX_SIZE + i]);
    }
    this.mCmd.cmd(GLCommand.UNIFORM_MATRIX, args);
  }

  fillRect(x: number, y: number, width: number, height: number, color: number): void {
    this.drawSolid(GLConst.GL_TRIANGLE_STRIP, GLES20Canvas.OFFSET_FILL_RECT,
      GLES20Canvas.COUNT_FILL_VERTEX, x, y, width, height, color, 0);
    this.mCountFillRect++;
  }

  fillOval(cx: number, cy: number, radiusX: number, radiusY: number, color: number): void {
    this.drawSolid(GLConst.GL_TRIANGLE_FAN, GLES20Canvas.OFFSET_FILL_CIRCLE,
      GLES20Canvas.OFFSET_LAST - GLES20Canvas.OFFSET_FILL_CIRCLE, cx - radiusX, cy - radiusY,
      radiusX * 2, radiusY * 2, color, 0);
    this.mCountFillRect++;
  }

  fillSector(cx: number, cy: number, radiusX: number, radiusY: number, sweepAngle: number,
    color: number): void {
    const conjugateAngle = Math.abs(360 - GLMath.positiveModulo(sweepAngle, 360));
    const conjugateCount = Math.round(GLES20Canvas.COUNT_CIRCLE_VERTEX * conjugateAngle / 360);
    if (conjugateCount === 0) {
      // 整圆
      this.fillOval(cx, cy, radiusX, radiusY, color);
    } else if (conjugateCount < GLES20Canvas.COUNT_CIRCLE_VERTEX) {
      this.drawSolid(GLConst.GL_TRIANGLE_FAN, GLES20Canvas.OFFSET_FILL_CIRCLE,
        GLES20Canvas.OFFSET_LAST - GLES20Canvas.OFFSET_FILL_CIRCLE - conjugateCount,
        cx - radiusX, cy - radiusY, radiusX * 2, radiusY * 2, color, 0);
      this.mCountFillRect++;
    }
  }

  // ==========================================================================
  // 纹理绘制
  // ==========================================================================

  drawTexture(texture: BasicTexture, a: number | RectF | number[], b?: number | RectF,
    c?: number, d?: number, e?: number, _f?: number): void {
    if (typeof a === 'number') {
      const x = a;
      const y = b as number;
      const width = c as number;
      const height = d as number;
      if (width <= 0 || height <= 0) {
        return;
      }
      GLES20Canvas.copyTextureCoordinates(texture, this.mTempSourceRect);
      this.mTempTargetRect.set(x, y, x + width, y + height);
      GLES20Canvas.convertCoordinate(this.mTempSourceRect, this.mTempTargetRect, texture);
      this.drawTextureRect(texture, this.mTempSourceRect, this.mTempTargetRect);
      return;
    }
    if (a instanceof RectF) { 
      const source = a;
      const target = b as RectF;
      if (target.width() <= 0 || target.height() <= 0) {
        return;
      }
      this.mTempSourceRect.set(source);
      this.mTempTargetRect.set(target);
      GLES20Canvas.convertCoordinate(this.mTempSourceRect, this.mTempTargetRect, texture);
      this.drawTextureRect(texture, this.mTempSourceRect, this.mTempTargetRect);
      return;
    }
    // 第三种形态：外部纹理变换矩阵 + (x, y, w, h)
    const textureTransform = a;
    const x = b as number;
    const y = c as number;
    const w = d as number;
    const h = e as number;
    if (w <= 0 || h <= 0) {
      return;
    }
    this.mTempTargetRect.set(x, y, x + w, y + h);
    this.drawTextureRectRaw(texture, textureTransform, this.mTempTargetRect);
  }

  private static copyTextureCoordinates(texture: BasicTexture, outRect: RectF): void {
    let left = 0;
    let top = 0;
    let right = texture.getWidth();
    let bottom = texture.getHeight();
    if (texture.hasBorder()) {
      left = 1;
      top = 1;
      right -= 1;
      bottom -= 1;
    }
    outRect.set(left, top, right, bottom);
  }

  /**
   * 源矩形 → 纹理坐标，并按纹理实际尺寸裁剪越界部分。
   * 顺序与上游一致：先归一化，再依次裁 x、裁 y（先改 target 再改 source）。
   */
  private static convertCoordinate(source: RectF, target: RectF, texture: BasicTexture): void {
    const width = texture.getWidth();
    const height = texture.getHeight();
    const texWidth = texture.getTextureWidth();
    const texHeight = texture.getTextureHeight();
    source.left /= texWidth;
    source.right /= texWidth;
    source.top /= texHeight;
    source.bottom /= texHeight;

    const xBound = width / texWidth;
    if (source.right > xBound) {
      target.right = target.left + target.width() * (xBound - source.left) / source.width();
      source.right = xBound;
    }
    const yBound = height / texHeight;
    if (source.bottom > yBound) {
      target.bottom = target.top + target.height() * (yBound - source.top) / source.height();
      source.bottom = yBound;
    }
  }

  private drawTextureRect(texture: BasicTexture, source: RectF, target: RectF): void {
    this.setTextureMatrix(source);
    this.drawTextureRectRaw(texture, this.mTempTextureMatrix, target);
  }

  private setTextureMatrix(source: RectF): void {
    this.mTempTextureMatrix[0] = source.width();
    this.mTempTextureMatrix[5] = source.height();
    this.mTempTextureMatrix[12] = source.left;
    this.mTempTextureMatrix[13] = source.top;
  }

  private drawTextureRectRaw(texture: BasicTexture, textureMatrix: number[], target: RectF): void {
    const program = this.prepareTexture(texture);
    this.setPosition(program, GLES20Canvas.OFFSET_FILL_RECT);
    const texArgs: number[] = [program];
    for (let i = 0; i < 16; i++) {
      texArgs.push(textureMatrix[i]);
    }
    this.mCmd.cmd(GLCommand.UNIFORM_TEXTURE_MATRIX, texArgs);
    if (texture.isFlippedVertically()) {
      this.save(GLCanvas.SAVE_FLAG_MATRIX);
      this.translate(0, target.centerY());
      this.scale(1, -1, 1);
      this.translate(0, -target.centerY());
    }
    this.drawProgram(program, GLConst.GL_TRIANGLE_STRIP, GLES20Canvas.COUNT_FILL_VERTEX,
      target.left, target.top, target.width(), target.height());
    if (texture.isFlippedVertically()) {
      this.restore();
    }
    this.mCountTextureRect++;
  }

  /** 按纹理 target 选 program（普通 2D / OES 外部纹理），并完成绑定与统一变量设置。 */
  private prepareTexture(texture: BasicTexture): number {
    const program = texture.getTarget() === GLConst.GL_TEXTURE_2D
      ? GLES20Canvas.PROGRAM_TEXTURE
      : GLES20Canvas.PROGRAM_OES_TEXTURE;
    this.textureUseProgram(texture, program);
    return program;
  }

  private textureUseProgram(texture: BasicTexture, program: number): void {
    this.mCmd.cmd(GLCommand.USE_PROGRAM, [program]);
    this.enableBlending(!texture.isOpaque() || this.getAlpha() < GLES20Canvas.OPAQUE_ALPHA);
    // onBind 可能触发纹理上传（首次绘制）；必须在 BIND_TEXTURE 之前
    texture.onBind(this);
    this.mCmd.cmd(GLCommand.BIND_TEXTURE, [texture.getTarget(), texture.getId()]);
    this.mCmd.cmd(GLCommand.UNIFORM_SAMPLER, [program, 0]);
    this.mCmd.cmd(GLCommand.UNIFORM_ALPHA, [program, this.getAlpha()]);
  }

  drawMesh(tex: BasicTexture, x: number, y: number, xyBuffer: number, uvBuffer: number,
    indexBuffer: number, indexCount: number): void {
    this.textureUseProgram(tex, GLES20Canvas.PROGRAM_MESH);

    this.mCmd.cmd(GLCommand.BIND_ELEMENT_ARRAY_BUFFER, [indexBuffer]);

    this.mCmd.cmd(GLCommand.BIND_ARRAY_BUFFER, [xyBuffer]);
    this.mCmd.cmd(GLCommand.VERTEX_ATTRIB_POINTER,
      [GLES20Canvas.PROGRAM_MESH, GLES20Canvas.ATTR_POSITION, GLES20Canvas.COORDS_PER_VERTEX, 0]);

    this.mCmd.cmd(GLCommand.BIND_ARRAY_BUFFER, [uvBuffer]);
    this.mCmd.cmd(GLCommand.VERTEX_ATTRIB_POINTER,
      [GLES20Canvas.PROGRAM_MESH, GLES20Canvas.ATTR_TEXTURE_COORD,
        GLES20Canvas.COORDS_PER_VERTEX, 0]);
    this.mCmd.cmd(GLCommand.BIND_ARRAY_BUFFER, [0]);

    this.mCmd.cmd(GLCommand.ENABLE_ATTRIB, [GLES20Canvas.PROGRAM_MESH, GLES20Canvas.ATTR_POSITION]);
    this.mCmd.cmd(GLCommand.ENABLE_ATTRIB,
      [GLES20Canvas.PROGRAM_MESH, GLES20Canvas.ATTR_TEXTURE_COORD]);

    this.setMatrix(GLES20Canvas.PROGRAM_MESH, x, y, 1, 1);
    this.mCmd.cmd(GLCommand.DRAW_ELEMENTS,
      [GLConst.GL_TRIANGLE_STRIP, indexCount, GLConst.GL_UNSIGNED_BYTE, 0]);

    this.mCmd.cmd(GLCommand.DISABLE_ATTRIB, [GLES20Canvas.PROGRAM_MESH, GLES20Canvas.ATTR_POSITION]);
    this.mCmd.cmd(GLCommand.DISABLE_ATTRIB,
      [GLES20Canvas.PROGRAM_MESH, GLES20Canvas.ATTR_TEXTURE_COORD]);
    this.mCmd.cmd(GLCommand.BIND_ELEMENT_ARRAY_BUFFER, [0]);
    this.mCountDrawMesh++;
  }

  drawMixed(from: BasicTexture, toColor: number, ratio: number, a: number | RectF,
    b: number | RectF, c?: number, d?: number): void {
    if (typeof a === 'number') {
      GLES20Canvas.copyTextureCoordinates(from, this.mTempSourceRect);
      this.mTempTargetRect.set(a, b as number, a + (c as number), (b as number) + (d as number));
      this.drawMixed(from, toColor, ratio, this.mTempSourceRect, this.mTempTargetRect);
      return;
    }
    const source = a;
    const target = b as RectF;
    if (target.width() <= 0 || target.height() <= 0) {
      return;
    }
    this.save(GLCanvas.SAVE_FLAG_ALPHA);

    const currentAlpha = this.getAlpha();
    const cappedRatio = Math.min(1, Math.max(0, ratio));

    const textureAlpha = (1 - cappedRatio) * currentAlpha;
    this.setAlpha(textureAlpha);
    this.drawTexture(from, source, target);

    if (0 !== Color.alpha(toColor)) {
      const colorAlpha = cappedRatio * currentAlpha;
      this.setAlpha(colorAlpha);
      this.fillRect(target.left, target.top, target.width(), target.height(), toColor);
    }

    this.restore();
  }

  // ==========================================================================
  // 纹理/缓冲回收
  // ==========================================================================

  unloadTexture(texture: BasicTexture): boolean {
    const unload = texture.isLoaded();
    if (unload) {
      this.mUnboundTextures.push(texture.getId());
    }
    return unload;
  }

  deleteBuffer(bufferId: number): void {
    this.mDeleteBuffers.push(bufferId);
  }

  /**
   * 回收纹理/缓冲 id。
   *
   * **与上游的差异及其代价（此处必须说明）**：上游没有 `isReady()` 这道门
   * （调用方保证 GL context 有效），我们为了防御 native 未就绪加了 gate。
   * 加了 gate 就必须同时处理队列，否则 **context 丢失期间队列只增不减 → 内存无上限增长**
   * （storage-db 全仓 review 发现的静默失败）。
   * 处理方式：context 不可用时，队列里的 id 已随 context 一起失效（重建后
   * `BasicTexture.invalidateAllTextures()` 会重新上传并分配新 id），因此**直接丢弃**并记一次日志。
   */
  deleteRecycledResources(): void {
    const backend = GLNative.backend();
    if (!GLNative.isReady()) {
      const dropped: number = this.mUnboundTextures.length + this.mDeleteBuffers.length;
      if (dropped > 0) {
        hilog.warn(DOMAIN, TAG,
          'deleteRecycledResources: GL backend not ready, dropping %{public}d stale ids (context lost)',
          dropped);
        this.mUnboundTextures = [];
        this.mDeleteBuffers = [];
      }
      return;
    }
    if (this.mUnboundTextures.length > 0) {
      for (let i = 0; i < this.mUnboundTextures.length; i++) {
        backend.deleteTexture(this.mUnboundTextures[i]);
      }
      this.mUnboundTextures = [];
    }
    if (this.mDeleteBuffers.length > 0) {
      for (let i = 0; i < this.mDeleteBuffers.length; i++) {
        backend.deleteBuffer(this.mDeleteBuffers[i]);
      }
      this.mDeleteBuffers = [];
    }
  }

  dumpStatisticsAndClear(): void {
    hilog.debug(DOMAIN, TAG, 'MESH:%{public}d, TEX_RECT:%{public}d, FILL_RECT:%{public}d, LINE:%{public}d',
      this.mCountDrawMesh, this.mCountTextureRect, this.mCountFillRect, this.mCountDrawLine);
    this.mCountDrawMesh = 0;
    this.mCountTextureRect = 0;
    this.mCountFillRect = 0;
    this.mCountDrawLine = 0;
  }

  // ==========================================================================
  // Render target
  // ==========================================================================

  beginRenderTarget(texture: RawTexture): void {
    this.save(); // 保存矩阵、alpha
    const oldTexture = this.getTargetTexture();
    this.mTargetTextures.push(texture);
    this.setRenderTarget(oldTexture, texture);
  }

  endRenderTarget(): void {
    const oldTexture = this.mTargetTextures.pop() as RawTexture;
    const texture = this.getTargetTexture();
    this.setRenderTarget(oldTexture, texture);
    this.restore();
  }

  private getTargetTexture(): RawTexture | null {
    return this.mTargetTextures[this.mTargetTextures.length - 1];
  }

  private setRenderTarget(oldTexture: RawTexture | null, texture: RawTexture | null): void {
    const backend = GLNative.backend();
    if (oldTexture === null && texture !== null) {
      this.mFrameBuffer = backend.genFramebuffer();
      if (this.mFrameBuffer < 0) {
        throw new Error('glGenFramebuffers failed');
      }
      this.mCmd.cmd(GLCommand.BIND_FRAMEBUFFER, [this.mFrameBuffer]);
    } else if (oldTexture !== null && texture === null) {
      this.mCmd.cmd(GLCommand.BIND_FRAMEBUFFER, [0]);
      backend.unbindFramebuffer();
    }

    if (texture === null) {
      this.setSize(this.mScreenWidth, this.mScreenHeight);
    } else {
      this.setSize(texture.getWidth(), texture.getHeight());
      if (!texture.isLoaded()) {
        texture.prepare(this);
      }
      this.mCmd.cmd(GLCommand.ATTACH_TEXTURE,
        [GLConst.GL_FRAMEBUFFER, GLConst.GL_COLOR_ATTACHMENT0, texture.getTarget(),
          texture.getId()]);
    }
  }

  // ==========================================================================
  // 纹理参数与上传
  // ==========================================================================

  setTextureParameters(texture: BasicTexture): void {
    const target = texture.getTarget();
    this.mCmd.cmd(GLCommand.BIND_TEXTURE, [target, texture.getId()]);
    this.mCmd.cmd(GLCommand.TEX_PARAMETER, [target, GLConst.GL_TEXTURE_WRAP_S,
      GLConst.GL_CLAMP_TO_EDGE]);
    this.mCmd.cmd(GLCommand.TEX_PARAMETER, [target, GLConst.GL_TEXTURE_WRAP_T,
      GLConst.GL_CLAMP_TO_EDGE]);
    this.mCmd.cmd(GLCommand.TEX_PARAMETER, [target, GLConst.GL_TEXTURE_MIN_FILTER,
      GLConst.GL_LINEAR]);
    this.mCmd.cmd(GLCommand.TEX_PARAMETER, [target, GLConst.GL_TEXTURE_MAG_FILTER,
      GLConst.GL_LINEAR]);
  }

  initializeTextureSize(texture: BasicTexture, format: number, type: number): void {
    const target = texture.getTarget();
    this.mCmd.cmd(GLCommand.BIND_TEXTURE, [target, texture.getId()]);
    this.mCmd.cmd(GLCommand.TEX_IMAGE_2D, [target, format, texture.getTextureWidth(),
      texture.getTextureHeight(), format, type]);
  }

  initializeTexture(texture: BasicTexture, pixelMap: image.PixelMap): void {
    const target = texture.getTarget();
    this.mCmd.cmd(GLCommand.BIND_TEXTURE, [target, texture.getId()]);
    this.flushPending();
    // 位图上传必须走 native（像素在 native 侧），不能进命令流
    const size: Size2D | null = PixelMapUtils.readSize(pixelMap);
    if (size === null) {
      hilog.error(DOMAIN, TAG, 'initializeTexture: PixelMap unreadable (released?), skip upload');
      return;
    }
    GLNative.backend().texImage2D(texture.getId(), size.width, size.height,
      GLConst.GL_RGBA, GLConst.GL_UNSIGNED_BYTE, pixelMap);
  }

  texSubImage2D(texture: BasicTexture, xOffset: number, yOffset: number,
    pixelMap: image.PixelMap, format: number, type: number): void {
    const target = texture.getTarget();
    this.mCmd.cmd(GLCommand.BIND_TEXTURE, [target, texture.getId()]);
    this.flushPending();
    const size: Size2D | null = PixelMapUtils.readSize(pixelMap);
    if (size === null) {
      hilog.error(DOMAIN, TAG, 'texSubImage2D: PixelMap unreadable (released?), skip upload');
      return;
    }
    GLNative.backend().texSubImage2D(texture.getId(), xOffset, yOffset, size.width,
      size.height, format, type, pixelMap);
  }

  /**
   * 立即绑定纹理并冲刷已录制命令（`NativeTexture.texImage` 的像素上传依赖它）。
   * 见 `GLCanvas.bindTextureForUpload` 注释里的顺序陷阱说明。
   */
  bindTextureForUpload(texture: BasicTexture): void {
    this.mCurrentBoundTextureId = texture.getId();
    this.mCmd.cmd(GLCommand.BIND_TEXTURE, [texture.getTarget(), texture.getId()]);
    this.flushPending();
  }

  /**
   * 当前已绑定纹理的 id（供 `GLTexImageBridge` 使用）。
   *
   * 存在原因：上游 `nativeTexImage(bitmap, init, x, y, w, h)` 不传纹理 id ——
   * 它依赖"当前已绑定的纹理"。`Image.texImage` 的桥签名同样不带 id，
   * 所以必须由画布记录最近一次 `bindTextureForUpload` 的目标。
   * 只在 `bindTextureForUpload` 里更新（其它绑定走命令流、不参与立即上传）。
   */
  getBoundTextureId(): number {
    return this.mCurrentBoundTextureId;
  }

  /** 用常量颜色填充纹理矩形区（见 `GLNativeBackend.texSubImage2DFill` 注释）。 */
  texSubImage2DFill(texture: BasicTexture, xOffset: number, yOffset: number, width: number,
    height: number, format: number, type: number, rgba: number): void {
    const target = texture.getTarget();
    this.mCmd.cmd(GLCommand.BIND_TEXTURE, [target, texture.getId()]);
    this.flushPending();
    GLNative.backend().texSubImage2DFill(texture.getId(), xOffset, yOffset, width, height,
      format, type, rgba);
  }

  uploadBufferFloat(data: Float32Array): number {
    const backend = GLNative.backend();
    const id = backend.genBuffer(GLConst.GL_ARRAY_BUFFER);
    if (id < 0) {
      return -1;
    }
    if (backend.bufferDataF32(id, data) !== GLErr.OK) {
      return -1;
    }
    return id;
  }

  uploadBufferByte(data: Uint8Array): number {
    const backend = GLNative.backend();
    const id = backend.genBuffer(GLConst.GL_ELEMENT_ARRAY_BUFFER);
    if (id < 0) {
      return -1;
    }
    if (backend.bufferDataU8(id, data) !== GLErr.OK) {
      return -1;
    }
    return id;
  }

  // ==========================================================================
  // 其它
  // ==========================================================================

  /**
   * 上游每次 GL 调用后都 `glGetError()`。批处理实现下逐命令查错会让 NAPI 往返翻倍，
   * 因此改为：命令流在 native 侧执行完统一查一次（`replay` 返回 GLErr.GL_ERROR）。
   * 需要逐命令定位时把 `DETAILED_ERROR_CHECK` 打开（仅调试用）。
   */
  checkError(): void {
    if (!GLES20Canvas.DETAILED_ERROR_CHECK) {
      return;
    }
    const err = GLNative.backend().getErrorCode();
    if (err !== GLConst.GL_NO_ERROR) {
      hilog.error(DOMAIN, TAG, 'GL error: %{public}d', err);
    }
  }

  private static readonly DETAILED_ERROR_CHECK: boolean = false;

  recoverFromLightCycle(): void {
    this.mCmd.cmd(GLCommand.SET_VIEWPORT, [this.mWidth, this.mHeight]);
    this.mCmd.cmd(GLCommand.BLEND_FUNC, [GLConst.GL_ONE, GLConst.GL_ONE_MINUS_SRC_ALPHA]);
  }

  getBounds(bounds: Rect, x: number, y: number, width: number, height: number): void {
    Matrix.translateMFrom(this.mTempMatrix, 0, this.mMatrices, this.mCurrentMatrixIndex, x, y, 0);
    Matrix.scaleM(this.mTempMatrix, 0, width, height, 1);
    Matrix.multiplyMV(this.mTempMatrix, GLES20Canvas.MATRIX_SIZE, this.mTempMatrix, 0,
      GLES20Canvas.BOUNDS_COORDINATES, 0);
    Matrix.multiplyMV(this.mTempMatrix, GLES20Canvas.MATRIX_SIZE + 4, this.mTempMatrix, 0,
      GLES20Canvas.BOUNDS_COORDINATES, 4);
    bounds.left = Math.round(this.mTempMatrix[GLES20Canvas.MATRIX_SIZE]);
    bounds.right = Math.round(this.mTempMatrix[GLES20Canvas.MATRIX_SIZE + 4]);
    bounds.top = Math.round(this.mTempMatrix[GLES20Canvas.MATRIX_SIZE + 1]);
    bounds.bottom = Math.round(this.mTempMatrix[GLES20Canvas.MATRIX_SIZE + 5]);
    bounds.sort();
  }
}
