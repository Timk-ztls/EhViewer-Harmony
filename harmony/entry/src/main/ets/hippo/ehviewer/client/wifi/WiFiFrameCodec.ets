/*
 * Copyright 2016 Hippo Seven
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

import util from '@ohos.util';
import { WiFiDataHand } from '../data/wifi/WiFiDataHand';
import { DirAck, DirManifest, FileChunk, FileMeta } from './MigrationTypes';
import { WiFiFrame } from './WiFiFrame';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/wifi/WiFiFrameCodec.java
 * （inventory S0118，321 行）
 *
 * 局域网迁移协议的唯一编解码点，**字节级照搬**（这是跨设备兼容的前提）：
 *
 * 帧头 22 字节，全部**大端**（Java DataOutputStream 语义）：
 *   [0..3]   MAGIC 'E','H','B','F'
 *   [4]      VERSION (unsigned byte)   = 1
 *   [5]      messageType (unsigned byte)
 *   [6..7]   dataType (unsigned short)
 *   [8..11]  pageIndex (int)
 *   [12..15] pageSize (int)
 *   [16..17] flags (unsigned short)    bit0 = FLAG_LAST_CHUNK
 *   [18..21] payloadLength (int)
 *   之后 payloadLength 字节 payload
 *
 * 三种二进制载荷（都用 `writeShort(len)+UTF-8 bytes` 写字符串）：
 *   Manifest: long gid, string dirname, short count, {string name, string md5, long size}*
 *   Ack:      long gid, string dirname, short count, {string name}*
 *   Chunk:    long gid, string name, string md5, int chunkIndex, int chunkTotal, int len, bytes
 *
 * 错误语义照搬：
 *   - readFrame：magic 不对 / version 不是 1 / payloadLength < 0 → 抛错
 *   - decodeManifest/decodeAck/decodeFileChunk：payload 为 null → null；解析中 IO 错 → null（不抛）
 *   - decodeFileChunk 额外检查 `len < 0 → null`
 *   - writeString 超 65535 字节 → 抛错
 */
export class WiFiFrameCodec {
  static readonly MAGIC: number[] = [0x45, 0x48, 0x42, 0x46]; // 'E','H','B','F'
  static readonly VERSION: number = 1;
  static readonly HEADER_SIZE: number = 22;
  static readonly FLAG_LAST_CHUNK: number = 1;

  /** 对齐 `encode(WiFiDataHand)`：payload 是 hand 的 JSON UTF-8 字节。 */
  static encode(hand: WiFiDataHand): WiFiFrame {
    const payload: ArrayBuffer = WiFiFrameCodec.utf8Encode(hand.toJsonObject());
    return new WiFiFrame(hand.messageType, hand.dataType, hand.pageIndex, hand.pageSize, 0, payload);
  }

  /** 对齐 `decodeDataHand(WiFiFrame)`。 */
  static decodeDataHand(frame: WiFiFrame): WiFiDataHand {
    if (frame.payload === null || frame.payload.byteLength === 0) {
      return new WiFiDataHand(WiFiDataHand.ERROR);
    }
    const text: string = WiFiFrameCodec.utf8Decode(frame.payload);
    const hand: WiFiDataHand = new WiFiDataHand(frame.messageType, undefined);
    hand.dataType = frame.dataType;
    hand.pageSize = frame.pageSize;
    hand.pageIndex = frame.pageIndex;
    try {
      const parsed: WiFiDataHand = WiFiDataHand.fromJson(text);
      // 帧头值先落地，payload 内若显式给出同名字段则以 payload 为准（上游逐键覆盖）
      hand.dataType = parsed.dataType !== 0 ? parsed.dataType : hand.dataType;
      if (parsed.pageSize !== 1) {
        hand.pageSize = parsed.pageSize;
      }
      if (parsed.pageIndex !== 1) {
        hand.pageIndex = parsed.pageIndex;
      }
      hand.setData(parsed.getData());
      if (parsed.messageType !== 0) {
        hand.messageType = parsed.messageType;
      }
      if (parsed.errorMessage !== null) {
        hand.errorMessage = parsed.errorMessage;
      }
      return hand;
    } catch (e) {
      return new WiFiDataHand(WiFiDataHand.ERROR);
    }
  }

