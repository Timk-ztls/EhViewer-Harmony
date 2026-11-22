/*
 * download-sync 接手批单测：WiFi 传书接收端（S0275）的纯逻辑
 *
 * 钉住五条"写错也像是对的"语义：
 *   1. intToIp 是**小端**（低位在前）—— 顺序写反得到 `1.0.168.192` 这种看似合理的地址
 *   2. 没有下载根目录 / 建目录失败 → **仍要回空 ack**，否则发送端等不到 ack 会卡死
 *   3. manifest.pageIndex == 1 → 完成计数归零
 *   4. chunkIndex == 0 → offset=0 + 清状态 + **删旧文件**（否则追加出半个新半个旧）
 *   5. lastChunk → 校验 MD5，不匹配**删文件**并提示失败
 *
 * 运行：pwsh -File harmony/entry/src/test/ui-scene/run.ps1
 */

import {
  WiFiClientActivity, ReceiveKind, ChunkPlan, ManifestPlan, PersistBatch
} from '../../main/ets/hippo/ehviewer/ui/wifi/WiFiClientActivity';
import { FileWriteState } from '../../main/ets/hippo/ehviewer/client/wifi/WiFiDownloadMigrationHelper';
import {
  MigrationFileSystem
} from '../../main/ets/hippo/ehviewer/client/wifi/WiFiDownloadMigrationHelper';
import { DirManifest, FileChunk, FileMeta } from '../../main/ets/hippo/ehviewer/client/wifi/MigrationTypes';
import { MigrationWriteSink, MigrationPersistSink } from '../../main/ets/hippo/ehviewer/ui/wifi/WiFiClientActivity';
import { ConnectThread } from '../../main/ets/hippo/ehviewer/client/wifi/ConnectThread';

let pass: number = 0;
const fails: string[] = [];

function eq(name: string, got: Object | null, want: Object | null): void {
  const g: string = JSON.stringify(got);
  const w: string = JSON.stringify(want);
  if (g === w) {
    pass++;
  } else {
    fails.push(`${name}\n    got  ${g}\n    want ${w}`);
  }
}

function ok(name: string, cond: boolean): void {
  if (cond) {
    pass++;
  } else {
    fails.push(`${name}  (want true)`);
  }
}

// ---------------------------------------------------------------- 假实现

/** 内存文件系统（只读侧，对齐 MigrationFileSystem）。 */
class FakeFs implements MigrationFileSystem {
  files: Map<string, string> = new Map<string, string>();
  md5Of: Map<string, string> = new Map<string, string>();

  list(dir: string): string[] {
    const out: string[] = [];
    this.files.forEach((_v: string, k: string) => {
      if (k.startsWith(dir + '/') && k.indexOf('/', dir.length + 1) === -1) {
        out.push(k.substring(dir.length + 1));
      }
    });
    return out;
  }

  isDirectory(_path: string): boolean {
    return false;
  }

  isFile(path: string): boolean {
    return this.files.has(path);
  }

  size(path: string): number {
    const v: string | undefined = this.files.get(path);
    return v === undefined ? 0 : v.length;
  }

  computeMd5Hex(path: string): string | null {
    const v: string | undefined = this.md5Of.get(path);
    return v === undefined ? null : v;
  }

  resolveFileInGallery(galleryDir: string, relPath: string): string | null {
    const p: string = `${galleryDir}/${relPath}`;
    return this.files.has(p) ? p : null;
  }
}

/** 写侧假实现：记录调用，便于断言"删了没有/写到哪个偏移"。 */
class FakeSink implements MigrationWriteSink {
  rootAvailable: boolean = true;
  ensureOk: boolean = true;
  deleted: string[] = [];
  writes: string[] = [];

  hasDownloadRoot(): boolean {
    return this.rootAvailable;
  }

  ensureGalleryDir(gid: number, dirname: string): string | null {
    return this.ensureOk ? `/downloads/${gid}_${dirname}` : null;
  }

