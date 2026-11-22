/**
 * native_image 的 ArkTS 薄封装。
 *
 * 目的：
 *  1) 把 C 侧「按格式常量解码」收敛成上游语义的四个入口
 *     decodePng / decodeJpeg / decodeWebp / decodeGif（对应上游 ImageDecoder 的按格式分支）；
 *  2) 统一 magic number 预检，避免把非目标格式的字节送进错误的解码器（上游
 *     ImageDecoder 也是先嗅探再分派）；
 *  3) 把 NAPI 抛出的原始 Error 规整成带 code 的 NativeImageError。
 *
 * 本文件不含任何解码逻辑，全部转发到 libnative-lib.so。
 */

import nativeImage from 'libnative-lib.so';
import type { NativeImage, GifDecoder } from 'libnative-lib.so';
import { A7ZipBridge, PropId, PropType } from '../hippo/ehviewer/gallery/A7ZipArchive';
import {
  ArchiveFormat,
  RAR_UNSUPPORTED_ERROR_MARKER,
  sniffRandomAccessFormat
} from '../hippo/ehviewer/gallery/ArchiveFormatSniffer';
import { UniRandomAccessFile } from '../hippo/unifile/UniRandomAccessFile';
import { OutputStream } from '../hippo/unifile/Contracts';
import { LibImageBridge } from '../hippo/lib/image/Image1';
import { NativeImageBackend, NativeImageHandleLike, NativeLibImageBridge } from '../hippo/lib/image/NativeLibImageBridge';

export { nativeImage };
export type { NativeImage, GifDecoder };

export const FORMAT_UNKNOWN: number = -1;
export const FORMAT_PLAIN: number = 0;
export const FORMAT_JPEG: number = 1;
export const FORMAT_PNG: number = 2;
export const FORMAT_GIF: number = 3;
export const FORMAT_WEBP: number = 4;

/** 与上游 ImageDecoder 对齐的错误分类 */
export enum NativeImageErrorCode {
  BAD_ARGUMENT = 1,
  UNSUPPORTED_FORMAT = 2,
  DECODE_FAILED = 3,
  OUT_OF_MEMORY = 4,
  SEVEN_ZIP_NOT_BUILT = 7001,
  SEVEN_ZIP_BAD_ARG = 7002,
  SEVEN_ZIP_EXTRACT_FAILED = 7003,
  SEVEN_ZIP_PASSWORD = 7004
}

export class NativeImageError extends Error {
  code: NativeImageErrorCode;

  constructor(code: NativeImageErrorCode, message: string) {
    super(message);
    this.code = code;
    this.name = 'NativeImageError';
  }
}

function bytesOf(data: ArrayBuffer | Uint8Array): Uint8Array {
  if (data instanceof Uint8Array) {
    return data;
  }
  return new Uint8Array(data);
}

function startsWith(data: Uint8Array, magic: number[]): boolean {
  if (data.length < magic.length) {
    return false;
  }
  for (let i = 0; i < magic.length; i++) {
    if (data[i] !== magic[i]) {
      return false;
    }
  }
  return true;
}

const PNG_MAGIC: number[] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
const JPEG_MAGIC: number[] = [0xFF, 0xD8];
const GIF87_MAGIC: number[] = [0x47, 0x49, 0x46, 0x38, 0x37, 0x61];
const GIF89_MAGIC: number[] = [0x47, 0x49, 0x46, 0x38, 0x39, 0x61];
const WEBP_RIFF_MAGIC: number[] = [0x52, 0x49, 0x46, 0x46]; // "RIFF"
const WEBP_TAG_MAGIC: number[] = [0x57, 0x45, 0x42, 0x50];  // "WEBP" @ offset 8

function decodeWithFormat(data: ArrayBuffer | Uint8Array, format: number, partially: boolean): NativeImage {
  const bytes = bytesOf(data);
  if (bytes.length === 0) {
    throw new NativeImageError(NativeImageErrorCode.BAD_ARGUMENT, 'empty image buffer');
  }
  try {
    return nativeImage.decodeAs(bytes, format, partially);
  } catch (e) {
    throw new NativeImageError(NativeImageErrorCode.DECODE_FAILED, `${e}`);
  }
}

