/*
 * 分片写 + 下载结果值对象 单测（纯逻辑，不依赖 okhttp 栈）
 *
 * 三个必须成立的行为（Lead 裁决）：
 *   ① 不依赖文件类型（只经 ByteSink 写字节）
 *   ② **分片写**：大于 CHUNK_SIZE 的内容要多次 write()，每次写的是**独立副本**
 *   ③ 必须暴露 HTTP 状态码：509 与「连不上（-1）」要能区分
 */

import { DEFAULT_CHUNK_SIZE, DownloadResult, writeInChunks } from '../../../okhttp/ChunkedSinkWriter';
import { ByteSink } from '../../../streampipe/OutputStreamPipe';

let pass = 0;
const fails: string[] = [];
function eq(name: string, got: unknown, want: unknown): void {
  const g = JSON.stringify(got);
  const w = JSON.stringify(want);
  if (g === w) { pass++; } else { fails.push(`${name}: got ${g} want ${w}`); }
}
function ok(name: string, cond: boolean): void {
  if (cond) { pass++; } else { fails.push(name); }
}

/** 记录每次 write 的字节：既校验分片次数，也校验内容拼接后与源一致。 */
class RecordingSink implements ByteSink {
  chunks: Uint8Array[] = [];
  closed: number = 0;

  write(data: ArrayBuffer): void {
    // 拷贝一份，验证「每次拿到的是独立副本」（否则后续写入会改到已交出的数据）
    this.chunks.push(new Uint8Array(data.slice(0)));
  }

  close(): void {
    this.closed++;
  }

  total(): number {
    let n = 0;
    for (const c of this.chunks) {
      n += c.length;
    }
    return n;
  }
}

// ---------------------------------------------------------------- 1. 常量
{
  eq('默认分片 = 64KB', DEFAULT_CHUNK_SIZE, 64 * 1024);
}

// ---------------------------------------------------------------- 2. DownloadResult 字段语义
{
  const ok1 = new DownloadResult(true, 200, 1234, '');
  eq('成功结果 ok', ok1.ok, true);
  eq('状态码', ok1.status, 200);
  eq('字节数', ok1.received, 1234);
  eq('成功时 error 为空串（不是 null）', ok1.error, '');

  const quota = new DownloadResult(false, 509, 0, 'HTTP 509');
  eq('509 能被识别', quota.status, 509);
  const offline = new DownloadResult(false, -1, 0, 'connect timeout');
  eq('连不上时 status = -1', offline.status, -1);
  ok('509 与 -1 不相等（这是能区分两种失败的前提）', quota.status !== offline.status);

  // C-18：hijacked 是独立维度，不能靠 status/error 反推
  eq('默认构造 hijacked=false', ok1.hijacked, false);
  const hj = new DownloadResult(false, -1, 0,
    '链接疑似被劫持\nThe link is suspected to be hijacked', true);
  eq('被劫持 → hijacked=true', hj.hijacked, true);
  ok('被劫持与"连不上"status 都是 -1，只能靠 hijacked 区分', hj.status === offline.status && hj.hijacked !== offline.hijacked);
}

// ---------------------------------------------------------------- 3. 分片写：2.5 块 → 3 次
{
  const total: number = DEFAULT_CHUNK_SIZE * 2 + 100;
  const src = new Uint8Array(total);
  for (let i = 0; i < total; i++) {
    src[i] = i % 251;
  }
  const sink = new RecordingSink();
  const written: number = writeInChunks(src.buffer, sink);
  // 注意：断言 closed 必须在调用方 close 之前检查
  eq('writeInChunks 自己不 close sink（close 时机由调用方定）', sink.closed, 0);
  sink.close();

  eq('返回值 = 总字节数', written, total);
  eq('2.5 块 → 3 次 write', sink.chunks.length, 3);
  eq('总字节数一致', sink.total(), total);
  eq('调用方 close 后只 +1', sink.closed, 1);

  // 拼接后逐字节一致
  const joined = new Uint8Array(sink.total());
  let off = 0;
  for (const c of sink.chunks) {
    joined.set(c, off);
    off += c.length;
  }
  let bad = -1;
  for (let i = 0; i < total; i++) {
    if (joined[i] !== src[i]) {
      bad = i;
      break;
    }
  }
  ok(`拼接内容逐字节正确（首个不符=${bad}）`, bad === -1);
  ok('每片都是独立副本（可安全异步消费）', sink.chunks[0].buffer !== sink.chunks[1].buffer);
}

// ---------------------------------------------------------------- 4. 边界：空内容 / 恰好一块 / 一块多一字节
{
  const empty = new RecordingSink();
  eq('空内容 → 返回 0', writeInChunks(new ArrayBuffer(0), empty), 0);
  eq('空内容 → 不写任何片', empty.chunks.length, 0);

  const one = new RecordingSink();
  writeInChunks(new ArrayBuffer(DEFAULT_CHUNK_SIZE), one);
  eq('恰好一块 → 1 次 write', one.chunks.length, 1);

  const over = new RecordingSink();
  writeInChunks(new ArrayBuffer(DEFAULT_CHUNK_SIZE + 1), over);
  eq('一块多一字节 → 2 次 write', over.chunks.length, 2);
  eq('第二片只有 1 字节', over.chunks[1].length, 1);
}

// ---------------------------------------------------------------- 5. 自定义分片大小
{
  const sink = new RecordingSink();
  writeInChunks(new ArrayBuffer(100), sink, 30);
  eq('100 字节按 30 分片 → 4 次', sink.chunks.length, 4);
  eq('最后一片 10 字节', sink.chunks[3].length, 10);
}

console.log(`\n=== 结果：${pass} passed, ${fails.length} failed ===`);
if (fails.length > 0) {
  for (const f of fails) {
    console.log('  FAIL ' + f);
  }
  throw new Error('chunked-sink 断言失败：' + fails.length);
}
