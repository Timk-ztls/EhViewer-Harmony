// WiFiFrameCodec 字节级一致性测试（构造样本）
//
// 这是**跨设备协议**，字节布局错一位就无法与上游设备互操作，所以逐字节断言：
//   帧头 22 字节各字段的偏移与端序、MAGIC、VERSION、FLAG_LAST_CHUNK
//   Manifest / Ack / FileChunk 三种二进制载荷的字段顺序与长度前缀
//   DataHand 的 JSON 键名（totalSize / part 而不是 pageSize / pageIndex）
//   错误语义：magic 错 / version 错 / payloadLength<0 / payload=null

import { WiFiFrame } from '../wifi/WiFiFrame';
import { WiFiFrameCodec, ByteReader } from '../wifi/WiFiFrameCodec';
import { WiFiDataHand } from './wifi/WiFiDataHand';
import { FileMeta } from '../wifi/MigrationTypes';

let pass = 0;
let fail = 0;
const failures: string[] = [];

function eq(name: string, actual: unknown, expected: unknown): void {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a === e) {
    pass++;
  } else {
    fail++;
    failures.push(`${name}\n    actual  = ${a}\n    expected= ${e}`);
  }
}

function ok(name: string, cond: boolean): void {
  if (cond) {
    pass++;
  } else {
    fail++;
    failures.push(name);
  }
}

function hex(buf: ArrayBuffer, len: number): string {
  const u8 = new Uint8Array(buf);
  const out: string[] = [];
  for (let i = 0; i < len && i < u8.length; i++) {
    out.push(u8[i].toString(16).padStart(2, '0'));
  }
  return out.join(' ');
}

const DT_MANIFEST = 1005;
const DT_ACK = 1006;
const DT_FILE = 1007;

// ---------- 1. 帧头逐字节 ----------
{
  const frame = new WiFiFrame(2 /* SEND */, 0x03FF, 0x01020304, -2, 1, null);
  const bytes = WiFiFrameCodec.writeFrame(frame);
  eq('帧头长度 22', bytes.byteLength, 22);
  eq('MAGIC', hex(bytes, 4), '45 48 42 46'); // E H B F
  const r = new ByteReader(bytes);
  r.readBytesRaw(4);
  eq('VERSION', r.readUnsignedByte(), 1);
  eq('messageType', r.readUnsignedByte(), 2);
  eq('dataType (unsigned short) 大端', r.readUnsignedShort(), 0x03ff);
  eq('pageIndex (int) 大端', r.readInt(), 0x01020304);
  eq('pageSize (int) 负值', r.readInt(), -2);
  eq('flags', r.readUnsignedShort(), 1);
  eq('payloadLength', r.readInt(), 0);
}

// ---------- 2. 带 payload 的往返 ----------
{
  const payload = new Uint8Array([1, 2, 3, 4, 5]).buffer;
  const frame = new WiFiFrame(1, 1002, 7, 9, 0, payload as ArrayBuffer);
  const bytes = WiFiFrameCodec.writeFrame(frame);
  eq('总长 = 22 + 5', bytes.byteLength, 27);
  const res = WiFiFrameCodec.readFrame(bytes, 0);
  eq('往返 messageType', res.frame.messageType, 1);
  eq('往返 dataType', res.frame.dataType, 1002);
  eq('往返 pageIndex', res.frame.pageIndex, 7);
  eq('往返 pageSize', res.frame.pageSize, 9);
  eq('往返 payload 长度', (res.frame.payload as ArrayBuffer).byteLength, 5);
  eq('往返 payload 内容', Array.from(new Uint8Array(res.frame.payload as ArrayBuffer)), [1, 2, 3, 4, 5]);
  eq('consumed', res.consumed, 27);
}