/** 解码 PNG；不是 PNG 时抛 UNSUPPORTED_FORMAT */
export function decodePng(data: ArrayBuffer | Uint8Array, partially: boolean = false): NativeImage {
  if (!startsWith(bytesOf(data), PNG_MAGIC)) {
    throw new NativeImageError(NativeImageErrorCode.UNSUPPORTED_FORMAT, 'not a PNG stream');
  }
  return decodeWithFormat(data, FORMAT_PNG, partially);
}

/** 解码 JPEG；不是 JPEG 时抛 UNSUPPORTED_FORMAT */
export function decodeJpeg(data: ArrayBuffer | Uint8Array, partially: boolean = false): NativeImage {
  if (!startsWith(bytesOf(data), JPEG_MAGIC)) {
    throw new NativeImageError(NativeImageErrorCode.UNSUPPORTED_FORMAT, 'not a JPEG stream');
  }
  return decodeWithFormat(data, FORMAT_JPEG, partially);
}

/** 解码 WebP；不是 WebP 时抛 UNSUPPORTED_FORMAT */
export function decodeWebp(data: ArrayBuffer | Uint8Array, partially: boolean = false): NativeImage {
  const bytes = bytesOf(data);
  if (!startsWith(bytes, WEBP_RIFF_MAGIC) || bytes.length < 12 ||
      bytes[8] !== WEBP_TAG_MAGIC[0] || bytes[9] !== WEBP_TAG_MAGIC[1] ||
      bytes[10] !== WEBP_TAG_MAGIC[2] || bytes[11] !== WEBP_TAG_MAGIC[3]) {
    throw new NativeImageError(NativeImageErrorCode.UNSUPPORTED_FORMAT, 'not a WebP stream');
  }
  return decodeWithFormat(data, FORMAT_WEBP, partially);
}

/** 解码 GIF（含动图首帧）；不是 GIF 时抛 UNSUPPORTED_FORMAT */
export function decodeGif(data: ArrayBuffer | Uint8Array, partially: boolean = false): NativeImage {
  const bytes = bytesOf(data);
  if (!startsWith(bytes, GIF87_MAGIC) && !startsWith(bytes, GIF89_MAGIC)) {
    throw new NativeImageError(NativeImageErrorCode.UNSUPPORTED_FORMAT, 'not a GIF stream');
  }
  return decodeWithFormat(data, FORMAT_GIF, partially);
}

/** 自动识别格式（对应上游 ImageDecoder 的嗅探分派） */
export function decode(data: ArrayBuffer | Uint8Array, partially: boolean = false): NativeImage {
  try {
    return nativeImage.decode(bytesOf(data), partially);
  } catch (e) {
    throw new NativeImageError(NativeImageErrorCode.DECODE_FAILED, `${e}`);
  }
}

/** 支持的格式列表（用于上游 ImageDecoder.getSupportedFormats 的等价判断） */
export function getSupportedFormats(): number[] {
  return nativeImage.getSupportedFormats();
}

export function parse7zErrorCode(message: string): NativeImageErrorCode {
  const m = /\[7z:(700[1-4])\]/.exec(message);
  if (m !== null) {
    const codeNum = Number(m[1]);
    if (codeNum === NativeImageErrorCode.SEVEN_ZIP_NOT_BUILT) {
      return NativeImageErrorCode.SEVEN_ZIP_NOT_BUILT;
    }
    if (codeNum === NativeImageErrorCode.SEVEN_ZIP_BAD_ARG) {
      return NativeImageErrorCode.SEVEN_ZIP_BAD_ARG;
    }
    if (codeNum === NativeImageErrorCode.SEVEN_ZIP_PASSWORD) {
      return NativeImageErrorCode.SEVEN_ZIP_PASSWORD;
    }
    return NativeImageErrorCode.SEVEN_ZIP_EXTRACT_FAILED;
  }
  return NativeImageErrorCode.SEVEN_ZIP_EXTRACT_FAILED;
}

