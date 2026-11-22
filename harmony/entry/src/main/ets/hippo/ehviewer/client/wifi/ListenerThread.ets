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

import { ConnectThread } from './ConnectThread';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/wifi/ListenerThread.java
 * （inventory S0115，88 行）
 *
 * 上游是 `Thread` + `ServerSocket(port)` + `setReuseAddress(true)` + `accept()` 循环：
 *   1. serverSocket 为 null 时**每次循环重试创建**（创建失败 continue，不停线程）
 *   2. accept() 成功后发 `DEVICE_CONNECTING`（obj = socket），然后 `sleep(500)`
 *      —— 这 500ms 是上游刻意留的「让对端准备好」的间隔，不是随手写的
 *   3. 退出时关闭 serverSocket
 *
 * 本层把「监听器」抽象成 `SocketAcceptor`（生产实现包 `@ohos.net.socket` 的 TCPSocket.listen/accept），
 * 循环逻辑保持形状一致，便于纯逻辑验证「重试创建」「accept 后 500ms」「退出关闭」三条行为。
 */
export class ListenerThread {
  /** 上游 `Thread.sleep(500)`。 */
  static readonly ACCEPT_INTERVAL_MS: number = 500;

  private _port: number;
  private _interrupted: boolean = false;
  private _socket: AcceptedLike | null = null;

  constructor(port: number) {
    this._port = port;
  }

  getPort(): number {
    return this._port;
  }

  getSocket(): AcceptedLike | null {
    return this._socket;
  }

  isInterrupted(): boolean {
    return this._interrupted;
  }

  interrupt(): void {
    this._interrupted = true;
  }

  /**
   * 对齐 run()：返回事件列表（DEVICE_CONNECTING 若干）+ 结束时关闭 server。
   * `sleeper` 与 `acceptor` 都是注入的，测试里用假实现验证「重试/间隔/关闭」。
   */
  runLoop(acceptor: SocketAcceptor, sleeper: Sleeper): ListenerEvent[] {
    const events: ListenerEvent[] = [];
    try {
      while (!this._interrupted) {
        if (!acceptor.isOpen()) {
          try {
            acceptor.open(this._port);
            acceptor.setReuseAddress(true);
          } catch (e) {
            continue; // 上游 continue：创建失败不退出线程
          }
        }
        let accepted: AcceptedLike | null = null;
        try {
          accepted = acceptor.accept();
        } catch (e) {
          if (this._interrupted) {
            break;
          }
          continue;
        }
        this._socket = accepted;
        events.push(ListenerEvent.ofConnecting(accepted));
        sleeper.sleep(ListenerThread.ACCEPT_INTERVAL_MS);
      }
      acceptor.close();
    } catch (e) {
      this._interrupted = true;
    }
    return events;
  }
}

/** accept 返回的连接（生产实现里包 `@ohos.net.socket` 的 socket 句柄）。 */
export interface AcceptedLike {
  readonly peer: string;
}

/** 监听器抽象（对应 `ServerSocket`）。 */
export interface SocketAcceptor {
  isOpen(): boolean;

  open(port: number): void;

  setReuseAddress(reuse: boolean): void;

  accept(): AcceptedLike | null;

  close(): void;
}

/** sleep 抽象（便于测试不真的等 500ms）。 */
export interface Sleeper {
  sleep(ms: number): void;
}

/** 监听事件（对应上游 `handler.sendMessage(DEVICE_CONNECTING, socket)`）。 */
export class ListenerEvent {
  what: number = 0;
  socket: AcceptedLike | null = null;

  static ofConnecting(socket: AcceptedLike | null): ListenerEvent {
    const e: ListenerEvent = new ListenerEvent();
    e.what = ConnectThread.DEVICE_CONNECTING;
    e.socket = socket;
    return e;
  }
}
