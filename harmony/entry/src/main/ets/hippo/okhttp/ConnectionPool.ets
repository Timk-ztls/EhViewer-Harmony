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

/**
 * okhttp3.ConnectionPool 等价层（语义模拟，不是真连接池）。
 *
 * 上游配置（EhApplication.getOkHttpClient）：
 *   new ConnectionPool(10, 5, TimeUnit.MINUTES)
 * 即「最多 10 个空闲连接，每个保活 5 分钟」。
 *
 * 鸿蒙侧的现实：@ohos.net.http 的连接池在系统侧，三方无法调参；@ohos.net.socket 由我们
 * 自己持有 socket，可以真正实现 keep-alive 复用。因此：
 *   - socket 引擎（HTTP/1.1）真正按 idle=10 / keepAlive=5min 复用 socket；
 *   - @ohos.net.http 引擎只把这两个数字作为「按 host 的并发闸门」参数
 *     （maxIdleConnections 作为同 host 最大并发，keepAlive 周期用于统计清理），
 *     实际复用交给系统栈。
 * 差异已在 MR 里登记（行为等价证据章节）。
 */
export interface PoolLike {
  acquire(host: string): void;

  release(host: string): void;
}

/** 池中可关闭的连接句柄，避免连接被淘汰或超限时泄露 FD。 */
export interface CloseableSocket {
  close(): void;
}

class IdleSocketEntry {
  readonly key: string;
  readonly conn: CloseableSocket | null;
  readonly since: number;

  constructor(key: string, conn: CloseableSocket | null, since: number) {
    this.key = key;
    this.conn = conn;
    this.since = since;
  }
}

export class ConnectionPool implements PoolLike {
  private readonly _maxIdleConnections: number;
  private readonly _keepAliveDurationNanos: number;
  private _idle: IdleSocketEntry[] = [];
  private readonly _inFlight: Map<string, number> = new Map<string, number>();

  /** 对齐 new ConnectionPool(int maxIdleConnections, long keepAliveDuration, TimeUnit) —— 单位已归一为毫秒。 */
  constructor(maxIdleConnections: number, keepAliveDurationMinutes: number) {
    this._maxIdleConnections = maxIdleConnections;
    this._keepAliveDurationNanos = keepAliveDurationMinutes * 60 * 1000;
  }

  maxIdleConnections(): number {
    return this._maxIdleConnections;
  }

  keepAliveDurationMs(): number {
    return this._keepAliveDurationNanos;
  }

  /** 连接被放回池子（socket 引擎调用）；超出上限时按最旧优先淘汰并关闭 FD。 */
  putIdle(key: string, conn: CloseableSocket | null = null): void {
    this.evictExpired();
    if (this._maxIdleConnections <= 0) {
      ConnectionPool.safeClose(conn);
      return;
    }
    while (this._idle.length >= this._maxIdleConnections) {
      const oldest: IdleSocketEntry = this._idle.shift() as IdleSocketEntry;
      ConnectionPool.safeClose(oldest.conn);
    }
    this._idle.push(new IdleSocketEntry(key, conn, Date.now()));
  }

  /** 尝试取一条空闲连接对象（LIFO 优先复用最近活跃的连接）。 */
  takeIdleConn(key: string): CloseableSocket | null {
    this.evictExpired();
    for (let i = this._idle.length - 1; i >= 0; i--) {
      if (this._idle[i].key === key) {
        const entry: IdleSocketEntry = this._idle.splice(i, 1)[0];
        return entry.conn;
      }
    }
    return null;
  }

  /** 尝试取一条空闲连接标记（保留旧签名兼容）。 */
  takeIdle(key: string): boolean {
    this.evictExpired();
    for (let i = this._idle.length - 1; i >= 0; i--) {
      if (this._idle[i].key === key) {
        this._idle.splice(i, 1);
        return true;
      }
    }
    return false;
  }

  /** 从空闲池移除已断开的指定连接并释放句柄。 */
  removeIdleConn(conn: CloseableSocket): void {
    for (let i = this._idle.length - 1; i >= 0; i--) {
      if (this._idle[i].conn === conn) {
        const entry: IdleSocketEntry = this._idle.splice(i, 1)[0];
        ConnectionPool.safeClose(entry.conn);
      }
    }
  }

  /** 淘汰超时空闲连接并关闭对应 socket，对应 OkHttp 的 cleanup 任务。 */
  evictExpired(): number {
    const now: number = Date.now();
    const alive: IdleSocketEntry[] = [];
    let evicted: number = 0;
    for (let i = 0; i < this._idle.length; i++) {
      const entry: IdleSocketEntry = this._idle[i];
      if (now - entry.since > this._keepAliveDurationNanos) {
        ConnectionPool.safeClose(entry.conn);
        evicted++;
      } else {
        alive.push(entry);
      }
    }
    this._idle = alive;
    return evicted;
  }

  /** 并发闸门：同 host 在飞请求计数（@ohos.net.http 引擎用）。 */
  acquire(host: string): void {
    const n: number | undefined = this._inFlight.get(host);
    this._inFlight.set(host, (n === undefined ? 0 : n) + 1);
  }

  release(host: string): void {
    const n: number | undefined = this._inFlight.get(host);
    if (n !== undefined) {
      if (n <= 1) {
        this._inFlight.delete(host);
      } else {
        this._inFlight.set(host, n - 1);
      }
    }
  }

  inFlight(host: string): number {
    const n: number | undefined = this._inFlight.get(host);
    return n === undefined ? 0 : n;
  }

  idleConnectionCount(): number {
    return this._idle.length;
  }

  /** 对齐 ConnectionPool.connectionCount()。 */
  connectionCount(): number {
    return this._idle.length + this.activeCount();
  }

  private activeCount(): number {
    let n: number = 0;
    this._inFlight.forEach((v: number) => {
      n += v;
    });
    return n;
  }

  evictAll(): void {
    for (let i = 0; i < this._idle.length; i++) {
      ConnectionPool.safeClose(this._idle[i].conn);
    }
    this._idle = [];
  }

  private static safeClose(conn: CloseableSocket | null): void {
    if (conn === null) {
      return;
    }
    try {
      conn.close();
    } catch (e) {
      // 关闭失败不影响池清理
    }
  }
}
