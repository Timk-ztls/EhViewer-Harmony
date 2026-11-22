/*
 * DiskLruCache 的 LRU touch 断言（A-02）
 *
 * 为什么必须单独测：`contain()` / `editWithSequence()` 各补了"delete + set"两行，
 * 代码看上去对，但 **"touch 生效"只能通过 Map 的迭代顺序观测**（`_lruEntries` 是 private）。
 * 没有观测面就回到"改对了 vs 证明改对了"的分界线。
 *
 * 上游依据：`lruEntries` 是 `LinkedHashMap(0, 0.75f, **true**)`（accessOrder=true），
 * 所以 `get` / `contain` / `editWithSequence` 里的 `lruEntries.get(key)` 都会把 entry 移到 LRU 头部。
 */

import { touchLru, DiskLruCache, DiskLruCacheEditor, DiskLruCacheSnapshot, FaultHidingWriter } from '../../main/ets/hippo/beerbelly/DiskLruCache';
import { SimpleDiskCache, CacheOutputStreamPipe } from '../../main/ets/hippo/beerbelly/SimpleDiskCache';
import { BeerBelly, BeerBellyParams } from '../../main/ets/hippo/beerbelly/BeerBelly';
import { Util } from '../../main/ets/hippo/beerbelly/Util';
import { ByteSink } from '../../main/ets/hippo/streampipe/OutputStreamPipe';
import { InputStreamPipe } from '../../main/ets/hippo/streampipe/InputStreamPipe';
import fs from '@ohos.file.fs';

interface FsTestHook {
  __activeFdCount?: () => number;
}

function activeFds(): number {
  const h: FsTestHook = fs as unknown as FsTestHook;
  return h.__activeFdCount !== undefined ? h.__activeFdCount() : 0;
}

class TestBeerBelly extends BeerBelly<string> {
  constructor(params: BeerBellyParams) {
    super(params);
  }

  sizeOf(key: string, value: string): number {
    return value.length;
  }

  memoryEntryAdded(value: string): void {
  }

  memoryEntryRemoved(evicted: boolean, key: string, oldValue: string | null, newValue: string | null): void {
  }

  read(isPipe: InputStreamPipe, hardware: boolean): string | null {
    return null;
  }

  write(os: ByteSink, value: string): boolean {
    return false;
  }
}

let pass = 0;
const fails: string[] = [];

function eq(name: string, got: unknown, want: unknown): void {
  const g = JSON.stringify(got);
  const w = JSON.stringify(want);
  if (g === w) {
    pass++;
  } else {
    fails.push(`${name}\n    got  ${g}\n    want ${w}`);
  }
}

function ok(name: string, cond: boolean): void {
  eq(name, cond, true);
}

function keys(map: Map<string, number>): string[] {
  const out: string[] = [];
  map.forEach((v: number, k: string) => {
    out.push(k);
  });
  return out;
}

