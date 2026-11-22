/*
 * D-020：`Image1.LibImageBridge` 的 ArkTS 侧适配层，连接 `libnative-lib.so` 解码句柄与 `GLTexImageBridge`。
 * 通过 `NativeImageBackend` 依赖注入与系统 NAPI 解耦，便于宿主 Node 单测全覆盖 16 个桥方法。
 */

import fs from '@ohos.file.fs';
import image from '@ohos.multimedia.image';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LibImageBridge } from './Image1';
import { GLTexImageBridge } from '../glview/native/GLTexImageBridge';

const DOMAIN: number = 0x0000;
const TAG: string = 'NativeLibImageBridge';

export interface NativeImageHandleLike {
  readonly format: number;
  readonly width: number;
  readonly height: number;
  readonly byteCount: number;
  readonly delay: number;
  readonly frameCount: number;

  getPixels(): ArrayBuffer;
  complete(): boolean;
  isCompleted(): boolean;
  render(dst: ArrayBuffer | Uint8Array, dstW: number, dstH: number,
    srcX: number, srcY: number, dstX: number, dstY: number,
    width: number, height: number, fillBlank: boolean, defaultColor: number): void;
  advance(): void;
  isOpaque(): boolean;
  isGray(error: number): boolean;
  clahe(toGray: boolean): void;
  recycle(): void;
}

export interface NativeImageBackend {
  decode(buffer: ArrayBuffer | Uint8Array, partially: boolean): NativeImageHandleLike;
  createPlain(width: number, height: number, pixels: ArrayBuffer | Uint8Array): NativeImageHandleLike;
  getSupportedFormats(): number[];
  getDecoderDescription(format: number): string;
}

export interface TextureUploadSink {
  uploadTexture(pixelMap: image.PixelMap, init: boolean, offsetX: number, offsetY: number,
    width: number, height: number): void;
}

class DefaultGLTexUploadSink implements TextureUploadSink {
  uploadTexture(pixelMap: image.PixelMap, init: boolean, offsetX: number, offsetY: number,
    width: number, height: number): void {
    GLTexImageBridge.getInstance().texImage(pixelMap, init, offsetX, offsetY, width, height);
  }
}

export class NativeLibImageBridge implements LibImageBridge {
  private readonly backend: NativeImageBackend;
  private readonly texSink: TextureUploadSink;
  private readonly handles: Map<bigint, NativeImageHandleLike> = new Map<bigint, NativeImageHandleLike>();
  private nextHandle: bigint = BigInt(1);

  constructor(backend: NativeImageBackend, texSink?: TextureUploadSink) {
    this.backend = backend;
    this.texSink = texSink === undefined ? new DefaultGLTexUploadSink() : texSink;
  }

  private allocHandle(img: NativeImageHandleLike): bigint {
    const id: bigint = this.nextHandle;
    this.nextHandle = this.nextHandle + BigInt(1);
    this.handles.set(id, img);
    return id;
  }

  private getHandle(nativePtr: bigint): NativeImageHandleLike | null {
    const item: NativeImageHandleLike | undefined = this.handles.get(nativePtr);
    return item === undefined ? null : item;
  }

  activeHandleCount(): number {
    return this.handles.size;
  }

