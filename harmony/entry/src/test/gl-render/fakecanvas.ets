/*
 * 假画布：实现 GLCanvas 全部抽象成员，记录关键调用顺序。
 *
 * 为什么不直接 new GLES20Canvas()：真实画布要 native backend 就绪，
 * 纯逻辑单测（C-10）跑在 node 上，没有 GL。这里只做"记录 + 断言"，不产生任何渲染副作用。
 */

import { GLCanvas } from '../../main/ets/hippo/lib/glview/glrenderer/GLCanvas';
import { GLId } from '../../main/ets/hippo/lib/glview/glrenderer/GLId';
import { GLPaint } from '../../main/ets/hippo/lib/glview/glrenderer/GLPaint';
import { BasicTexture } from '../../main/ets/hippo/lib/glview/glrenderer/BasicTexture';
import { RawTexture } from '../../main/ets/hippo/lib/glview/glrenderer/RawTexture';
import { Rect } from '../../main/ets/hippo/lib/glview/util/Rect';
import { RectF } from '../../main/ets/hippo/lib/glview/util/RectF';

export class FakeCanvas extends GLCanvas {
  log: string[] = [];
  savedFlags: number[] = [];
  alpha: number = 1;

  getGLId(): GLId {
    throw new Error('FakeCanvas.getGLId 不应被调用');
  }

  setSize(width: number, height: number): void { this.log.push(`setSize:${width},${height}`); }

  clearBuffer(): void { this.log.push('clearBuffer'); }

  clearBufferArgb(argb: number[]): void { this.log.push('clearBufferArgb'); }

  setAlpha(alpha: number): void { this.alpha = alpha; this.log.push(`setAlpha:${alpha}`); }

  getAlpha(): number { return this.alpha; }

  multiplyAlpha(alpha: number): void { this.alpha *= alpha; this.log.push(`multiplyAlpha:${alpha}`); }

  translate(x: number, y: number, z?: number): void { this.log.push(`translate:${x},${y},${z}`); }

  scale(sx: number, sy: number, sz: number): void { this.log.push(`scale:${sx},${sy},${sz}`); }

  rotate(angle: number, x: number, y: number, z: number): void { this.log.push(`rotate:${angle}`); }

  multiplyMatrix(mMatrix: number[], offset: number): void { this.log.push('multiplyMatrix'); }

  save(saveFlags?: number): void {
    const f: number = saveFlags === undefined ? GLCanvas.SAVE_FLAG_ALL : saveFlags;
    this.savedFlags.push(f);
    this.log.push(`save:${f}`);
  }

  restore(): void { this.log.push('restore'); }

  drawLine(x1: number, y1: number, x2: number, y2: number, paint: GLPaint): void { this.log.push('drawLine'); }

  drawRect(x: number, y: number, width: number, height: number, paint: GLPaint): void { this.log.push('drawRect'); }

  drawOval(cx: number, cy: number, radiusX: number, radiusY: number, paint: GLPaint): void { this.log.push('drawOval'); }

  drawArc(cx: number, cy: number, radiusX: number, radiusY: number, sweepAngle: number,
    paint: GLPaint): void { this.log.push('drawArc'); }

  fillRect(x: number, y: number, width: number, height: number, color: number): void {
    this.log.push(`fillRect:${color}`);
  }

  fillOval(cx: number, cy: number, radiusX: number, radiusY: number, color: number): void { this.log.push('fillOval'); }

  fillSector(cx: number, cy: number, radiusX: number, radiusY: number, sweepAngle: number,
    color: number): void { this.log.push('fillSector'); }

  drawTexture(texture: BasicTexture, a: number | RectF | number[], b?: number | RectF,
    c?: number, d?: number, e?: number, f?: number): void { this.log.push('drawTexture'); }

  drawMesh(tex: BasicTexture, x: number, y: number, xyBuffer: number, uvBuffer: number,
    indexBuffer: number, indexCount: number): void { this.log.push('drawMesh'); }

  drawMixed(from: BasicTexture, toColor: number, ratio: number, a: number | RectF,
    b: number | RectF, c?: number, d?: number): void { this.log.push('drawMixed'); }

  unloadTexture(texture: BasicTexture): boolean { return false; }

  deleteBuffer(bufferId: number): void { }

  deleteRecycledResources(): void { }

  dumpStatisticsAndClear(): void { }

  beginRenderTarget(texture: RawTexture): void { }

  endRenderTarget(): void { }

  setTextureParameters(texture: BasicTexture): void { }

  initializeTextureSize(texture: BasicTexture, format: number, type: number): void { }

  initializeTexture(texture: BasicTexture, pixelMap: Object): void { this.log.push('initializeTexture'); }

  texSubImage2D(texture: BasicTexture, xOffset: number, yOffset: number, pixelMap: Object,
    format: number, type: number): void { }

  texSubImage2DFill(texture: BasicTexture, xOffset: number, yOffset: number, width: number,
    height: number, format: number, type: number, rgba: number): void { }

  uploadBufferFloat(data: Float32Array): number { return 0; }

  uploadBufferByte(data: Uint8Array): number { return 0; }

  recoverFromLightCycle(): void { }

  getBounds(bounds: Rect, x: number, y: number, width: number, height: number): void { }
}

/** 带 GL id 的假画布：`UploadedTexture.onBind` 会向画布要 GL id。 */
export class FakeGLId extends GLId {
  next: number = 1;

  generateTexture(): number { return this.next++; }

  glGenBuffers(n: number, buffers: number[], offset: number): void { }

  glDeleteTextures(n: number, textures: number[], offset: number): void { }

  glDeleteBuffers(n: number, buffers: number[], offset: number): void { }

  glDeleteFramebuffers(n: number, buffers: number[], offset: number): void { }
}

/** 在 FakeCanvas 之上补 `getGLId()` 与 `setTextureParameters()`。 */
export class ExtCanvas extends FakeCanvas {
  glId: GLId = new FakeGLId();
  paramsSet: number = 0;

  getGLId(): GLId {
    return this.glId;
  }

  setTextureParameters(texture: BasicTexture): void {
    this.paramsSet++;
  }
}