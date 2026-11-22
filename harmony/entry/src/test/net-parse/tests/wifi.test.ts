// wifi 三件（ConnectThread 分派 / ListenerThread 循环 / MigrationHelper 纯逻辑）测试
//
// 这些类在上游都是 Thread + Socket，本层把「协议分派」与「循环语义」拆成可测的纯逻辑：
//   dispatchFrame：客户端/服务端 × messageType 过滤 × 5 种 dataType
//   runLoop：连接 → 读帧 → 对端关闭（EOF）→ 断开；sendFrame 成功/失败两条
//   listener：open 失败 continue、accept 后 sleep 500ms、退出关闭
//   migration：parseGidFromDirname / filterFilesNeeded（MD5 忽略大小写）/ FileWriteState

import { ConnectThread, DispatchEvent, FrameTransport } from '../wifi/ConnectThread';
import { ListenerThread, ListenerEvent, SocketAcceptor, AcceptedLike, Sleeper } from '../wifi/ListenerThread';
import { WiFiDownloadMigrationHelper, FileWriteState, MigrationFileSystem } from '../wifi/WiFiDownloadMigrationHelper';
import { WiFiFrameCodec } from '../wifi/WiFiFrameCodec';
import { WiFiFrame } from '../wifi/WiFiFrame';
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

// ---------- 假 transport ----------
class FakeTransport implements FrameTransport {
  frames: (WiFiFrame | null)[] = [];
  written: WiFiFrame[] = [];
  closed: boolean = false;
  failWrite: boolean = false;
  private _i: number = 0;

  readFrame(): WiFiFrame | null {
    if (this._i >= this.frames.length) {
      return null; // 对端关闭
    }
    return this.frames[this._i++];
  }

  /** 对齐 `Socket.isClosed()`：`isSocketClose()` 问的是传输层，不是 ConnectThread 的标志位。 */
  isClosed(): boolean {
    return this.closed;
  }

  writeFrame(frame: WiFiFrame): void {
    if (this.failWrite) {
      throw new Error('write failed');
    }
    this.written.push(frame);
  }

  close(): void {
    this.closed = true;
  }
}

// ---------- 1. 客户端分派 ----------
{
  const client = new ConnectThread(ConnectThread.IS_CLIENT);

  // messageType != SEND → 丢弃（返回空）
  const notSend = new WiFiFrame(WiFiDataHand.RECEIVED, ConnectThread.DATA_TYPE_QUICK_SEARCH, 0, 0, 0, new ArrayBuffer(0));
  eq('客户端忽略非 SEND 帧', client.dispatchFrame(notSend).length, 0);

  // 普通 JSON 消息 → GET_MSG
  const hand = new WiFiDataHand(WiFiDataHand.SEND, '{"quick_search":"abc"}');
  hand.dataType = ConnectThread.DATA_TYPE_QUICK_SEARCH;
  const msgFrame = WiFiFrameCodec.encode(hand);
  const ev1 = client.dispatchFrame(msgFrame);
  eq('客户端 SEND 普通帧 → 1 个事件', ev1.length, 1);
  eq('事件 what = GET_MSG', ev1[0].what, ConnectThread.GET_MSG);
  eq('事件携带 hand.dataType', (ev1[0].hand as WiFiDataHand).dataType, ConnectThread.DATA_TYPE_QUICK_SEARCH);

  // 文件块 → GET_FILE_CHUNK
  const chunkFrame = WiFiFrameCodec.encodeFileChunk(7, 'a.jpg', 'md5a', 0, 2,
    new Uint8Array([1, 2]).buffer as ArrayBuffer, false, ConnectThread.DATA_TYPE_DOWNLOAD_DIR_FILE);
  const ev2 = client.dispatchFrame(chunkFrame);
  eq('客户端文件块 → GET_FILE_CHUNK', ev2[0].what, ConnectThread.GET_FILE_CHUNK);
  eq('事件 chunk.name', (ev2[0].chunk as { name: string }).name, 'a.jpg');

  // 文件块但 payload 坏 → 不出事件
  const badChunk = new WiFiFrame(WiFiDataHand.SEND, ConnectThread.DATA_TYPE_DOWNLOAD_DIR_FILE, 0, 0, 0,
    new Uint8Array([1]).buffer as ArrayBuffer);
  eq('坏文件块 → 无事件', client.dispatchFrame(badChunk).length, 0);
}