  deleteFile(path: string): boolean {
    this.deleted.push(path);
    return true;
  }

  writeChunk(galleryDir: string, name: string, data: Uint8Array, offset: number): boolean {
    this.writes.push(`${galleryDir}/${name}@${offset}+${data.byteLength}`);
    return true;
  }

  resolveFile(galleryDir: string, relPath: string): string | null {
    return `${galleryDir}/${relPath}`;
  }
}

class FakePersist implements MigrationPersistSink {
  quick: string[] = [];
  labels: string[] = [];
  infos: string[] = [];
  favs: string[] = [];

  takeOverQuickSearchList(jsonTexts: string[]): void {
    this.quick = jsonTexts;
  }

  addDownloadLabel(label: string): void {
    this.labels.push(label);
  }

  addDownloadInfo(jsonText: string): void {
    this.infos.push(jsonText);
  }

  putLocalFavorite(jsonText: string): void {
    this.favs.push(jsonText);
  }
}

// ---------------------------------------------------------------- intToIp

function testIntToIp(): void {
  // Android `WifiInfo.getIpAddress()` 返回的 int 里**最低字节是第一段**：
  // 对 192.168.1.5 返回 0x0501A8C0（0xC0=192 在最低位），所以 intToIp 要按 低位→高位 拼。
  eq('192.168.1.5 对应 int 0x0501A8C0 → 192.168.1.5',
    WiFiClientActivity.intToIp(0x0501A8C0), '192.168.1.5');
  eq('192.168.43.1 对应 int 0x012BA8C0 → 192.168.43.1',
    WiFiClientActivity.intToIp(0x012BA8C0), '192.168.43.1');
  eq('0 → 0.0.0.0', WiFiClientActivity.intToIp(0), '0.0.0.0');
  eq('全 1 → 255.255.255.255', WiFiClientActivity.intToIp(0xFFFFFFFF), '255.255.255.255');
  eq('10.0.0.7 对应 int 0x0700000A → 10.0.0.7',
    WiFiClientActivity.intToIp(0x0700000A), '10.0.0.7');
  // 反例：如果按"高位在前"拼，0x0501A8C0 会得到 5.1.168.192 —— 这是错的写法，专门钉住
  ok('顺序写反会得到 5.1.168.192（不是我们要的）',
    WiFiClientActivity.intToIp(0x0501A8C0) !== '5.1.168.192');
}

// ---------------------------------------------------------------- 键与分派

function testKeysAndDispatch(): void {
  eq('目录键', WiFiClientActivity.dirKey(42, 'd'), '42:d');
  eq('文件键 = key/name', WiFiClientActivity.fileKey('42:d', '001.jpg'), '42:d/001.jpg');

  // 四个业务类型 + 两个迁移类型
  eq('1001 → QUICK_SEARCH', WiFiClientActivity.receiveKindOf(ConnectThread.DATA_TYPE_QUICK_SEARCH),
    ReceiveKind.QUICK_SEARCH);
  eq('1002 → DOWNLOAD_INFO', WiFiClientActivity.receiveKindOf(ConnectThread.DATA_TYPE_DOWNLOAD_INFO),
    ReceiveKind.DOWNLOAD_INFO);
  eq('1003 → DOWNLOAD_LABEL', WiFiClientActivity.receiveKindOf(ConnectThread.DATA_TYPE_DOWNLOAD_LABEL),
    ReceiveKind.DOWNLOAD_LABEL);
  eq('1004 → FAVORITE_INFO', WiFiClientActivity.receiveKindOf(ConnectThread.DATA_TYPE_FAVORITE_INFO),
    ReceiveKind.FAVORITE_INFO);
  eq('1005 → DIR_MANIFEST', WiFiClientActivity.receiveKindOf(ConnectThread.DATA_TYPE_DOWNLOAD_DIR_MANIFEST),
    ReceiveKind.DIR_MANIFEST);
  eq('1007 → DIR_FILE_CHUNK', WiFiClientActivity.receiveKindOf(ConnectThread.DATA_TYPE_DOWNLOAD_DIR_FILE),
    ReceiveKind.DIR_FILE_CHUNK);
  // 未知必须仍然可识别为 UNKNOWN（要回 dataProcessed，不能丢）
  eq('9999 → UNKNOWN（不丢弃）', WiFiClientActivity.receiveKindOf(9999), ReceiveKind.UNKNOWN);

  eq('数据键：收藏', WiFiClientActivity.dataKeyOf(ReceiveKind.FAVORITE_INFO),
    ConnectThread.FAVORITE_INFO_DATA_KEY);
  eq('数据键：下载信息', WiFiClientActivity.dataKeyOf(ReceiveKind.DOWNLOAD_INFO),
    ConnectThread.DOWNLOAD_INFO_DATA_KEY);
  eq('数据键：未知 → 空串', WiFiClientActivity.dataKeyOf(ReceiveKind.UNKNOWN), '');
}