  /** 对齐 `encodeManifest(long, String, List<FileMeta>, int, int)`。 */
  static encodeManifest(gid: number, dirname: string, files: FileMeta[],
    pageIndex: number, pageSize: number, dataType: number): WiFiFrame {
    const w: ByteWriter = new ByteWriter();
    w.writeLong(gid);
    WiFiFrameCodec.writeString(w, dirname);
    w.writeShort(Math.min(files.length, 65535));
    for (let i = 0; i < files.length; i++) {
      WiFiFrameCodec.writeString(w, files[i].name);
      WiFiFrameCodec.writeString(w, files[i].md5);
      w.writeLong(files[i].size);
    }
    return new WiFiFrame(WiFiDataHand.SEND, dataType, pageIndex, pageSize, 0, w.toArrayBuffer());
  }

  /** 对齐 `decodeManifest(WiFiFrame)`。 */
  static decodeManifest(frame: WiFiFrame): DirManifest | null {
    if (frame.payload === null) {
      return null;
    }
    try {
      const r: ByteReader = new ByteReader(frame.payload);
      const manifest: DirManifest = new DirManifest();
      manifest.gid = r.readLong();
      manifest.dirname = WiFiFrameCodec.readString(r);
      const count: number = r.readUnsignedShort();
      const files: FileMeta[] = [];
      for (let i = 0; i < count; i++) {
        const meta: FileMeta = new FileMeta();
        meta.name = WiFiFrameCodec.readString(r);
        meta.md5 = WiFiFrameCodec.readString(r);
        meta.size = r.readLong();
        files.push(meta);
      }
      manifest.files = files;
      manifest.pageIndex = frame.pageIndex;
      manifest.pageSize = frame.pageSize;
      return manifest;
    } catch (e) {
      return null;
    }
  }

  /** 对齐 `encodeAck(long, String, List<String>)`。 */
  static encodeAck(gid: number, dirname: string, filesNeeded: string[], dataType: number): WiFiFrame {
    const w: ByteWriter = new ByteWriter();
    w.writeLong(gid);
    WiFiFrameCodec.writeString(w, dirname);
    w.writeShort(Math.min(filesNeeded.length, 65535));
    for (let i = 0; i < filesNeeded.length; i++) {
      WiFiFrameCodec.writeString(w, filesNeeded[i]);
    }
    return new WiFiFrame(WiFiDataHand.RECEIVED, dataType, 0, 0, 0, w.toArrayBuffer());
  }

  /** 对齐 `decodeAck(WiFiFrame)`。 */
  static decodeAck(frame: WiFiFrame): DirAck | null {
    if (frame.payload === null) {
      return null;
    }
    try {
      const r: ByteReader = new ByteReader(frame.payload);
      const ack: DirAck = new DirAck();
      ack.gid = r.readLong();
      ack.dirname = WiFiFrameCodec.readString(r);
      const count: number = r.readUnsignedShort();
      const files: string[] = [];
      for (let i = 0; i < count; i++) {
        files.push(WiFiFrameCodec.readString(r));
      }
      ack.filesNeeded = files;
      return ack;
    } catch (e) {
      return null;
    }
  }

  /** 对齐 `encodeFileChunk(...)`。 */
  static encodeFileChunk(gid: number, name: string, fileMd5: string, chunkIndex: number,
    chunkTotal: number, data: ArrayBuffer, lastChunk: boolean, dataType: number): WiFiFrame {
    const w: ByteWriter = new ByteWriter();
    w.writeLong(gid);
    WiFiFrameCodec.writeString(w, name);
    WiFiFrameCodec.writeString(w, fileMd5);
    w.writeInt(chunkIndex);
    w.writeInt(chunkTotal);
    w.writeInt(data.byteLength);
    w.writeBytes(data);
    const flags: number = lastChunk ? WiFiFrameCodec.FLAG_LAST_CHUNK : 0;
    return new WiFiFrame(WiFiDataHand.SEND, dataType, chunkIndex, chunkTotal, flags, w.toArrayBuffer());
  }