// ---------- 2. 服务端分派 ----------
{
  const server = new ConnectThread(ConnectThread.IS_SERVER);

  const manifestFrame = WiFiFrameCodec.encodeManifest(5, 'dir', [new FileMeta()],
    1, 2, ConnectThread.DATA_TYPE_DOWNLOAD_DIR_MANIFEST);
  const ev1 = server.dispatchFrame(manifestFrame);
  eq('服务端 manifest → GET_DIR_MANIFEST', ev1[0].what, ConnectThread.GET_DIR_MANIFEST);

  const ackFrame = WiFiFrameCodec.encodeAck(5, 'dir', ['a'], ConnectThread.DATA_TYPE_DOWNLOAD_DIR_ACK);
  const ev2 = server.dispatchFrame(ackFrame);
  eq('服务端 ack → GET_DIR_ACK', ev2[0].what, ConnectThread.GET_DIR_ACK);

  // 服务端收到普通 JSON → GET_MSG
  const hand = new WiFiDataHand(WiFiDataHand.SEND, '{"download_info":"x"}');
  hand.dataType = ConnectThread.DATA_TYPE_DOWNLOAD_INFO;
  const ev3 = server.dispatchFrame(WiFiFrameCodec.encode(hand));
  eq('服务端普通帧 → GET_MSG', ev3[0].what, ConnectThread.GET_MSG);

  // 服务端收到 manifest 但 payload 坏 → 无事件
  const badManifest = new WiFiFrame(WiFiDataHand.SEND, ConnectThread.DATA_TYPE_DOWNLOAD_DIR_MANIFEST,
    0, 0, 0, new Uint8Array([1, 2]).buffer as ArrayBuffer);
  eq('坏 manifest → 无事件', server.dispatchFrame(badManifest).length, 0);
}

// ---------- 3. runLoop：连接→帧→对端关闭 ----------
{
  const client = new ConnectThread(ConnectThread.IS_CLIENT);
  const t = new FakeTransport();
  const hand = new WiFiDataHand(WiFiDataHand.SEND, '{"a":"b"}');
  t.frames = [WiFiFrameCodec.encode(hand)]; // 之后 readFrame 返回 null = 对端关闭
  const events = client.runLoop(t);
  eq('runLoop 事件数（CONNECTED + MSG + DISCONNECTED）', events.length, 3);
  eq('首个事件 DEVICE_CONNECTED', events[0].what, ConnectThread.DEVICE_CONNECTED);
  eq('中间事件 GET_MSG', events[1].what, ConnectThread.GET_MSG);
  eq('末个事件 DEVICE_DISCONNECTED', events[2].what, ConnectThread.DEVICE_DISCONNECTED);
  ok('对端关闭后 close=true', client.isClose());
}

// ---------- 4. sendFrame 成功/失败 ----------
{
  const client = new ConnectThread(ConnectThread.IS_CLIENT);
  const t = new FakeTransport();
  const frame = new WiFiFrame(2, 1002, 0, 0, 0, new ArrayBuffer(0));
  eq('sendFrame 成功 → SEND_MSG_SUCCESS', client.sendFrame(t, frame).what, ConnectThread.SEND_MSG_SUCCESS);
  eq('帧已写入', t.written.length, 1);
  t.failWrite = true;
  eq('sendFrame 失败 → SEND_MSG_ERROR', client.sendFrame(t, frame).what, ConnectThread.SEND_MSG_ERROR);
}

