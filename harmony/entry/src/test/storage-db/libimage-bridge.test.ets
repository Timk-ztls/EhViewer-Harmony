/*
 * D-020 NativeLibImageBridge 16 方法与 handle 生命周期单测（Stage C Track P5）。
 */

import fs from '@ohos.file.fs';
import image from '@ohos.multimedia.image';
import { Image1 } from '../../main/ets/hippo/lib/image/Image1';
import {
  NativeImageBackend,
  NativeImageHandleLike,
  NativeLibImageBridge,
  TextureUploadSink
} from '../../main/ets/hippo/lib/image/NativeLibImageBridge';

let pass = 0;
const fails: string[] = [];

function eq(name: string, got: unknown, want: unknown): void {
  const g = JSON.stringify(got);
  const w = JSON.stringify(want);
  if (g === w) {
    pass++;
  } else {
    fails.push(`${name}: got ${g} want ${w}`);
  }
}

function ok(name: string, cond: boolean): void {
  if (cond) {
    pass++;
  } else {
    fails.push(name);
  }
}

class MockHandle implements NativeImageHandleLike {
  format: number;
  width: number;
  height: number;
  byteCount: number;
  delay: number = 120;
  frameCount: number = 3;
  completed: boolean = false;
  advances: number = 0;
  claheCalls: number = 0;
  recycled: boolean = false;
  renderedWidth: number = 0;
  private readonly rawPixels: Uint8Array;

  constructor(format: number, width: number, height: number) {
    this.format = format;
    this.width = width;
    this.height = height;
    this.byteCount = width * height * 4;
    this.rawPixels = new Uint8Array(this.byteCount);
    for (let i = 0; i < this.rawPixels.length; i++) {
      this.rawPixels[i] = (i & 0xFF);
    }
  }

  getPixels(): ArrayBuffer {
    const ab = new ArrayBuffer(this.rawPixels.byteLength);
    new Uint8Array(ab).set(this.rawPixels);
    return ab;
  }

  complete(): boolean {
    this.completed = true;
    return true;
  }

  isCompleted(): boolean {
    return this.completed;
  }

  render(dst: ArrayBuffer | Uint8Array, _dstW: number, _dstH: number,
    _srcX: number, _srcY: number, _dstX: number, _dstY: number,
    width: number, height: number, _fillBlank: boolean, _defaultColor: number): void {
    this.renderedWidth = width;
    const view = dst instanceof Uint8Array ? dst : new Uint8Array(dst);
    const n = Math.min(view.length, this.rawPixels.length);
    for (let i = 0; i < n; i++) {
      view[i] = this.rawPixels[i];
    }
    if (height < 0) {
      this.renderedWidth = 0;
    }
  }

  advance(): void {
    this.advances++;
  }

  isOpaque(): boolean {
    return true;
  }

  isGray(_error: number): boolean {
    return false;
  }

  clahe(_toGray: boolean): void {
    this.claheCalls++;
  }

  recycle(): void {
    this.recycled = true;
  }
}

class MockBackend implements NativeImageBackend {
  lastDecodedBytes: number = 0;
  lastPlainDims: string = '';
  createdHandles: MockHandle[] = [];

  decode(buffer: ArrayBuffer | Uint8Array, _partially: boolean): NativeImageHandleLike {
    const view = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer);
    this.lastDecodedBytes = view.byteLength;
    const h = new MockHandle(Image1.FORMAT_PNG, 2, 2);
    this.createdHandles.push(h);
    return h;
  }

  createPlain(width: number, height: number, _pixels: ArrayBuffer | Uint8Array): NativeImageHandleLike {
    this.lastPlainDims = `${width}x${height}`;
    const h = new MockHandle(Image1.FORMAT_PLAIN, width, height);
    this.createdHandles.push(h);
    return h;
  }

  getSupportedFormats(): number[] {
    return [Image1.FORMAT_JPEG, Image1.FORMAT_PNG, Image1.FORMAT_WEBP, Image1.FORMAT_GIF];
  }

  getDecoderDescription(format: number): string {
    return format === Image1.FORMAT_PNG ? 'libpng' : '';
  }
}

class RecordingUploadSink implements TextureUploadSink {
  calls: number = 0;
  lastWidth: number = 0;
  lastHeight: number = 0;
  lastInit: boolean = false;