  /** 对齐 `decodeFileChunk(WiFiFrame)`。 */
  static decodeFileChunk(frame: WiFiFrame): FileChunk | null {
    if (frame.payload === null) {
      return null;
    }
    try {
      const r: ByteReader = new ByteReader(frame.payload);
      const chunk: FileChunk = new FileChunk();
      chunk.gid = r.readLong();
      chunk.name = WiFiFrameCodec.readString(r);
      chunk.fileMd5 = WiFiFrameCodec.readString(r);
      chunk.chunkIndex = r.readInt();
      chunk.chunkTotal = r.readInt();
      const len: number = r.readInt();
      if (len < 0) {
        return null;
      }
      chunk.data = r.readBytes(len);
      chunk.lastChunk = (frame.flags & WiFiFrameCodec.FLAG_LAST_CHUNK) !== 0;
      return chunk;
    } catch (e) {
      return null;
    }
  }

  /** 对齐 `writeFrame(OutputStream, WiFiFrame)`：22 字节头 + payload。 */
  static writeFrame(frame: WiFiFrame): ArrayBuffer {
    const payload: ArrayBuffer = frame.payload === null ? new ArrayBuffer(0) : (frame.payload as ArrayBuffer);
    const w: ByteWriter = new ByteWriter();
    w.writeBytes(new Uint8Array(WiFiFrameCodec.MAGIC).buffer as ArrayBuffer);
    w.writeByte(WiFiFrameCodec.VERSION);
    w.writeByte(frame.messageType);
    w.writeShort(frame.dataType);
    w.writeInt(frame.pageIndex);
    w.writeInt(frame.pageSize);
    w.writeShort(frame.flags);
    w.writeInt(payload.byteLength);
    if (payload.byteLength > 0) {
      w.writeBytes(payload);
    }
    return w.toArrayBuffer();
  }

  /** 对齐 `readFrame(InputStream)`：从字节数组读一帧，返回帧与消耗的字节数。 */
  static readFrame(bytes: ArrayBuffer, offset: number): FrameReadResult {
    if (bytes.byteLength - offset < WiFiFrameCodec.HEADER_SIZE) {
      throw new Error('EOF');
    }
    const r: ByteReader = new ByteReader(bytes, offset);
    const magic: Uint8Array = r.readBytesRaw(4);
    for (let i = 0; i < 4; i++) {
      if (magic[i] !== WiFiFrameCodec.MAGIC[i]) {
        throw new Error('Invalid frame magic');
      }
    }
    const version: number = r.readUnsignedByte();
    if (version !== WiFiFrameCodec.VERSION) {
      throw new Error('Unsupported frame version: ' + version);
    }
    const frame: WiFiFrame = new WiFiFrame();
    frame.messageType = r.readUnsignedByte();
    frame.dataType = r.readUnsignedShort();
    frame.pageIndex = r.readInt();
    frame.pageSize = r.readInt();
    frame.flags = r.readUnsignedShort();
    const payloadLength: number = r.readInt();
    if (payloadLength < 0) {
      throw new Error('Invalid payload length');
    }
    if (payloadLength === 0) {
      frame.payload = new ArrayBuffer(0);
    } else {
      frame.payload = r.readBytes(payloadLength);
    }
    const result: FrameReadResult = new FrameReadResult();
    result.frame = frame;
    result.consumed = WiFiFrameCodec.HEADER_SIZE + payloadLength;
    return result;
  }

  // ---- 内部：字符串 UTF-8 短前缀读写 ----

  private static writeString(w: ByteWriter, s: string): void {
    const bytes: Uint8Array = new Uint8Array(WiFiFrameCodec.utf8Encode(s));
    if (bytes.length > 65535) {
      throw new Error('String too long');
    }
    w.writeShort(bytes.length);
    w.writeBytes(bytes.buffer.slice(0, bytes.length) as ArrayBuffer);
  }

  private static readString(r: ByteReader): string {
    const len: number = r.readUnsignedShort();
    return WiFiFrameCodec.utf8Decode(r.readBytes(len));
  }