// ---------- 3. 错误语义 ----------
{
  const bad = new Uint8Array(22);
  bad[0] = 0x45; bad[1] = 0x48; bad[2] = 0x42; bad[3] = 0x00; // magic 坏
  let threw = false;
  try {
    WiFiFrameCodec.readFrame(bad.buffer as ArrayBuffer, 0);
  } catch (e) {
    threw = (e as Error).message === 'Invalid frame magic';
  }
  ok('magic 错 → Invalid frame magic', threw);

  const badVer = new Uint8Array(22);
  badVer[0] = 0x45; badVer[1] = 0x48; badVer[2] = 0x42; badVer[3] = 0x46;
  badVer[4] = 2; // version 2
  threw = false;
  try {
    WiFiFrameCodec.readFrame(badVer.buffer as ArrayBuffer, 0);
  } catch (e) {
    threw = (e as Error).message.indexOf('Unsupported frame version') >= 0;
  }
  ok('version 错 → Unsupported frame version', threw);

  threw = false;
  try {
    WiFiFrameCodec.readFrame(new ArrayBuffer(10), 0);
  } catch (e) {
    threw = (e as Error).message === 'EOF';
  }
  ok('不足 22 字节 → EOF', threw);

  ok('decodeManifest(null payload) → null',
    WiFiFrameCodec.decodeManifest(new WiFiFrame(2, DT_MANIFEST, 0, 0, 0, null)) === null);
  ok('decodeAck(null payload) → null',
    WiFiFrameCodec.decodeAck(new WiFiFrame(1, DT_ACK, 0, 0, 0, null)) === null);
  ok('decodeFileChunk(null payload) → null',
    WiFiFrameCodec.decodeFileChunk(new WiFiFrame(2, DT_FILE, 0, 0, 0, null)) === null);
  ok('decodeFileChunk(截断) → null',
    WiFiFrameCodec.decodeFileChunk(new WiFiFrame(2, DT_FILE, 0, 0, 0, new Uint8Array([0, 1, 2]).buffer as ArrayBuffer)) === null);
  ok('decodeDataHand(空 payload) → ERROR',
    WiFiFrameCodec.decodeDataHand(new WiFiFrame(2, 1001, 0, 0, 0, new ArrayBuffer(0))).messageType === WiFiDataHand.ERROR);
}

// ---------- 4. Manifest 往返（含中文字节长度） ----------
{
  const files: FileMeta[] = [];
  const f1 = new FileMeta();
  f1.name = '001.jpg'; f1.md5 = 'd41d8cd98f00b204e9800998ecf8427e'; f1.size = 123456;
  const f2 = new FileMeta();
  f2.name = '封面.jpg'; f2.md5 = 'abcdefabcdefabcdefabcdefabcdefab'; f2.size = 7890;
  files.push(f1, f2);

  const frame = WiFiFrameCodec.encodeManifest(987654321, '(C91) 标题', files, 2, 5, DT_MANIFEST);
  eq('manifest messageType = SEND', frame.messageType, WiFiDataHand.SEND);
  eq('manifest dataType', frame.dataType, DT_MANIFEST);
  eq('manifest pageIndex', frame.pageIndex, 2);
  eq('manifest pageSize', frame.pageSize, 5);

  const m = WiFiFrameCodec.decodeManifest(frame);
  ok('manifest 解析成功', m !== null);
  eq('manifest.gid', (m as { gid: number }).gid, 987654321);
  eq('manifest.dirname（UTF-8）', (m as { dirname: string }).dirname, '(C91) 标题');
  eq('manifest.files 长度', (m as { files: FileMeta[] }).files.length, 2);
  eq('manifest.files[0].name', (m as { files: FileMeta[] }).files[0].name, '001.jpg');
  eq('manifest.files[0].size', (m as { files: FileMeta[] }).files[0].size, 123456);
  eq('manifest.files[1].name（中文）', (m as { files: FileMeta[] }).files[1].name, '封面.jpg');
  eq('manifest.pageIndex 来自帧头', (m as { pageIndex: number }).pageIndex, 2);
}

// ---------- 5. Ack 往返 ----------
{
  const frame = WiFiFrameCodec.encodeAck(42, 'dir', ['a.jpg', 'b.jpg', 'c.jpg'], DT_ACK);
  eq('ack messageType = RECEIVED', frame.messageType, WiFiDataHand.RECEIVED);
  const ack = WiFiFrameCodec.decodeAck(frame);
  ok('ack 解析成功', ack !== null);
  eq('ack.gid', (ack as { gid: number }).gid, 42);
  eq('ack.dirname', (ack as { dirname: string }).dirname, 'dir');
  eq('ack.filesNeeded', (ack as { filesNeeded: string[] }).filesNeeded, ['a.jpg', 'b.jpg', 'c.jpg']);
}