  uploadTexture(_pixelMap: image.PixelMap, init: boolean, _offsetX: number, _offsetY: number,
    width: number, height: number): void {
    this.calls++;
    this.lastInit = init;
    this.lastWidth = width;
    this.lastHeight = height;
  }
}

interface FsSeedExt {
  __seedFile: (path: string, data: Uint8Array) => void;
}

{
  const backend = new MockBackend();
  const texSink = new RecordingUploadSink();
  const bridge = new NativeLibImageBridge(backend, texSink);
  Image1.setBridge(bridge);

  ok('invalid fd decode returns 0n', bridge.decode(-1, false) === BigInt(0));
  ok('null PixelMap create returns 0n', bridge.create(null) === BigInt(0));

  const fsExt = fs as unknown as FsSeedExt;
  fsExt.__seedFile('/tmp/test_libimage.png', new Uint8Array([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4]));
  const f = fs.openSync('/tmp/test_libimage.png', fs.OpenMode.READ_ONLY);
  const ptr = bridge.decode(f.fd, true);
  fs.closeSync(f);

  ok('decode valid fd returns non-zero ptr', ptr > BigInt(0));
  eq('decoded byte length read fully', backend.lastDecodedBytes, 8);
  eq('activeHandleCount = 1', bridge.activeHandleCount(), 1);
  eq('getByteCount = 16', bridge.getByteCount(ptr, Image1.FORMAT_PNG), 16);
  eq('isCompleted initially false', bridge.isCompleted(ptr, Image1.FORMAT_PNG), false);
  eq('complete returns true', bridge.complete(ptr, Image1.FORMAT_PNG), true);
  eq('isCompleted after complete', bridge.isCompleted(ptr, Image1.FORMAT_PNG), true);

  const dstPm = image.createPixelMapSync(new ArrayBuffer(16), { size: { width: 2, height: 2 } });
  bridge.render(ptr, Image1.FORMAT_PNG, 0, 0, dstPm, 0, 0, 2, 2, true, 0);
  eq('render forwarded width', backend.createdHandles[0].renderedWidth, 2);

  bridge.texImage(ptr, Image1.FORMAT_PNG, true, 0, 0, 2, 2);
  eq('texImage called uploadSink once', texSink.calls, 1);
  eq('texImage passed init=true & 2x2', [texSink.lastInit, texSink.lastWidth, texSink.lastHeight], [true, 2, 2]);

  bridge.advance(ptr, Image1.FORMAT_PNG);
  eq('advance incremented handle counter', backend.createdHandles[0].advances, 1);
  eq('getDelay = 120', bridge.getDelay(ptr, Image1.FORMAT_PNG), 120);
  eq('frameCount = 3', bridge.frameCount(ptr, Image1.FORMAT_PNG), 3);
  eq('isOpaque = true', bridge.isOpaque(ptr, Image1.FORMAT_PNG), true);
  eq('isGray = false', bridge.isGray(ptr, Image1.FORMAT_PNG, 1), false);
  bridge.clahe(ptr, Image1.FORMAT_PNG, true);
  eq('clahe forwarded', backend.createdHandles[0].claheCalls, 1);

  eq('supportedImageFormats matched', Image1.supportedImageFormats(),
    [Image1.FORMAT_JPEG, Image1.FORMAT_PNG, Image1.FORMAT_WEBP, Image1.FORMAT_GIF]);
  eq('decoderDescription non-empty for PNG', Image1.getDecoderDescription(Image1.FORMAT_PNG), 'libpng');
  eq('decoderDescription null for unknown', Image1.getDecoderDescription(99), null);

  bridge.recycle(ptr, Image1.FORMAT_PNG);
  ok('handle marked recycled', backend.createdHandles[0].recycled);
  eq('activeHandleCount = 0 after recycle', bridge.activeHandleCount(), 0);

  const ptrPlain = bridge.create(dstPm);
  ok('create from PixelMap returns non-zero ptr', ptrPlain > BigInt(0));
  eq('createPlain received 2x2', backend.lastPlainDims, '2x2');
  bridge.recycle(ptrPlain, Image1.FORMAT_PLAIN);
  eq('activeHandleCount = 0 after plain recycle', bridge.activeHandleCount(), 0);
}

if (fails.length > 0) {
  console.log(`\n${fails.length} 个断言失败：`);
  for (const f of fails) {
    console.log(`  ✗ ${f}`);
  }
  console.log(`\n通过 ${pass}，失败 ${fails.length}`);
  process.exit(1);
}
console.log(`全部通过：${pass} 个断言`);
