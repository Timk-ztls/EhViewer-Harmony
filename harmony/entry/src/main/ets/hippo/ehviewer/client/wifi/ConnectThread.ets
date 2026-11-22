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

import { WiFiDataHand } from '../data/wifi/WiFiDataHand';
import { DirAck, DirManifest, FileChunk } from './MigrationTypes';
import { WiFiFrame } from './WiFiFrame';
import { WiFiFrameCodec } from './WiFiFrameCodec';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/wifi/ConnectThread.java
 * （inventory S0114，264 行）
 *
 * 上游是 `Thread` + `Socket` + `Handler` 三者耦合：run() 里读帧、dispatchFrame() 里按
 * `connectKind`（IS_SERVER / IS_CLIENT）与 `dataType` 分派、再 `handler.sendMessage(...)`。
 *
 * 本层的拆法（协议逻辑可测，线程/套接字只做接线）：
 *   - **常量表**逐字照搬（DEVICE_* / SEND_MSG_* / GET_* / IS_* / DATA_TYPE_* / *_KEY）
 *   - `dispatchFrame(frame)` —— **纯函数**，返回「要发给 UI 的事件列表」而不是直接 sendMessage
 *   - `runLoop()` —— 让调用方提供「下一帧」，循环直到 close；socket 读写由 `FrameTransport` 注入
 *
 * 这样 `dispatchFrame` 的每条分支（客户端/服务端 × 5 种 dataType × messageType 过滤）
 * 都能在纯逻辑测试里断言，不需要真机也不需要 socket。
 */
export class ConnectThread {
  static readonly DEVICE_CONNECTING: number = 1;
  static readonly DEVICE_CONNECTED: number = 2;
  static readonly DEVICE_DISCONNECTED: number = 3;
  static readonly SEND_MSG_SUCCESS: number = 4;
  static readonly SEND_MSG_ERROR: number = 5;
  static readonly GET_MSG: number = 6;
  static readonly GET_FILE_CHUNK: number = 7;
  static readonly GET_DIR_MANIFEST: number = 8;
  static readonly GET_DIR_ACK: number = 9;

  static readonly IS_SERVER: number = 101;
  static readonly IS_CLIENT: number = 102;

  static readonly DATA_TYPE_QUICK_SEARCH: number = 1001;
  static readonly QUICK_SEARCH_DATA_KEY: string = 'quick_search';
  static readonly DATA_TYPE_DOWNLOAD_INFO: number = 1002;
  static readonly DOWNLOAD_INFO_DATA_KEY: string = 'download_info';
  static readonly DATA_TYPE_DOWNLOAD_LABEL: number = 1003;
  static readonly DOWNLOAD_LABEL_KEY: string = 'download_label';
  static readonly DATA_TYPE_FAVORITE_INFO: number = 1004;
  static readonly FAVORITE_INFO_DATA_KEY: string = 'favorite_info';
  static readonly DATA_TYPE_DOWNLOAD_DIR_MANIFEST: number = 1005;
  static readonly DATA_TYPE_DOWNLOAD_DIR_ACK: number = 1006;
  static readonly DATA_TYPE_DOWNLOAD_DIR_FILE: number = 1007;

  private _connectKind: number = ConnectThread.IS_CLIENT;
  private _close: boolean = false;
  /** 文件块同步接收器（对齐上游 olatile FileChunkReceiver）。 */
  private _fileChunkReceiver: FileChunkReceiver | null = null;

  constructor(connectKind: number) {
    this._connectKind = connectKind;
  }

  isClose(): boolean {
    return this._close;
  }

  // ==========================================================================
  // native-image 第二层筛法报的 7 条（S0114）
  // 判据（Lead 转述）：上游方法体只有一行 [return] obj.method(...) → 转发缺口；否则真缺失。
  //   closeConnect / dataProcessed / isSocketClose / setFileChunkReceiver → **真缺失**（要写逻辑）
  //   readNextFrame / deliverDataHand / sendData                        → **转发缺口**（本地已内联，抽出接线）
  // ==========================================================================

  /**
   * 对齐 `setFileChunkReceiver(receiver)`（**真缺失**）。
   *
   * 上游注释：*在读取线程同步处理文件块，避免主线程队列堆积大对象*。
   * 设了 receiver 后 `dispatchFrame` 的分支**不再产出事件**，而是就地回调 —— 这是语义分叉，
   * 不是可选优化：迁移大文件时一帧几百 KB，走队列会把主线程堆满。
   */
  setFileChunkReceiver(receiver: FileChunkReceiver | null): void {
    this._fileChunkReceiver = receiver;
  }

  /** 测试用：当前是否挂了文件块接收器。 */
  hasFileChunkReceiver(): boolean {
    return this._fileChunkReceiver !== null;
  }

