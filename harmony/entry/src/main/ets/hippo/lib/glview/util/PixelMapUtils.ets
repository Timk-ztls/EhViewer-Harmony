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

/**
 * PixelMap 尺寸读取的容错封装。
 *
 * 为什么单拎出来：`pixelMap.getImageInfoSync()` 在 ArkTS 里被标注为"可能抛异常"
 * （ArkTS 编译器会给出 `Function may throw exceptions. Special handling is required`
 * 警告，见 hvigor 对 UploadedTexture.ets:84 / GLES20Canvas.ets:933 的 4 条 WARN）。
 * 真实触发场景不是理论问题：PixelMap 已被 `release()`（别处提前回收）时这里会抛
 * `BusinessError`，而这段代码跑在渲染循环里 —— 不兜住就是整帧崩、死循环重试。
 *
 * 语义选择：读不到尺寸返回 `null`，由调用方决定"跳过本次上传"还是"标记纹理错误"，
 * 不在这里吞掉错误（否则问题会被藏到像素层面的黑图）。
 */
export class PixelMapUtils {
  /** 读 PixelMap 的逻辑宽高；失败（已释放/非法句柄）返回 null。 */
  static readSize(pixelMap: image.PixelMap): Size2D | null {
    try {
      const info = pixelMap.getImageInfoSync();
      return new Size2D(info.size.width, info.size.height);
    } catch (err) {
      // 失败原因（已释放/非法句柄）由调用方决定是否打日志；这里只把结果变成可判定的返回值
      return null;
    }
  }

  /** 读 stride（像素行字节数）；取不到时返回 0，让 native 侧自己按 width*4 兜底。 */
  static readStride(pixelMap: image.PixelMap): number {
    try {
      const info = pixelMap.getImageInfoSync();
      const stride = info.stride;
      return typeof stride === 'number' ? stride : 0;
    } catch (err) {
      return 0;
    }
  }
}

/** 尺寸值对象（避免跨文件传 image.Size 接口带来的结构类型问题）。 */
export class Size2D {
  width: number;
  height: number;

  constructor(width: number, height: number) {
    this.width = width;
    this.height = height;
  }
}