  decode(fileDescriptor: number, partially: boolean): bigint {
    if (fileDescriptor < 0) {
      return BigInt(0);
    }
    try {
      const st: fs.Stat = fs.statSync(fileDescriptor);
      if (st.size <= 0) {
        return BigInt(0);
      }
      fs.lseek(fileDescriptor, 0, fs.WhenceType.SEEK_SET);
      const buf: ArrayBuffer = new ArrayBuffer(st.size);
      const view: Uint8Array = new Uint8Array(buf);
      let totalRead: number = 0;
      const chunk: ArrayBuffer = new ArrayBuffer(Math.min(65536, st.size));
      while (totalRead < st.size) {
        const want: number = Math.min(chunk.byteLength, st.size - totalRead);
        const n: number = fs.readSync(fileDescriptor, chunk, { length: want });
        if (n <= 0) {
          break;
        }
        view.set(new Uint8Array(chunk, 0, n), totalRead);
        totalRead += n;
      }
      if (totalRead <= 0) {
        return BigInt(0);
      }
      const slice: Uint8Array = totalRead === st.size ? view : view.subarray(0, totalRead);
      const nativeImg: NativeImageHandleLike = this.backend.decode(slice, partially);
      return this.allocHandle(nativeImg);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'decode fd=%{public}d failed: %{public}s',
        fileDescriptor, (e as Error).message);
      return BigInt(0);
    }
  }

  create(pixelMap: image.PixelMap | null): bigint {
    if (pixelMap === null) {
      return BigInt(0);
    }
    try {
      const info: image.ImageInfo = pixelMap.getImageInfoSync();
      const w: number = info.size.width;
      const h: number = info.size.height;
      if (w <= 0 || h <= 0) {
        return BigInt(0);
      }
      const pixels: ArrayBuffer = new ArrayBuffer(w * h * 4);
      pixelMap.readPixelsToBufferSync(pixels);
      const nativeImg: NativeImageHandleLike = this.backend.createPlain(w, h, pixels);
      return this.allocHandle(nativeImg);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'create from PixelMap failed: %{public}s', (e as Error).message);
      return BigInt(0);
    }
  }

  getByteCount(nativePtr: bigint, _format: number): number {
    const img: NativeImageHandleLike | null = this.getHandle(nativePtr);
    return img !== null ? img.byteCount : 0;
  }

  complete(nativePtr: bigint, _format: number): boolean {
    const img: NativeImageHandleLike | null = this.getHandle(nativePtr);
    return img !== null ? img.complete() : false;
  }

  isCompleted(nativePtr: bigint, _format: number): boolean {
    const img: NativeImageHandleLike | null = this.getHandle(nativePtr);
    return img !== null ? img.isCompleted() : false;
  }

  render(nativePtr: bigint, _format: number, srcX: number, srcY: number,
    dst: image.PixelMap | null, dstX: number, dstY: number,
    width: number, height: number, fillBlank: boolean, defaultColor: number): void {
    const img: NativeImageHandleLike | null = this.getHandle(nativePtr);
    if (img === null || dst === null || width <= 0 || height <= 0) {
      return;
    }
    const info: image.ImageInfo = dst.getImageInfoSync();
    const dstW: number = info.size.width;
    const dstH: number = info.size.height;
    if (dstW <= 0 || dstH <= 0) {
      return;
    }
    const buffer: ArrayBuffer = new ArrayBuffer(dstW * dstH * 4);
    img.render(buffer, dstW, dstH, srcX, srcY, dstX, dstY, width, height, fillBlank, defaultColor);
    dst.writeBufferToPixelsSync(buffer);
  }

  texImage(nativePtr: bigint, _format: number, init: boolean,
    offsetX: number, offsetY: number, width: number, height: number): void {
    const img: NativeImageHandleLike | null = this.getHandle(nativePtr);
    if (img === null) {
      return;
    }
    if (!img.isCompleted()) {
      img.complete();
    }
    const imgW: number = img.width;
    const imgH: number = img.height;
    if (imgW <= 0 || imgH <= 0) {
      return;
    }
    const pixels: ArrayBuffer = img.getPixels();
    const pm: image.PixelMap = image.createPixelMapSync(pixels, {
      size: { width: imgW, height: imgH },
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      alphaType: image.AlphaType.PREMUL,
      editable: false
    });
    try {
      this.texSink.uploadTexture(pm, init, offsetX, offsetY, width, height);
    } finally {
      pm.release().catch((e: Object): void => {
        hilog.warn(DOMAIN, TAG, 'texImage PixelMap release failed: %{public}s',
          e instanceof Error ? e.message : String(e));
      });
    }
  }

  advance(nativePtr: bigint, _format: number): void {
    const img: NativeImageHandleLike | null = this.getHandle(nativePtr);
    if (img !== null) {
      img.advance();
    }
  }

  getDelay(nativePtr: bigint, _format: number): number {
    const img: NativeImageHandleLike | null = this.getHandle(nativePtr);
    return img !== null ? img.delay : 0;
  }

  frameCount(nativePtr: bigint, _format: number): number {
    const img: NativeImageHandleLike | null = this.getHandle(nativePtr);
    return img !== null ? img.frameCount : 0;
  }

  isOpaque(nativePtr: bigint, _format: number): boolean {
    const img: NativeImageHandleLike | null = this.getHandle(nativePtr);
    return img !== null ? img.isOpaque() : false;
  }

  isGray(nativePtr: bigint, _format: number, error: number): boolean {
    const img: NativeImageHandleLike | null = this.getHandle(nativePtr);
    return img !== null ? img.isGray(error) : false;
  }

  clahe(nativePtr: bigint, _format: number, toGray: boolean): void {
    const img: NativeImageHandleLike | null = this.getHandle(nativePtr);
    if (img !== null) {
      img.clahe(toGray);
    }
  }

  recycle(nativePtr: bigint, _format: number): void {
    const img: NativeImageHandleLike | null = this.getHandle(nativePtr);
    if (img !== null) {
      this.handles.delete(nativePtr);
      img.recycle();
    }
  }

  supportedImageFormats(): number[] {
    return this.backend.getSupportedFormats();
  }

  decoderDescription(format: number): string | null {
    const desc: string = this.backend.getDecoderDescription(format);
    return desc.length > 0 ? desc : null;
  }
}