  /**
   * 对齐 `isSocketClose()`（**真缺失**，且**语义与 `isClose()` 不同**）。
   *
   * 上游问的是**传输层**：`socket == null → true`、否则 `socket.isClosed()`。
   * 我们的 `isClose()` 问的是**自己的标志位**。两者不能互相替代：
   * 对端先 close、我们还没走到 `finally` 时，传输层已关但标志位还是 false ——
   * 读循环若只看标志位会**多读一轮**（上游靠 `isInterrupted() && !close` + 传输层异常兜住）。
   */
  isSocketClose(transport: FrameTransport | null): boolean {
    if (transport === null) {
      return true;
    }
    return transport.isClosed();
  }

  /**
   * 对齐 `closeConnect()`（**真缺失**）。
   *
   * 上游顺序：`socket.close()` → `interrupt()` → `close = true`。
   * **顺序不能换**：先关流才能让阻塞在读上的线程抛出来；先置标志再关流会让读线程继续阻塞。
   * 这里 `transport.close()` 之后再置 `_close = true`，并且**重复调用安全**（上游 catch NPE）。
   */
  closeConnect(transport: FrameTransport | null): void {
    if (transport !== null) {
      try {
        transport.close();
      } catch (e) {
        // 上游 `catch (IOException | NullPointerException)` 只记日志：关闭失败不应打断上层清理
      }
    }
    this._close = true;
  }

  /**
   * 对齐 `readNextFrame(inputStream)`（**转发缺口**：本地 runLoop 内联了等价逻辑）。
   *
   * 语义：读到帧就返回；EOF / IO 错 → **置 `_close` 并返回 null**（上游同一分支处理两类异常，
   * 区别只在是否记 Analytics —— 我们无 Analytics，两者都只置位）。
   */
  readNextFrame(transport: FrameTransport): WiFiFrame | null {
    let frame: WiFiFrame | null;
    try {
      frame = transport.readFrame();
    } catch (e) {
      this._close = true;
      return null;
    }
    if (frame === null) {
      // 上游 EOFException 分支：对端关闭连接
      this._close = true;
      return null;
    }
    return frame;
  }

  /** 对齐 `deliverDataHand(hand)`（**转发缺口**）：产出一条 `GET_MSG` 事件。 */
  deliverDataHand(hand: WiFiDataHand): DispatchEvent {
    return DispatchEvent.ofMessage(hand);
  }

  /**
   * 对齐 `sendData(dataHand)`（**转发缺口**）：编码后发送，返回 SEND_MSG_SUCCESS / ERROR。
   *
   * 上游是新开线程发送（`new Thread(() -> sendData(...)).start()`），避免阻塞调用方；
   * 本层 `sendFrame` 是同步的、由调用方决定线程模型（`runLoop` 外通常就在 UI 线程外）。
   */
  sendData(transport: FrameTransport, hand: WiFiDataHand): DispatchEvent {
    return this.sendFrame(transport, WiFiFrameCodec.encode(hand));
  }

  /**
   * 对齐 `dataProcessed(response)`（**真缺失**）。
   *
   * 把业务结果包成 `RECEIVED` 帧回给对方，**逐字段复制**：
   * `dataType` / `data` / `pageIndex` / `pageSize`。
   * 漏抄 `pageIndex/pageSize` 的症状是「分页传输永远只回第 1 页」（对端按 part 判定）。
   */
  dataProcessed(transport: FrameTransport, response: WiFiDataHand): DispatchEvent {
    const reply: WiFiDataHand = new WiFiDataHand(WiFiDataHand.RECEIVED);
    reply.dataType = response.dataType;
    reply.setData(response.getData());
    reply.pageIndex = response.pageIndex;
    reply.pageSize = response.pageSize;
    return this.sendData(transport, reply);
  }

  /** 对齐 run()：连接成功 → 循环读帧 → 断开。事件通过返回列表交给调用方发。 */
  runLoop(transport: FrameTransport): DispatchEvent[] {
    const events: DispatchEvent[] = [];
    events.push(DispatchEvent.simple(ConnectThread.DEVICE_CONNECTED));
    while (!this._close) {
      let frame: WiFiFrame | null = null;
      try {
        frame = transport.readFrame();
      } catch (e) {
        frame = null;
      }
      if (this._close) {
        break;
      }
      if (frame === null) {
        // 上游：EOF/IO 错 → close = true（对端关闭连接）
        this._close = true;
        break;
      }
      const dispatched: DispatchEvent[] = this.dispatchFrame(frame);
      for (let i = 0; i < dispatched.length; i++) {
        events.push(dispatched[i]);
      }
    }
    this._close = true;
    events.push(DispatchEvent.simple(ConnectThread.DEVICE_DISCONNECTED));
    return events;
  }