// ---------------------------------------------------------------- planChunk

function chunkOf(index: number, total: number, len: number, last: boolean, gid: number = 9): FileChunk {
  const c: FileChunk = new FileChunk();
  c.gid = gid;
  c.name = 'a.jpg';
  c.fileMd5 = 'md5';
  c.chunkIndex = index;
  c.chunkTotal = total;
  c.data = new ArrayBuffer(len);
  c.lastChunk = last;
  return c;
}

function testPlanChunk(): void {
  const ignored: ChunkPlan = WiFiClientActivity.planChunk(false, 999, chunkOf(0, 2, 10, false));
  eq('无 dirname → ignore（上游直接 return）', ignored.ignore, true);

  const first: ChunkPlan = WiFiClientActivity.planChunk(true, 500, chunkOf(0, 3, 10, false));
  eq('首块：offset 归零（不是沿用已写 500）', first.offset, 0);
  eq('首块：删旧文件', first.deleteExisting, true);
  eq('首块：清写入状态', first.clearState, true);
  eq('首块：本块字节数', first.writtenBytes, 10);
  eq('非末块：不校验 MD5', first.verifyMd5, false);

  const mid: ChunkPlan = WiFiClientActivity.planChunk(true, 500, chunkOf(1, 3, 10, false));
  eq('中间块：按已写字节续写', mid.offset, 500);
  eq('中间块：不删文件', mid.deleteExisting, false);

  const last: ChunkPlan = WiFiClientActivity.planChunk(true, 500, chunkOf(2, 3, 10, true));
  eq('末块：校验 MD5', last.verifyMd5, true);
  eq('末块：完成后清状态 + 计数', last.finishFile, true);

  // 空块（data 长度 0）
  const empty: ChunkPlan = WiFiClientActivity.planChunk(true, 0, chunkOf(0, 1, 0, true));
  eq('空块：writtenBytes = 0', empty.writtenBytes, 0);
  eq('空块：仍是末块', empty.verifyMd5, true);
}

// ---------------------------------------------------------------- 进度

function testProgress(): void {
  eq('第 0 个不刷', WiFiClientActivity.progressTextIfDue(0), null);
  eq('第 9 个不刷', WiFiClientActivity.progressTextIfDue(9), null);
  const t = WiFiClientActivity.progressTextIfDue(10);
  eq('第 10 个刷一次（资源名）', t === null ? null : t.resKey, 'wifi_download_dir_files_progress');
  eq('第 10 个带上计数', t === null ? null : t.args, [10]);
  eq('第 11 个不刷', WiFiClientActivity.progressTextIfDue(11), null);
  eq('第 20 个刷', WiFiClientActivity.progressTextIfDue(20) === null ? null : 20, 20);
}

// ---------------------------------------------------------------- manifest