// ---------- 5. ListenerThread 循环 ----------
{
  class FakeAcceptor implements SocketAcceptor {
    openCalls: number = 0;
    failOpenTimes: number = 0;
    openState: boolean = false;
    acceptQueue: (AcceptedLike | null)[] = [];
    closed: boolean = false;
    reuse: boolean = false;

    isOpen(): boolean {
      return this.openState;
    }

    open(port: number): void {
      this.openCalls++;
      if (this.failOpenTimes > 0) {
        this.failOpenTimes--;
        throw new Error('bind failed');
      }
      this.openState = true;
    }

    setReuseAddress(reuse: boolean): void {
      this.reuse = reuse;
    }

    accept(): AcceptedLike | null {
      const next = this.acceptQueue.length > 0 ? this.acceptQueue.shift() : null;
      return next === undefined ? null : next;
    }

    close(): void {
      this.closed = true;
      this.openState = false;
    }
  }

  class FakeSleeper implements Sleeper {
    slept: number[] = [];
    onSleep: (() => void) | null = null;

    sleep(ms: number): void {
      this.slept.push(ms);
      if (this.onSleep !== null) {
        const cb = this.onSleep;
        this.onSleep = null;
        cb();
      }
    }
  }

  const acceptor = new FakeAcceptor();
  acceptor.acceptQueue = [{ peer: 'A' }, { peer: 'B' }];
  const sleeper = new FakeSleeper();
  const listener = new ListenerThread(12345);

  // 第二次 sleep 时中断 → 退出循环
  sleeper.onSleep = null;
  const events: ListenerEvent[] = [];
  // 手动驱动：第一次 accept 后 sleep，第二次 accept 后 sleep 时中断
  let sleepCount = 0;
  const drivingSleeper: Sleeper = {
    sleep: (ms: number): void => {
      sleeper.slept.push(ms);
      sleepCount++;
      if (sleepCount >= 2) {
        listener.interrupt();
      }
    }
  };
  const out = listener.runLoop(acceptor, drivingSleeper);
  eq('listener 收到 2 个连接事件', out.length, 2);
  eq('事件 what = DEVICE_CONNECTING', out[0].what, ConnectThread.DEVICE_CONNECTING);
  eq('accept 间隔 500ms', sleeper.slept[0], ListenerThread.ACCEPT_INTERVAL_MS);
  ok('setReuseAddress(true) 被调用', acceptor.reuse);
  ok('退出时关闭 server socket', acceptor.closed);
  eq('serverSocket 只 open 一次', acceptor.openCalls, 1);

  // open 失败 → continue 重试（不退出）
  const acceptor2 = new FakeAcceptor();
  acceptor2.failOpenTimes = 1;
  acceptor2.acceptQueue = [{ peer: 'X' }];
  const listener2 = new ListenerThread(1234);
  let n = 0;
  const s2: Sleeper = {
    sleep: (): void => {
      n++;
      listener2.interrupt();
    }
  };
  const out2 = listener2.runLoop(acceptor2, s2);
  eq('open 失败后重试成功（open 调用 2 次）', acceptor2.openCalls, 2);
  eq('重试后仍能 accept 到连接', out2.length, 1);
}