  /**
   * 对齐 dispatchFrame(WiFiFrame)。
   *
   * 分派规则（逐条照搬）：
   *   客户端：只收 messageType == SEND 的帧；
   *     DOWNLOAD_DIR_FILE → GET_FILE_CHUNK（解不出 chunk 就什么都不发）
   *   服务端：DOWNLOAD_DIR_MANIFEST → GET_DIR_MANIFEST；
   *     DOWNLOAD_DIR_ACK → GET_DIR_ACK；
   *   其它 dataType → GET_MSG（带 WiFiDataHand）
   */
  dispatchFrame(frame: WiFiFrame): DispatchEvent[] {
    const events: DispatchEvent[] = [];
    if (this._connectKind === ConnectThread.IS_CLIENT) {
      if (frame.messageType !== WiFiDataHand.SEND) {
        return events;
      }
      if (frame.dataType === ConnectThread.DATA_TYPE_DOWNLOAD_DIR_FILE) {
        const chunk: FileChunk | null = WiFiFrameCodec.decodeFileChunk(frame);
        if (chunk !== null) {
          const receiver: FileChunkReceiver | null = this._fileChunkReceiver;
          if (receiver !== null) {
            // 上游：挂了 receiver 就**就地处理、不进队列**（避免主线程堆积大对象）→ 不产出事件
            receiver.onFileChunk(chunk);
          } else {
            events.push(DispatchEvent.ofFileChunk(chunk));
          }
        }
        return events;
      }
    } else {
      // 服务端
      if (frame.dataType === ConnectThread.DATA_TYPE_DOWNLOAD_DIR_MANIFEST) {
        const manifest: DirManifest | null = WiFiFrameCodec.decodeManifest(frame);
        if (manifest !== null) {
          events.push(DispatchEvent.ofDirManifest(manifest));
        }
        return events;
      }
      if (frame.dataType === ConnectThread.DATA_TYPE_DOWNLOAD_DIR_ACK) {
        const ack: DirAck | null = WiFiFrameCodec.decodeAck(frame);
        if (ack !== null) {
          events.push(DispatchEvent.ofDirAck(ack));
        }
        return events;
      }
    }
    // 其余一律当普通 JSON 消息
    const hand: WiFiDataHand = WiFiFrameCodec.decodeDataHand(frame);
    events.push(DispatchEvent.ofMessage(hand));
    return events;
  }

  /** 对齐 sendFrame：写帧成功后发 SEND_MSG_SUCCESS，失败发 SEND_MSG_ERROR。 */
  sendFrame(transport: FrameTransport, frame: WiFiFrame): DispatchEvent {
    try {
      transport.writeFrame(frame);
      return DispatchEvent.simple(ConnectThread.SEND_MSG_SUCCESS);
    } catch (e) {
      return DispatchEvent.simple(ConnectThread.SEND_MSG_ERROR);
    }
  }

  close(): void {
    this._close = true;
  }
}

/**
 * 帧收发抽象（对应上游的 `Socket.getInputStream()/getOutputStream()`）。
 * 生产实现包 `@ohos.net.socket` 的 TCPSocket/TLSSocket；测试用内存实现。
 */
export interface FrameTransport {
  /** 读下一帧；对端关闭时返回 null（对应 EOFException 的处理）。 */
  readFrame(): WiFiFrame | null;

  writeFrame(frame: WiFiFrame): void;

  /** 是否已关闭（对齐 Socket.isClosed()）。isSocketClose() 用它、**不用** ConnectThread 自己的标志位。 */
  isClosed(): boolean;

  close(): void;
}

/** dispatchFrame 的产出（对应上游 handler.sendMessage 的 message.what + obj）。 */
export class DispatchEvent {
  what: number = 0;
  hand: WiFiDataHand | null = null;
  chunk: FileChunk | null = null;
  manifest: DirManifest | null = null;
  ack: DirAck | null = null;

  static simple(what: number): DispatchEvent {
    const e: DispatchEvent = new DispatchEvent();
    e.what = what;
    return e;
  }

  static ofMessage(hand: WiFiDataHand): DispatchEvent {
    const e: DispatchEvent = new DispatchEvent();
    e.what = ConnectThread.GET_MSG;
    e.hand = hand;
    return e;
  }

  static ofFileChunk(chunk: FileChunk): DispatchEvent {
    const e: DispatchEvent = new DispatchEvent();
    e.what = ConnectThread.GET_FILE_CHUNK;
    e.chunk = chunk;
    return e;
  }

  static ofDirManifest(manifest: DirManifest): DispatchEvent {
    const e: DispatchEvent = new DispatchEvent();
    e.what = ConnectThread.GET_DIR_MANIFEST;
    e.manifest = manifest;
    return e;
  }

  static ofDirAck(ack: DirAck): DispatchEvent {
    const e: DispatchEvent = new DispatchEvent();
    e.what = ConnectThread.GET_DIR_ACK;
    e.ack = ack;
    return e;
  }
}
/**
 * 文件块同步接收器（对齐上游 `ConnectThread.FileChunkReceiver`）。
 *
 * 为什么是"同步"：迁移大文件时一帧几百 KB，走 Handler 队列会把主线程堆满；
 * 上游在**读取线程**里直接回调，落盘与否由接收方决定。
 */
export interface FileChunkReceiver {
  onFileChunk(chunk: FileChunk): void;
}