function main(): void {
  // ① 初始插入序（Map 保持插入序 → 这同时是"我们的 Map 确实有序"的前提断言）
  {
    const m: Map<string, number> = new Map<string, number>();
    m.set('A', 1);
    m.set('B', 2);
    eq('初始插入序 = [A, B]', keys(m), ['A', 'B']);
  }

  // ② touch('A') 之后 → [B, A]（= contain()/get() 的 LRU 效果）
  {
    const m: Map<string, number> = new Map<string, number>();
    m.set('A', 1);
    m.set('B', 2);
    touchLru(m, 'A');
    eq('touch(A) → [B, A]（A 移到最新端）', keys(m), ['B', 'A']);
  }

  // ③ 反证：不 touch 就仍是 [A, B] —— 这条把"touch 是必要的"钉住
  {
    const m: Map<string, number> = new Map<string, number>();
    m.set('A', 1);
    m.set('B', 2);
    // 不调用 touchLru
    eq('不 touch → 仍是 [A, B]（反证：touch 不是 no-op）', keys(m), ['A', 'B']);
  }

  // ④ touch 不存在的 key 是 no-op（不能凭空插入）
  {
    const m: Map<string, number> = new Map<string, number>();
    m.set('A', 1);
    touchLru(m, 'ZZ');
    eq('touch 不存在的 key → 不插入', keys(m), ['A']);
    eq('touch 不存在的 key → 长度不变', m.size, 1);
  }

  // ⑤ 值不被 touch 改变（只改顺序，不改内容）
  {
    const m: Map<string, number> = new Map<string, number>();
    m.set('A', 11);
    m.set('B', 22);
    touchLru(m, 'A');
    eq('touch 后 A 的值不变', m.get('A'), 11);
    eq('touch 后 B 的值不变', m.get('B'), 22);
  }

  // ⑥ 连续 touch 同一 key → 顺序稳定（幂等，不会反复挪动出意外结果）
  {
    const m: Map<string, number> = new Map<string, number>();
    m.set('A', 1);
    m.set('B', 2);
    m.set('C', 3);
    touchLru(m, 'A');
    touchLru(m, 'A');
    eq('连续 touch(A) 两次 → [B, C, A]', keys(m), ['B', 'C', 'A']);
  }

  // ⑦ 淘汰顺序的直接体现：最旧的 key 排在最前（trimToSize 会先删它）
  {
    const m: Map<string, number> = new Map<string, number>();
    m.set('A', 1);
    m.set('B', 2);
    m.set('C', 3);
    touchLru(m, 'A');            // A 变成最新 → 最旧是 B
    eq('最旧的是 B（淘汰先删它）', keys(m)[0], 'B');
    touchLru(m, 'B');
    eq('touch(B) 后最旧的是 C', keys(m)[0], 'C');
  }

  // ⑧ P1 #8 (F-2) + #12 (statSync(fd))：DiskLruCache.get 在 journalRebuildRequired 时先 touchLru
  {
    const baseFds: number = activeFds();
    const dir: string = '/tmp/m42_lru_f2';
    fs.mkdirSync(dir, true);
    const cache: DiskLruCache = DiskLruCache.open(dir, 1, 1, 100);
    const putStr = (k: string, s: string): void => {
      const ed: DiskLruCacheEditor | null = cache.edit(k);
      ok(`edit(${k}) 非空`, ed !== null);
      if (ed !== null) {
        ed.set(0, s);
        ed.commit();
      }
    };
    const fiftyA: string = 'A'.repeat(50);
    const fiftyB: string = 'B'.repeat(50);
    const fiftyC: string = 'C'.repeat(50);
    putStr('k1', fiftyA);
    putStr('k2', fiftyB);
    // 刷够 redundantOps，第 2000 次 get('k1') 时 journalRebuildRequired() 为 true，验证 k1 被提前续命
    for (let i = 0; i < 1998; i++) {
      const snap: DiskLruCacheSnapshot | null = cache.get('k2');
      if (snap !== null) {
        snap.close();
      }
    }
    const snapK1: DiskLruCacheSnapshot | null = cache.get('k1');
    ok('P1 #8/#12: k1 snapshot 非空且 statSync(fd) 可读全文',
      snapK1 !== null && snapK1.getString(0) === fiftyA);
    if (snapK1 !== null) {
      snapK1.close();
    }
    // 放入 k3(50B) 触发淘汰：最旧的应是 k2，k1 必须存活
    putStr('k3', fiftyC);
    const snapAfter1: DiskLruCacheSnapshot | null = cache.get('k1');
    const snapAfter2: DiskLruCacheSnapshot | null = cache.get('k2');
    ok('P1 #8: 触发 rebuild/淘汰后热点 k1 仍保留', snapAfter1 !== null);
    eq('P1 #8: 最久未用的 k2 被淘汰', snapAfter2, null);
    if (snapAfter1 !== null) {
      snapAfter1.close();
    }
    cache.close();
    eq('P1 #5/#12: DiskLruCache 操作结束后无 FD 泄漏', activeFds(), baseFds);
  }

  // ⑨ P1 #5 & P0 #3: FaultHidingWriter 幂等关闭；CacheOutputStreamPipe close 前关 writer + abort 丢弃脏写
  {
    const preInitFds: number = activeFds();
    const sdc: SimpleDiskCache = new SimpleDiskCache('/tmp/m42_sdc_pipe', 4096);
    const baseFds: number = activeFds(); // SimpleDiskCache 持有 1 个 journal 句柄
    const wPipe = sdc.getOutputStreamPipe('valid_key');
    wPipe.obtain();
    const sink = wPipe.open();
    const payload: ArrayBuffer = new Uint8Array([1, 2, 3, 4]).buffer;
    sink.write(payload);
    wPipe.close();
    wPipe.release();
    ok('P1 #5: 正常写入后 valid_key 命中', sdc.contain('valid_key'));
    eq('P1 #5: CacheOutputStreamPipe.close 关闭了 FaultHidingWriter（无 FD 泄漏）', activeFds(), baseFds);

    // 对 FaultHidingWriter 显式二次 close() 必须幂等不报错
    const cPipe = sdc.getOutputStreamPipe('valid_key');
    cPipe.obtain();
    const w: FaultHidingWriter = cPipe.open() as FaultHidingWriter;
    w.write(new Uint8Array([9, 9]).buffer);
    w.close();
    w.close(); // 第二次 close 不得抛 EBADF 或污染 editor
    (cPipe as CacheOutputStreamPipe).abort(); // 失败中止：保留原先 4 字节 valid_key
    cPipe.release();
    eq('P0 #3/#5: abort() 后无 FD 泄漏', activeFds(), baseFds);

    const rd = sdc.getInputStreamPipe('valid_key');
    ok('P0 #3: abort() 未覆盖已有有效缓存', rd !== null);
    if (rd !== null) {
      rd.obtain();
      const f: fs.File = rd.open();
      const st: fs.Stat = fs.statSync(f.fd);
      eq('P0 #3: 原 valid_key 长度仍为 4（未被 2 字节脏写污染）', st.size, 4);
      rd.close();
      rd.release();
    }

    // abort 一个全新的 key → 不得提交 0 字节进缓存
    const badPipe: CacheOutputStreamPipe = sdc.getOutputStreamPipe('bad_zero') as CacheOutputStreamPipe;
    badPipe.obtain();
    badPipe.open();
    badPipe.abort();
    badPipe.release();
    eq('P0 #3: 全新 key abort() 后不得 contain 0 字节', sdc.contain('bad_zero'), false);
    eq('P0 #3: 全程结束后无 FD 泄漏', activeFds(), baseFds);
    const innerCache: DiskLruCache | null = sdc.diskCacheOrNull();
    if (innerCache !== null) {
      innerCache.close();
    }
    eq('P0 #3: 关闭底层 DiskLruCache 后全部 FD 归零', activeFds(), preInitFds);
  }

  // ⑩ P1 #9 (F-4) & P2 #13 (F-5): Util.deleteContents 删含子目录缓存；SimpleDiskCache.clear() 语义
  {
    const rootDir: string = '/tmp/m42_util_del';
    const subDir: string = rootDir + '/nested_dir';
    const deepFile: string = subDir + '/inner.bin';
    fs.mkdirSync(rootDir, true);
    fs.mkdirSync(subDir, true);
    const f: fs.File = fs.openSync(deepFile, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE);
    fs.writeSync(f.fd, new Uint8Array([1, 2, 3]).buffer);
    fs.closeSync(f);
    Util.deleteContents(rootDir);
    eq('P1 #9 (F-4): deleteContents 清空含子目录的目录内容', fs.listFileSync(rootDir), []);

    const sdcClear: SimpleDiskCache = new SimpleDiskCache('/tmp/m42_sdc_clear', 4096);
    fs.mkdirSync('/tmp/m42_sdc_clear/sub_artifact', true);
    const okClear: boolean = sdcClear.clear();
    eq('P1 #9 / P2 #13: 含子目录的 SimpleDiskCache.clear() 返回 true', okClear, true);
    eq('P2 #13: 子目录已被清掉', fs.accessSync('/tmp/m42_sdc_clear/sub_artifact'), false);
  }

  // ⑪ P2 #14 (F-6): BeerBelly 缺失缓存查询方法返回 -1（不是 0）
  {
    const memOnlyParams: BeerBellyParams = new BeerBellyParams();
    memOnlyParams.hasMemoryCache = true;
    memOnlyParams.memoryCacheMaxSize = 1024;
    memOnlyParams.hasDiskCache = false;
    const memOnly: TestBeerBelly = new TestBeerBelly(memOnlyParams);
    eq('P2 #14: 无磁盘缓存时 diskSize() = -1', memOnly.diskSize(), -1);
    eq('P2 #14: 无磁盘缓存时 diskMaxSize() = -1', memOnly.diskMaxSize(), -1);

    const diskOnlyParams: BeerBellyParams = new BeerBellyParams();
    diskOnlyParams.hasMemoryCache = false;
    diskOnlyParams.hasDiskCache = true;
    diskOnlyParams.diskCacheDir = '/tmp/m42_bb_diskonly';
    diskOnlyParams.diskCacheMaxSize = 4096;
    const diskOnly: TestBeerBelly = new TestBeerBelly(diskOnlyParams);
    eq('P2 #14: 无内存缓存时 memorySize() = -1', diskOnly.memorySize(), -1);
    eq('P2 #14: 无内存缓存时 memoryMaxSize() = -1', diskOnly.memoryMaxSize(), -1);
  }

  if (fails.length > 0) {
    console.log(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.log('  - ' + f);
    }
    throw new Error('disklru-lru test failed');
  }
  console.log(`✓ disklru-lru: ${pass} 条断言全部通过`);
}

main();