// ---------- 6. MigrationHelper 纯逻辑 ----------
{
  eq('parseGidFromDirname 正常', WiFiDownloadMigrationHelper.parseGidFromDirname('1234567-title'), 1234567);
  eq('parseGidFromDirname 无 dash', WiFiDownloadMigrationHelper.parseGidFromDirname('1234567'), -1);
  eq('parseGidFromDirname dash 在首位', WiFiDownloadMigrationHelper.parseGidFromDirname('-title'), -1);
  eq('parseGidFromDirname 非数字', WiFiDownloadMigrationHelper.parseGidFromDirname('abc-title'), -1);

  eq('bytesToHex', WiFiDownloadMigrationHelper.bytesToHex(new Uint8Array([0, 15, 255])), '000fff');

  class FakeFs implements MigrationFileSystem {
    files: Map<string, { md5: string; size: number; dir: boolean }> = new Map();

    // 契约：返回条目名（不是完整路径）
    list(dir: string): string[] {
      return Array.from(this.files.keys())
        .filter((k) => k.indexOf(dir + '/') === 0 && k.substring(dir.length + 1).indexOf('/') < 0)
        .map((k) => k.substring(dir.length + 1));
    }

    isDirectory(path: string): boolean {
      const v = this.files.get(path);
      return v !== undefined && v.dir;
    }

    isFile(path: string): boolean {
      const v = this.files.get(path);
      return v !== undefined && !v.dir;
    }

    size(path: string): number {
      const v = this.files.get(path);
      return v === undefined ? 0 : v.size;
    }

    computeMd5Hex(path: string): string | null {
      const v = this.files.get(path);
      return v === undefined ? null : v.md5;
    }

    resolveFileInGallery(galleryDir: string, relPath: string): string | null {
      const full = galleryDir + '/' + relPath;
      return this.files.has(full) ? full : null;
    }
  }

  const fs = new FakeFs();
  fs.files.set('/root', { md5: '', size: 0, dir: true });
  fs.files.set('/root/111-a', { md5: '', size: 0, dir: true });
  fs.files.set('/root/noname', { md5: '', size: 0, dir: true });
  fs.files.set('/root/111-a/1.jpg', { md5: 'AAAA', size: 10, dir: false });
  fs.files.set('/root/111-a/sub', { md5: '', size: 0, dir: true });
  fs.files.set('/root/111-a/2.jpg', { md5: 'bbbb', size: 20, dir: false });
  fs.files.set('/root/111-a/sub/3.jpg', { md5: 'cccc', size: 30, dir: false });

  const dirs = WiFiDownloadMigrationHelper.scanGalleryDirs(fs, '/root');
  eq('scanGalleryDirs 只保留 gid 合法目录', dirs.length, 1);
  eq('scanGalleryDirs gid', dirs[0].gid, 111);
  eq('scanGalleryDirs dirname', dirs[0].dirname, '111-a');

  const scanned = WiFiDownloadMigrationHelper.scanGalleryDir(fs, '/root/111-a');
  eq('scanGalleryDir 含子目录文件（3 个）', scanned.length, 3);
  ok('scanGalleryDir 子目录路径带前缀',
    scanned.some((m) => m.name === 'sub/3.jpg'));
  eq('scanGalleryDir size', scanned.filter((m) => m.name === '2.jpg')[0].size, 20);

  // MD5 忽略大小写：本地 AAAA vs 远端 aaaa → 不需要
  const needed = WiFiDownloadMigrationHelper.filterFilesNeeded(fs, '/root/111-a', [
    { name: '1.jpg', md5: 'aaaa', size: 10 } as FileMeta,
    { name: '9.jpg', md5: 'dddd', size: 9 } as FileMeta
  ]);
  eq('filterFilesNeeded 大小写不同视为相同', needed, ['9.jpg']);

  ok('verifyFileMd5 忽略大小写',
    WiFiDownloadMigrationHelper.verifyFileMd5(fs, '/root/111-a/1.jpg', 'aaaa'));
  ok('verifyFileMd5 不匹配 → false',
    !WiFiDownloadMigrationHelper.verifyFileMd5(fs, '/root/111-a/1.jpg', 'zzzz'));
  ok('verifyFileMd5 文件不存在 → false',
    !WiFiDownloadMigrationHelper.verifyFileMd5(fs, '/root/none.jpg', 'aaaa'));

  const state = new FileWriteState();
  state.addWritten('a.jpg', 100);
  state.addWritten('a.jpg', 50);
  eq('FileWriteState 累计', state.getWritten('a.jpg'), 150);
  state.clear('a.jpg');
  eq('FileWriteState clear 后为 0', state.getWritten('a.jpg'), 0);

  eq('FILE_CHUNK_SIZE = 256KiB', WiFiDownloadMigrationHelper.FILE_CHUNK_SIZE, 262144);
}

// ---------- 汇总 ----------
console.log(`\n=== 结果：${pass} passed, ${fail} failed ===`);
if (fail > 0) {
  for (const f of failures) {
    console.log('  FAIL ' + f);
  }
  throw new Error('wifi 断言失败：' + fail);
}