/**
 * 7z 解压（D-004）。解析 native 抛出的 [7z:70xx] 错误码映射为对应 NativeImageErrorCode。
 */
export function extract7z(archive: ArrayBuffer | Uint8Array, outDir: string, password?: string): number {
  try {
    return nativeImage.extract7z(bytesOf(archive), outDir, password);
  } catch (e) {
    const msg: string = `${e}`;
    throw new NativeImageError(parse7zErrorCode(msg), msg);
  }
}

enum ArchiveKind {
  SEVEN_ZIP = 0,
  ZIP = 1,
}

class ArchiveSlotRef {
  readonly kind: ArchiveKind;
  readonly nativeHandle: number;

  constructor(kind: ArchiveKind, nativeHandle: number) {
    this.kind = kind;
    this.nativeHandle = nativeHandle;
  }
}

class NativeA7ZipBridge implements A7ZipBridge {
  private readonly slots: Map<number, ArchiveSlotRef> = new Map<number, ArchiveSlotRef>();
  private nextHandle: number = 1;

  private allocSlot(kind: ArchiveKind, nativeHandle: number): number {
    const id: number = this.nextHandle++;
    this.slots.set(id, new ArchiveSlotRef(kind, nativeHandle));
    return id;
  }

  private openWithZip(file: UniRandomAccessFile, total: number): number {
    const nh: number = nativeImage.openZip(total, (pos: number, buf: ArrayBuffer, len: number): number => {
      file.seek(pos);
      const n: number = file.readBytes(buf, 0, len);
      return n > 0 ? n : 0;
    });
    return nh > 0 ? this.allocSlot(ArchiveKind.ZIP, nh) : 0;
  }

  private openWith7z(file: UniRandomAccessFile, total: number): number {
    const nh: number = nativeImage.open7z(total, (pos: number, buf: ArrayBuffer, len: number): number => {
      file.seek(pos);
      const n: number = file.readBytes(buf, 0, len);
      return n > 0 ? n : 0;
    });
    return nh > 0 ? this.allocSlot(ArchiveKind.SEVEN_ZIP, nh) : 0;
  }

  open(file: UniRandomAccessFile): number {
    const format: ArchiveFormat = sniffRandomAccessFormat(file);
    if (format === ArchiveFormat.RAR) {
      throw new NativeImageError(
        NativeImageErrorCode.UNSUPPORTED_FORMAT,
        `${RAR_UNSUPPORTED_ERROR_MARKER} RAR archive format is not supported`
      );
    }
    try {
      const total: number = file.length();
      if (total <= 0) {
        return 0;
      }
      if (format === ArchiveFormat.ZIP) {
        const zipHandle: number = this.openWithZip(file, total);
        if (zipHandle > 0) {
          return zipHandle;
        }
        return this.openWith7z(file, total);
      }
      if (format === ArchiveFormat.SEVEN_ZIP) {
        return this.openWith7z(file, total);
      }
      const tryZip: number = this.openWithZip(file, total);
      if (tryZip > 0) {
        return tryZip;
      }
      return this.openWith7z(file, total);
    } catch (_e) {
      return 0;
    }
  }

  close(handle: number): void {
    const ref: ArchiveSlotRef | undefined = this.slots.get(handle);
    if (ref === undefined) {
      return;
    }
    this.slots.delete(handle);
    try {
      if (ref.kind === ArchiveKind.ZIP) {
        nativeImage.closeZip(ref.nativeHandle);
      } else {
        nativeImage.close7z(ref.nativeHandle);
      }
    } catch (_e) {
      // ignore close errors
    }
  }

  entryCount(handle: number): number {
    const ref: ArchiveSlotRef | undefined = this.slots.get(handle);
    if (ref === undefined) {
      return 0;
    }
    return ref.kind === ArchiveKind.ZIP
      ? nativeImage.getZipEntryCount(ref.nativeHandle)
      : nativeImage.get7zEntryCount(ref.nativeHandle);
  }

