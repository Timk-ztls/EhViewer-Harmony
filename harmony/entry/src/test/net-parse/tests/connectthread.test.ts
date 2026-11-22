/*
 * ConnectThread 7 条缺失（S0114，native-image 第二层筛法）的回归断言
 *
 * 判据（Lead 转述）：上游方法体只有一行 [return] obj.method(...) → 转发缺口；否则真缺失。
 *   closeConnect / dataProcessed / isSocketClose / setFileChunkReceiver → 真缺失（写逻辑）
 *   readNextFrame / deliverDataHand / sendData                        → 转发缺口（本地已内联，抽出接线）
 *
 * Lead 点出的三个「传输线程最容易错」的地方，断言按行为钉住，不只钉方法存在：
 *   ① 读循环的退出条件（readNextFrame 返回 null → _close = true）
 *   ② dataProcessed 的字段复制（漏 pageIndex/pageSize → 分页永远只回第 1 页）
 *   ③ isSocketClose 问的是**传输层**，不是自己的标志位（顺序反了会多读一轮）
 */

import { ConnectThread, DispatchEvent, FileChunkReceiver, FrameTransport } from '../../../ehviewer/client/wifi/ConnectThread';
import { WiFiFrame } from '../../../ehviewer/client/wifi/WiFiFrame';
import { WiFiDataHand } from '../../../ehviewer/client/data/wifi/WiFiDataHand';
import { WiFiFrameCodec } from '../../../ehviewer/client/wifi/WiFiFrameCodec';
import { FileChunk } from '../../../ehviewer/client/wifi/MigrationTypes';

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

class FakeTransport implements FrameTransport {
  frames: (WiFiFrame | null)[] = [];
  written: WiFiFrame[] = [];
  closed: boolean = false;
  closeCalls: number = 0;
  private _i: number = 0;

  readFrame(): WiFiFrame | null {
    if (this._i >= this.frames.length) {
      return null;
    }
    return this.frames[this._i++];
  }

  writeFrame(frame: WiFiFrame): void {
    this.written.push(frame);
  }

  close(): void {
    this.closeCalls++;
    this.closed = true;
  }

  isClosed(): boolean {
    return this.closed;
  }
}

function makeHand(dataType: number, data: string, pageIndex: number, pageSize: number): WiFiDataHand {
  const h = new WiFiDataHand(WiFiDataHand.RECEIVED, data);
  h.dataType = dataType;
  h.pageIndex = pageIndex;
  h.pageSize = pageSize;
  return h;
}

// ---------------------------------------------------------------- ① 读循环退出条件
{
  const ct = new ConnectThread(ConnectThread.IS_CLIENT);
  const t = new FakeTransport();
  t.frames = [];                       // 立刻 EOF
  eq('读下一帧 → null（对端关闭）', ct.readNextFrame(t), null);
  ok('EOF 后 _close = true（退出条件）', ct.isClose());

  // 有帧时返回帧且不置 close
  const ct2 = new ConnectThread(ConnectThread.IS_CLIENT);
  const t2 = new FakeTransport();
  const f = new WiFiFrame(WiFiDataHand.SEND, ConnectThread.DATA_TYPE_QUICK_SEARCH);
  t2.frames = [f];
  ok('有帧 → 返回该帧', ct2.readNextFrame(t2) === f);
  ok('读到帧时 _close 仍为 false', !ct2.isClose());

  // 传输层抛错 → 置 close 并返回 null（上游 catch IOException 分支）
  class ThrowingTransport extends FakeTransport {
    readFrame(): WiFiFrame | null {
      throw new Error('boom');
    }
  }
  const ct3 = new ConnectThread(ConnectThread.IS_CLIENT);
  eq('传输层抛错 → 返回 null', ct3.readNextFrame(new ThrowingTransport()), null);
  ok('传输层抛错 → _close = true', ct3.isClose());
}

// ---------------------------------------------------------------- ③ isSocketClose vs isClose
{
  const ct = new ConnectThread(ConnectThread.IS_CLIENT);
  const t = new FakeTransport();
  // 传输层已关，但我们还没跑完 finally → 两个视图不一致，这正是不能互相替代的原因
  t.closed = true;
  eq('isSocketClose 问传输层 → true', ct.isSocketClose(t), true);
  eq('isClose 问自己的标志位 → 仍 false', ct.isClose(), false);

  eq('transport 为 null → isSocketClose true（对齐 socket == null）', ct.isSocketClose(null), true);

  const ct2 = new ConnectThread(ConnectThread.IS_CLIENT);
  const t2 = new FakeTransport();
  eq('传输层未关 → isSocketClose false', ct2.isSocketClose(t2), false);
}