function manifestOf(gid: number, dirname: string, names: string[], pageIndex: number,
  pageSize: number): DirManifest {
  const m: DirManifest = new DirManifest();
  m.gid = gid;
  m.dirname = dirname;
  m.pageIndex = pageIndex;
  m.pageSize = pageSize;
  for (const n of names) {
    const f: FileMeta = new FileMeta();
    f.name = n;
    f.md5 = 'm_' + n;
    f.size = 3;
    m.files.push(f);
  }
  return m;
}

function testManifest(): void {
  const fs: FakeFs = new FakeFs();
  const sink: FakeSink = new FakeSink();
  const client: WiFiClientActivity = new WiFiClientActivity();

  // ① 没有下载根目录 → 空 ack（关键：不能"什么都不做"）
  sink.rootAvailable = false;
  const noRoot: ManifestPlan = client.onDirManifest(manifestOf(1, 'd1', ['a'], 1, 1), sink, fs);
  eq('无根目录 → 回空 ack', noRoot.sendEmptyAck, true);
  eq('无根目录 → needed 为空', noRoot.needed, []);
  eq('无根目录 → 不推进度', noRoot.progress, null);

  // ② 建目录失败 → 空 ack
  sink.rootAvailable = true;
  sink.ensureOk = false;
  const noDir: ManifestPlan = client.onDirManifest(manifestOf(1, 'd1', ['a'], 1, 1), sink, fs);
  eq('建目录失败 → 回空 ack', noDir.sendEmptyAck, true);

  // ③ 正常：缺的文件进 ack（目标目录为空 → 全部需要）
  sink.ensureOk = true;
  const ok: ManifestPlan = client.onDirManifest(manifestOf(2, 'd2', ['a.jpg', 'b.jpg'], 1, 2), sink, fs);
  eq('正常 → 不回空 ack', ok.sendEmptyAck, false);
  eq('目标为空 → 两个都要', ok.needed, ['a.jpg', 'b.jpg']);
  eq('pageIndex==1 → 重置完成计数', ok.resetCompleted, true);
  eq('进度文案资源名', ok.progress === null ? null : ok.progress.resKey,
    'wifi_download_dir_manifest_received');
  eq('进度参数（dirname/pageIndex/pageSize/已存在/需要）',
    ok.progress === null ? null : ok.progress.args, ['d2', 1, 2, 0, 2]);

  // ④ pageIndex != 1 → 不重置
  const page2: ManifestPlan = client.onDirManifest(manifestOf(2, 'd2', [], 2, 2), sink, fs);
  eq('pageIndex==2 → 不重置', page2.resetCompleted, false);

  // ⑤ 目标已有同名且 MD5 相同 → 不需要（filterFilesNeeded 的语义）
  const fs2: FakeFs = new FakeFs();
  fs2.files.set('/downloads/3_d3/a.jpg', 'abc');
  fs2.md5Of.set('/downloads/3_d3/a.jpg', 'm_a.jpg');
  fs2.files.set('/downloads/3_d3/b.jpg', 'xyz');
  fs2.md5Of.set('/downloads/3_d3/b.jpg', 'different');
  const sink2: FakeSink = new FakeSink();
  const client2: WiFiClientActivity = new WiFiClientActivity();
  const dedup: ManifestPlan = client2.onDirManifest(manifestOf(3, 'd3', ['a.jpg', 'b.jpg'], 1, 1), sink2, fs2);
  eq('已存在且 MD5 一致 → 不再要；不一致 → 仍要', dedup.needed, ['b.jpg']);
}

// ---------------------------------------------------------------- applyFileChunk