  entryPath(handle: number, index: number): string {
    const ref: ArchiveSlotRef | undefined = this.slots.get(handle);
    if (ref === undefined) {
      return '';
    }
    return ref.kind === ArchiveKind.ZIP
      ? nativeImage.getZipEntryName(ref.nativeHandle, index)
      : nativeImage.get7zEntryName(ref.nativeHandle, index);
  }

  entryBoolean(handle: number, index: number, prop: string): boolean {
    const ref: ArchiveSlotRef | undefined = this.slots.get(handle);
    if (ref === undefined) {
      return false;
    }
    if (ref.kind === ArchiveKind.ZIP) {
      if (prop === PropId.IS_DIR) {
        return nativeImage.isZipEntryDir(ref.nativeHandle, index);
      }
      if (prop === PropId.ENCRYPTED) {
        return nativeImage.isZipEntryEncrypted(ref.nativeHandle, index);
      }
      return false;
    }
    if (prop === PropId.IS_DIR) {
      return nativeImage.is7zEntryDir(ref.nativeHandle, index);
    }
    if (prop === PropId.ENCRYPTED) {
      return nativeImage.is7zEntryEncrypted(ref.nativeHandle, index);
    }
    return false;
  }

  archivePropertyType(_handle: number, prop: string): string {
    if (prop === PropId.ENCRYPTED) {
      return PropType.BOOL;
    }
    return PropType.NONE;
  }

  archiveBoolean(handle: number, prop: string): boolean {
    const ref: ArchiveSlotRef | undefined = this.slots.get(handle);
    if (ref === undefined) {
      return false;
    }
    if (prop === PropId.ENCRYPTED) {
      return ref.kind === ArchiveKind.ZIP
        ? nativeImage.isZipEncrypted(ref.nativeHandle)
        : nativeImage.is7zEncrypted(ref.nativeHandle);
    }
    return false;
  }

  extractEntry(handle: number, index: number, sink: OutputStream): void {
    const ref: ArchiveSlotRef | undefined = this.slots.get(handle);
    if (ref === undefined) {
      throw new NativeImageError(NativeImageErrorCode.BAD_ARGUMENT, 'invalid archive handle');
    }
    try {
      const data: ArrayBuffer = ref.kind === ArchiveKind.ZIP
        ? nativeImage.extractZipEntry(ref.nativeHandle, index)
        : nativeImage.extract7zEntry(ref.nativeHandle, index);
      if (data.byteLength > 0) {
        sink.writeBytes(data, 0, data.byteLength);
      }
      sink.flush();
    } catch (e) {
      const msg: string = `${e}`;
      throw new NativeImageError(parse7zErrorCode(msg), msg);
    }
  }
}

class ModuleNativeImageBackend implements NativeImageBackend {
  decode(buffer: ArrayBuffer | Uint8Array, partially: boolean): NativeImageHandleLike {
    return nativeImage.decode(buffer, partially);
  }

  createPlain(width: number, height: number, pixels: ArrayBuffer | Uint8Array): NativeImageHandleLike {
    return nativeImage.createPlain(width, height, pixels);
  }

  getSupportedFormats(): number[] {
    return nativeImage.getSupportedFormats();
  }

  getDecoderDescription(format: number): string {
    return nativeImage.getDecoderDescription(format);
  }
}

/** 创建接入 cpp/7z + cpp/napi/napi_zip NAPI 的 A7ZipBridge 实现（D-004 / Z2 / R1）。 */
export function createNativeA7ZipBridge(): A7ZipBridge {
  return new NativeA7ZipBridge();
}

/** 创建接入 Image1.setBridge() 的 LibImageBridge 实现（D-020）。 */
export function createNativeLibImageBridge(): LibImageBridge {
  return new NativeLibImageBridge(new ModuleNativeImageBackend());
}

/** GIF 逐帧解码器工厂（对齐上游 GifHandler 的构造语义） */
export function createGifDecoder(): GifDecoder {
  return new nativeImage.GifDecoder();
}