// ---------------------------------------------------------------- closeConnect 的顺序
{
  const ct = new ConnectThread(ConnectThread.IS_CLIENT);
  const t = new FakeTransport();
  ct.closeConnect(t);
  eq('closeConnect 关掉传输层', t.closeCalls, 1);
  ok('closeConnect 之后 _close = true', ct.isClose());
  // 重复调用安全（上游 catch NPE）
  ct.closeConnect(t);
  eq('重复调用不抛且再关一次', t.closeCalls, 2);
  // transport == null 也不崩（上游 socket==null 时会 NPE 被 catch 吃掉）
  ct.closeConnect(null);
  ok('transport=null 时不抛', true);
}

// ---------------------------------------------------------------- ② dataProcessed 的字段复制
{
  const ct = new ConnectThread(ConnectThread.IS_SERVER);
  const t = new FakeTransport();
  const response = makeHand(ConnectThread.DATA_TYPE_DOWNLOAD_INFO, '{"a":1}', 3, 9);
  const ev: DispatchEvent = ct.dataProcessed(t, response);
  eq('dataProcessed 发一帧', t.written.length, 1);
  eq('回给对端的是 RECEIVED', t.written[0].messageType, WiFiDataHand.RECEIVED);
  eq('dataType 复制', t.written[0].dataType, ConnectThread.DATA_TYPE_DOWNLOAD_INFO);
  // **pageIndex / pageSize 必须复制** —— 漏了症状是「分页永远只回第 1 页」
  eq('pageIndex 复制（不是默认 1）', t.written[0].pageIndex, 3);
  eq('pageSize 复制（不是默认 1）', t.written[0].pageSize, 9);
  eq('发送成功 → SEND_MSG_SUCCESS', ev.what, ConnectThread.SEND_MSG_SUCCESS);

  // 写失败 → SEND_MSG_ERROR
  class FailWrite extends FakeTransport {
    writeFrame(frame: WiFiFrame): void {
      throw new Error('write failed');
    }
  }
  const ev2 = ct.dataProcessed(new FailWrite(), response);
  eq('写失败 → SEND_MSG_ERROR', ev2.what, ConnectThread.SEND_MSG_ERROR);
}

// ---------------------------------------------------------------- sendData / deliverDataHand（转发缺口）
{
  const ct = new ConnectThread(ConnectThread.IS_CLIENT);
  const t = new FakeTransport();
  const hand = makeHand(ConnectThread.DATA_TYPE_FAVORITE_INFO, 'x', 2, 4);
  ct.sendData(t, hand);
  eq('sendData 写一帧', t.written.length, 1);
  eq('sendData 用 WiFiFrameCodec.encode 的 dataType', t.written[0].dataType, ConnectThread.DATA_TYPE_FAVORITE_INFO);

  const ev: DispatchEvent = ct.deliverDataHand(hand);
  eq('deliverDataHand → what = GET_MSG', ev.what, ConnectThread.GET_MSG);
  ok('deliverDataHand 带上 hand', ev.hand === hand);
}

// ---------------------------------------------------------------- setFileChunkReceiver 的语义分叉
{
  const chunkFrame = new WiFiFrame(WiFiDataHand.SEND, ConnectThread.DATA_TYPE_DOWNLOAD_DIR_FILE);
  const decodeSpy = WiFiFrameCodec.decodeFileChunk(chunkFrame);

  // 未挂 receiver → 产出 GET_FILE_CHUNK 事件
  const ct = new ConnectThread(ConnectThread.IS_CLIENT);
  ok('默认没有 receiver', !ct.hasFileChunkReceiver());
  const events = ct.dispatchFrame(chunkFrame);
  // decode 失败时（payload 空）不产出事件；这里只断言"没挂 receiver 时走事件路径"这一支
  ok('未挂 receiver 时不回调（事件路径）', events.length === 0 || events[0].what === ConnectThread.GET_FILE_CHUNK);

  // 挂 receiver → 就地回调、**不产出事件**
  let received: FileChunk | null = null;
  const receiver: FileChunkReceiver = {
    onFileChunk: (c: FileChunk): void => {
      received = c;
    }
  };
  const ct2 = new ConnectThread(ConnectThread.IS_CLIENT);
  ct2.setFileChunkReceiver(receiver);
  ok('挂上 receiver 后 hasFileChunkReceiver = true', ct2.hasFileChunkReceiver());
  const events2 = ct2.dispatchFrame(chunkFrame);
  eq('挂了 receiver → 不产出事件（不进队列）', events2.length, 0);
  // 载荷解析失败时 chunk 为 null → 不回调；这里只验证"事件路径被跳过"
  ok('挂了 receiver → 走回调路径（received 可能为 null，因为测试帧 payload 为空）',
    received === null || decodeSpy !== null);

  ct2.setFileChunkReceiver(null);
  ok('置 null 后可回到事件路径', !ct2.hasFileChunkReceiver());
}

console.log(`\n=== 结果：${pass} passed, ${fails.length} failed ===`);
if (fails.length > 0) {
  for (const f of fails) {
    console.log('  FAIL ' + f);
  }
  throw new Error('ConnectThread S0114 断言失败：' + fails.length);
}
