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

import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TexImageBridge, Image } from '../../image/Image';
import { GLES20Canvas } from '../glrenderer/GLES20Canvas';
import { GLConst } from './GLConst';
import { GLNative, TexRegionUploader, GLErr } from './GLNativeBridge';

const TAG = 'GLTexImageBridge';
const DOMAIN = 0x0000;

/**
 * `Image.TexImageBridge` 的实现（**本项目新增**）：把 `Image.texImage` 的像素推给当前绑定的纹理。
 *
 * ## 为什么需要它
 * `ImageTexture.Tile.texImage` → `ImageWrapper.texImage` → `Image.texImage` → **本桥**。
 * 未注入时 `Image.texImage` 直接抛 `TODO(native-image/gl-render): TexImageBridge 未注入`。
 * 也就是说：`ImageTexture`(1244) 编译通过、断言通过，但**运行时不出像素**。
 *
 * ## 签名不带纹理 id 的原因
 * 上游 `nativeTexImage(Bitmap, init, offsetX, offsetY, w, h)` 也不带 id —— 它作用于
 * **当前已绑定**的纹理。这里沿用同一约定：由 `GLES20Canvas.getBoundTextureId()` 提供，
 * 并且必须在 `bindTextureForUpload(texture)` 之后立即调用（`NativeTexture` 已经这么做了）。
 *
 * ## ⚠️ 已知限制（阻塞项，已上报）
 * tile 的边框会上传成**负偏移**（`offsetX - borderSize`，首行首列为 -1/-2），因为
 * 上游 JNI 支持"把图片的一个区域渲染到纹理的任意偏移处"（负偏移时自动裁剪）。
 * 当前 NAPI 面只有 `nativeTexImage2D` / `nativeTexSubImage2D`，**没有区域 blit**，
 * 而 `glTexSubImage2D` 的 xoffset/yoffset 不允许为负。
 *
 * 需要的原生能力（已提交给 native-image）：
 * ```
 * nativeTexImageRegion(id, init, pixelMap, srcX, srcY, srcW, srcH, dstX, dstY, texW, texH)
 *   init=true  → glTexImage2D(texW, texH) 分配 + 区域 blit
 *   init=false → glTexSubImage2D 区域 blit（越界部分裁剪）
 * ```
 * **修正（初版判断错了一次）**：起初以为"非负偏移可以走普通上传"，实际上 tile 需要的是
 * **图片的某个区域**贴到纹理的某个偏移 —— 例如 offset=(254,0) 的 tile 要把图片 [254,510)
 * 这一条贴到纹理 [0,256)，而 `texSubImage2D(id,254,0,...)` 传的是**整张图**。
 * 所以**除了"整图刚好铺满一块 tile（offset=0 且尺寸一致）"这一个退化情形**，
 * 分块上传都依赖 `nativeTexImageRegion`。
 *
 * **`nativeTexImageRegion` 已合入 main**（native-image MR !59，26 条 C 断言真跑），
 * 因此本桥现在只有一条路径：区域 blit。原先"负偏移抛具名错误"的兜底已撤除。
 *
 * 传参（Lead 提醒过的一致性点）：
 * - 纹理 id **显式传参**（native 签名带 id），不再依赖"当前绑定纹理"；
 *   `mCurrentBoundTextureId` 仅作为 `bindTextureForUpload` 的副作用保留给其它路径。
 * - `texW/texH` 传的是**有效写入范围**：`init=true` 时等于 tile 纹理尺寸（256/512，用于分配），
 *   `init=false` 时等于内容+边框（≤ 纹理尺寸，用于裁剪）。
 * - `srcW/srcH` 已含边框（`内容 + 2*border`），与上游 `Image.texImage` 的实参一致。
 */
export class GLTexImageBridge implements TexImageBridge {
  private static sInstance: GLTexImageBridge | null = null;

  private mCanvas: GLES20Canvas | null = null;

  /** 绑定画布（`GLRootViewController` 创建画布后调用）。 */
  setCanvas(canvas: GLES20Canvas | null): void {
    this.mCanvas = canvas;
  }

  texImage(pixelMap: image.PixelMap, init: boolean, offsetX: number, offsetY: number,
    width: number, height: number): void {
    const canvas = this.mCanvas;
    if (canvas === null) {
      throw new Error('GLTexImageBridge: canvas not set (call setCanvas() first)');
    }
    const id = canvas.getBoundTextureId();
    if (id <= 0) {
      throw new Error('GLTexImageBridge: no bound texture (call bindTextureForUpload() first)');
    }
    if (!GLNative.isReady()) {
      throw new Error('GLTexImageBridge: native backend not registered');
    }

    // 唯一路径：区域 blit（`nativeTexImageRegion`，已合入 main）。
    // 传参语义：src = 图片上的区域起点与尺寸（可为负，native 侧裁剪并对 src 同量正向平移）；
    //           dst = 纹理内目标偏移（tile 总是贴到 (0,0)）；
    //           texW/texH = 纹理的有效写入范围（init 时同时用作 glTexImage2D 的分配尺寸）。
    const uploader: TexRegionUploader | null = GLNative.regionUploader();
    if (uploader === null) {
      // 理论上注册后不会走到这里；保留是为了"未合并 MR 的构建"能给出清晰错误
      throw new Error('GLTexImageBridge: TexRegionUploader not registered '
        + '(GLNativeBackendImpl.registerGLBackend() must run first)');
    }
    const err = uploader.texImageRegion(id, init, pixelMap, offsetX, offsetY, width, height,
      0, 0, width, height);
    if (err !== GLErr.OK) {
      hilog.error(DOMAIN, TAG, 'texImageRegion failed: %{public}d (offset %{public}d,%{public}d '
        + '%{public}dx%{public}d init=%{public}s)', err as number, offsetX, offsetY, width, height,
        init ? 'true' : 'false');
    }
  }
  /** 单例（`Image.setTexImageBridge` 只接受一个桥实例）。 */
  static getInstance(): GLTexImageBridge {
    let instance = GLTexImageBridge.sInstance;
    if (instance === null) {
      instance = new GLTexImageBridge();
      GLTexImageBridge.sInstance = instance;
    }
    return instance;
  }

  /** 注入到 `Image`（幂等）。 */
  static install(): GLTexImageBridge {
    const bridge = GLTexImageBridge.getInstance();
    Image.setTexImageBridge(bridge);
    return bridge;
  }
}