  // ArkTS 没有全局 TextEncoder/TextDecoder，用 @ohos.util（与 okhttp/RequestBody 同一手法）
  private static utf8Encode(s: string): ArrayBuffer {
    const enc = new util.TextEncoder('utf-8') as Utf8EncoderLike;
    const u8: Uint8Array = enc.encodeInto(s);
    return u8.buffer.slice(u8.byteOffset, u8.byteOffset + u8.byteLength) as ArrayBuffer;
  }

  private static utf8Decode(buf: ArrayBuffer): string {
    const dec = util.TextDecoder.create('utf-8', { fatal: false, ignoreBOM: false }) as Utf8DecoderLike;
    return dec.decodeToString(new Uint8Array(buf));
  }
}

/** `readFrame` 的结果：帧 + 本次消耗字节数（流式解析要据此推进偏移）。 */
export class FrameReadResult {
  frame: WiFiFrame = new WiFiFrame();
  consumed: number = 0;
}

/** 大端写入器（对齐 DataOutputStream）。 */
export class ByteWriter {
  private _bytes: number[] = [];

  writeByte(v: number): void {
    this._bytes.push(v & 0xff);
  }

  writeShort(v: number): void {
    this._bytes.push((v >> 8) & 0xff);
    this._bytes.push(v & 0xff);
  }

  writeInt(v: number): void {
    this._bytes.push((v >>> 24) & 0xff);
    this._bytes.push((v >>> 16) & 0xff);
    this._bytes.push((v >>> 8) & 0xff);
    this._bytes.push(v & 0xff);
  }

  writeLong(v: number): void {
    // JS 数字安全整数范围内：高 32 位 / 低 32 位拆分
    const hi: number = Math.floor(v / 4294967296);
    const lo: number = v - hi * 4294967296;
    this.writeInt(hi);
    this.writeInt(lo);
  }

  writeBytes(buf: ArrayBuffer): void {
    const u8: Uint8Array = new Uint8Array(buf);
    for (let i = 0; i < u8.length; i++) {
      this._bytes.push(u8[i]);
    }
  }

  toArrayBuffer(): ArrayBuffer {
    const u8: Uint8Array = new Uint8Array(this._bytes.length);
    for (let i = 0; i < this._bytes.length; i++) {
      u8[i] = this._bytes[i];
    }
    return u8.buffer as ArrayBuffer;
  }
}

/** 大端读取器（对齐 DataInputStream；越界抛错，与 EOFException 等价）。 */
export class ByteReader {
  private _u8: Uint8Array;
  private _offset: number = 0;

  constructor(buf: ArrayBuffer, offset: number = 0) {
    this._u8 = new Uint8Array(buf);
    this._offset = offset;
  }

  private need(n: number): void {
    if (this._offset + n > this._u8.length) {
      throw new Error('EOF');
    }
  }

  readUnsignedByte(): number {
    this.need(1);
    return this._u8[this._offset++];
  }

  readUnsignedShort(): number {
    this.need(2);
    const v: number = (this._u8[this._offset] << 8) | this._u8[this._offset + 1];
    this._offset += 2;
    return v;
  }

  readInt(): number {
    this.need(4);
    const v: number = (this._u8[this._offset] << 24) | (this._u8[this._offset + 1] << 16) |
      (this._u8[this._offset + 2] << 8) | this._u8[this._offset + 3];
    this._offset += 4;
    return v | 0;
  }

  readLong(): number {
    const hi: number = this.readInt();
    const lo: number = this.readInt() >>> 0;
    return hi * 4294967296 + lo;
  }

  readBytesRaw(n: number): Uint8Array {
    this.need(n);
    const out: Uint8Array = this._u8.slice(this._offset, this._offset + n);
    this._offset += n;
    return out;
  }

  readBytes(n: number): ArrayBuffer {
    this.need(n);
    const out: ArrayBuffer = this._u8.slice(this._offset, this._offset + n).buffer as ArrayBuffer;
    this._offset += n;
    return out;
  }

  remaining(): number {
    return this._u8.length - this._offset;
  }
}


/** @ohos.util 的最小结构（避免把平台命名空间类型带进纯逻辑测试）。 */
interface Utf8EncoderLike {
  encodeInto(s: string): Uint8Array;
}

interface Utf8DecoderLike {
  decodeToString(u8: Uint8Array): string;
}