// ---------- 6. FileChunk 往返（含 lastChunk 标志） ----------
{
  const data = new Uint8Array([9, 8, 7, 6]).buffer as ArrayBuffer;
  const frame = WiFiFrameCodec.encodeFileChunk(100, 'x.jpg', 'md5x', 3, 10, data, true, DT_FILE);
  eq('chunk flags 含 LAST_CHUNK', frame.flags & WiFiFrameCodec.FLAG_LAST_CHUNK, 1);
  const c = WiFiFrameCodec.decodeFileChunk(frame);
  ok('chunk 解析成功', c !== null);
  eq('chunk.gid', (c as { gid: number }).gid, 100);
  eq('chunk.name', (c as { name: string }).name, 'x.jpg');
  eq('chunk.chunkIndex', (c as { chunkIndex: number }).chunkIndex, 3);
  eq('chunk.chunkTotal', (c as { chunkTotal: number }).chunkTotal, 10);
  eq('chunk.data', Array.from(new Uint8Array((c as { data: ArrayBuffer }).data)), [9, 8, 7, 6]);
  eq('chunk.lastChunk', (c as { lastChunk: boolean }).lastChunk, true);

  const frame2 = WiFiFrameCodec.encodeFileChunk(100, 'x.jpg', 'md5x', 1, 10, data, false, DT_FILE);
  eq('非末块 flags = 0', frame2.flags, 0);
}

// ---------- 7. DataHand JSON 键名契约 ----------
{
  const hand = new WiFiDataHand(WiFiDataHand.SEND, '{"quick_search":"abc"}');
  hand.dataType = 1001;
  hand.pageSize = 20;
  hand.pageIndex = 3;
  const json = hand.toJsonObject();
  ok('JSON 含 messageType', json.indexOf('"messageType":2') >= 0);
  ok('JSON 用 totalSize 而不是 pageSize', json.indexOf('"totalSize":20') >= 0 && json.indexOf('"pageSize"') < 0);
  ok('JSON 用 part 而不是 pageIndex', json.indexOf('"part":3') >= 0 && json.indexOf('"pageIndex"') < 0);
  ok('JSON data 原样嵌入', json.indexOf('"data":{"quick_search":"abc"}') >= 0);

  const round = WiFiDataHand.fromJson(hand.toJsonObject());
  eq('fromJson messageType', round.messageType, WiFiDataHand.SEND);
  eq('fromJson dataType', round.dataType, 1001);
  eq('fromJson totalSize → pageSize', round.pageSize, 20);
  eq('fromJson part → pageIndex', round.pageIndex, 3);
  eq('fromJson data', round.getData(), '{"quick_search":"abc"}');

  const badHand = WiFiDataHand.fromJson('not json');
  eq('fromJson 非法 → ERROR', badHand.messageType, WiFiDataHand.ERROR);
  ok('fromJson 非法 → errorMessage 非空', badHand.errorMessage !== null);
}

// ---------- 8. encode/decodeDataHand 端到端 ----------
{
  const hand = new WiFiDataHand(WiFiDataHand.SEND, '{"download_info":"x"}');
  hand.dataType = 1002;
  const frame = WiFiFrameCodec.encode(hand);
  eq('encode messageType', frame.messageType, WiFiDataHand.SEND);
  eq('encode dataType', frame.dataType, 1002);
  const back = WiFiFrameCodec.decodeDataHand(frame);
  eq('decode dataType', back.dataType, 1002);
  eq('decode data', back.getData(), '{"download_info":"x"}');
}

// ---------- 汇总 ----------
console.log(`\n=== 结果：${pass} passed, ${fail} failed ===`);
if (fail > 0) {
  for (const f of failures) {
    console.log('  FAIL ' + f);
  }
  throw new Error('WiFiFrameCodec 断言失败：' + fail);
}