function testApplyChunk(): void {
  const fs: FakeFs = new FakeFs();
  const sink: FakeSink = new FakeSink();
  const client: WiFiClientActivity = new WiFiClientActivity();

  // 先收 manifest 建立 gid→dirname 映射
  client.onDirManifest(manifestOf(9, 'd9', ['a.jpg'], 1, 1), sink, fs);

  // 首块：删旧文件 + 从 0 写
  sink.deleted = [];
  sink.writes = [];
  const mismatch1: boolean = client.applyFileChunk(chunkOf(0, 2, 10, false), sink, fs);
  eq('首块不报 MD5 失败', mismatch1, false);
  eq('首块删了旧文件', sink.deleted.length, 1);
  eq('首块从 offset 0 写', sink.writes, ['/downloads/9_d9/a.jpg@0+10']);

  // 中间块：续写
  sink.writes = [];
  client.applyFileChunk(chunkOf(1, 2, 5, true), sink, fs);
  eq('末块按已写 10 续写', sink.writes, ['/downloads/9_d9/a.jpg@10+5']);
  eq('完成后计数 +1', client.completedFiles(), 1);

  // MD5 不匹配 → 删文件 + 返回 true（提示失败）
  const fs2: FakeFs = new FakeFs();
  fs2.md5Of.set('/downloads/9_d9/a.jpg', 'expected');
  const sink2: FakeSink = new FakeSink();
  const client2: WiFiClientActivity = new WiFiClientActivity();
  client2.onDirManifest(manifestOf(9, 'd9', ['a.jpg'], 1, 1), sink2, fs2);
  const chunk: FileChunk = chunkOf(0, 1, 4, true);
  chunk.fileMd5 = 'not-expected';
  sink2.deleted = [];
  const bad: boolean = client2.applyFileChunk(chunk, sink2, fs2);
  eq('MD5 不匹配 → 返回 true（要提示失败）', bad, true);
  eq('MD5 不匹配 → 删掉坏文件', sink2.deleted.length >= 1, true);

  // 没有 dirname 的块 → 直接忽略
  const stray: FileChunk = chunkOf(0, 1, 4, true, 12345);
  const sink3: FakeSink = new FakeSink();
  sink3.writes = [];
  client2.applyFileChunk(stray, sink3, fs2);
  eq('未知 gid → 不写任何东西', sink3.writes, []);
}

// ---------------------------------------------------------------- 落地分派

function testPersist(): void {
  const sink: FakePersist = new FakePersist();

  const labels: PersistBatch | null = WiFiClientActivity.planPersist(ReceiveKind.DOWNLOAD_LABEL, ['L1', 'L2']);
  WiFiClientActivity.persist(labels as PersistBatch, sink);
  eq('标签逐条写入', sink.labels, ['L1', 'L2']);

  const infos: PersistBatch | null = WiFiClientActivity.planPersist(ReceiveKind.DOWNLOAD_INFO, ['{"gid":1}']);
  WiFiClientActivity.persist(infos as PersistBatch, sink);
  eq('下载信息写入', sink.infos, ['{"gid":1}']);

  const favs: PersistBatch | null = WiFiClientActivity.planPersist(ReceiveKind.FAVORITE_INFO, ['{"gid":2}']);
  WiFiClientActivity.persist(favs as PersistBatch, sink);
  eq('收藏写入', sink.favs, ['{"gid":2}']);

  const quick: PersistBatch | null = WiFiClientActivity.planPersist(ReceiveKind.QUICK_SEARCH, ['{"name":"x"}']);
  WiFiClientActivity.persist(quick as PersistBatch, sink);
  eq('书签整表接管', sink.quick, ['{"name":"x"}']);

  eq('未知类型 → null 批次', WiFiClientActivity.planPersist(ReceiveKind.UNKNOWN, []), null);
}

// ---------------------------------------------------------------- 入口

function main(): void {
  testIntToIp();
  testKeysAndDispatch();
  testPlanChunk();
  testProgress();
  testManifest();
  testApplyChunk();
  testPersist();

  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('download-sync wifi client test failed');
  }
  console.log(`✓ download-sync WiFi 接收端批: ${pass} 条断言全部通过`);
}

main();
