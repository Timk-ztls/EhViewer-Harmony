/*
 * F-3 回归测试：readSync 的 offset 语义（`docs/f3-readsync-ruling.md`）
 *
 * `@ohos.file.fs` 的 `ReadOptions.offset` = 「**文件内**起点（filePointer + offset）」，
 * **不是** Java `read(byte[] b, int off, int len)` 的「缓冲区下标」。
 *
 * 踩坑形态：把「缓冲区进度」当 offset 传进去
 * ```ts
 * while (offset < size) { fs.readSync(fd, buf, { offset: offset, length: size - offset }); … }
 * ```
 * 后果：`offset=0` 时恰好对（**所以小块文件/第一个测试块是绿的**），
 *       `offset>0` 时读的是**文件中间**、且只读 `size-offset` 字节。
 *
 * 本文件必须用**大于单次读块**（64 KB）的文件才能触发第二块，
 * 且测试桩按 SDK 语义建模（否则这个 bug 永远测不出来 —— 见 run.ps1 的 fs shim 注释）。
 */

import { Util } from '../../../beerbelly/Util';
import { RequestBody } from '../../../okhttp/RequestBody';
import fileIo from '@ohos.file.fs';

declare const require: (name: string) => Object;
const nodeFs: Object = require('fs');

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

interface FsLike {
  mkdtempSync(prefix: string): string;
  writeFileSync(path: string, data: Uint8Array): void;
  rmSync(path: string, opts: Object): void;
}
const fsx: FsLike = nodeFs as Object as FsLike;

const root: string = fsx.mkdtempSync('f3-readsync-');

/** 造一个可校验内容的文件：第 i 字节 = i % 251（质数，跨块不容易巧合相等）。 */
function makeFile(name: string, size: number): string {
  const path: string = root + '/' + name;
  const data = new Uint8Array(size);
  for (let i = 0; i < size; i++) {
    data[i] = i % 251;
  }
  fsx.writeFileSync(path, data);
  return path;
}

function checkBytes(name: string, buf: ArrayBuffer, size: number): void {
  const u8 = new Uint8Array(buf);
  eq(`${name} 长度`, u8.length, size);
  let bad = -1;
  for (let i = 0; i < size; i++) {
    if (u8[i] !== i % 251) {
      bad = i;
      break;
    }
  }
  ok(`${name} 内容逐字节正确（首个不符位置=${bad}）`, bad === -1);
}

// ---------------------------------------------------------------- 1. 小于单块（这类一直是绿的）
{
  const path: string = makeFile('small.bin', 1000);
  const text: string = Util.readFullyText(path);
  eq('小文件读全（长度）', text.length, 1000);
}

// ---------------------------------------------------------------- 2. **大于单块** —— 这里才会踩 F-3
{
  // 64 KB 块 × 3 块 + 零头
  const size = 64 * 1024 * 3 + 123;
  const path: string = makeFile('big.bin', size);

  const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
  let buf: ArrayBuffer;
  try {
    buf = Util.readFullyTo(file.fd, size);
  } finally {
    fileIo.closeSync(file);
  }
  checkBytes('Util.readFullyTo 大文件', buf, size);

  // 同一个文件走 readFullyText（解码成 latin1 风格会乱，只校验长度与首尾）
  const file2 = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
  let raw: ArrayBuffer;
  try {
    raw = Util.readFullyTo(file2.fd, size);
  } finally {
    fileIo.closeSync(file2);
  }
  eq('二次读长度一致', raw.byteLength, size);
}

// ---------------------------------------------------------------- 3. RequestBody 的文件读取路径
{
  const size = 64 * 1024 * 2 + 7;
  const path: string = makeFile('body.bin', size);
  const body: RequestBody = RequestBody.createFromFile(null, path);
  const buf: ArrayBuffer = body.bytes();
  checkBytes('FileRequestBody.bytes 大文件', buf, size);
  eq('contentLength 与文件大小一致', body.contentLength(), size);
  // 缓存验证：第二次拿同一对象
  ok('第二次 bytes() 命中缓存（引用相等）', body.bytes() === buf);
}

// ---------------------------------------------------------------- 4. 增量读（模拟大文件流式写）
{
  const size = 64 * 1024 + 500;
  const path: string = makeFile('stream.bin', size);
  const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
  const chunk = new ArrayBuffer(8192);
  let total = 0;
  let firstBad = -1;
  try {
    let n: number = 0;
    while ((n = fileIo.readSync(file.fd, chunk, { length: chunk.byteLength })) > 0) {
      const u8 = new Uint8Array(chunk, 0, n);
      for (let i = 0; i < n; i++) {
        if (u8[i] !== (total + i) % 251) {
          firstBad = total + i;
          break;
        }
      }
      total += n;
      if (firstBad >= 0) {
        break;
      }
    }
  } finally {
    fileIo.closeSync(file);
  }
  eq('流式读总字节数', total, size);
  ok('流式读逐块内容正确', firstBad === -1);
}

try {
  fsx.rmSync(root, { recursive: true, force: true });
} catch (e) {
  // 清理失败不影响断言结果
}

console.log(`\n=== 结果：${pass} passed, ${fails.length} failed ===`);
if (fails.length > 0) {
  for (const f of fails) {
    console.log('  FAIL ' + f);
  }
  throw new Error('F-3 readSync 断言失败：' + fails.length);
}
