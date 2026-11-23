/*
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

export type ReadProgressChangeListener = (changedGids: number[]) => void;
export type AsyncStartPageLoader = (gid: number) => Promise<number>;

/**
 * In-memory LRU-bounded read-progress cache (`gid -> 0-based startPage`) with async background
 * prefetching and batched listener notifications.
 *
 * Strictly avoids any synchronous disk I/O during ArkUI `build()` / `LazyForEach` / `@Reusable`
 * rendering paths.
 */
export class ReadProgressCache {
  private static readonly MAX_ENTRIES: number = 2000;
  private static readonly MAX_CONCURRENCY: number = 4;
  private static readonly NOTIFY_DEBOUNCE_MS: number = 40;

  private static readonly sCache: Map<number, number> = new Map<number, number>();
  private static readonly sInFlight: Set<number> = new Set<number>();
  private static readonly sListeners: Set<ReadProgressChangeListener> = new Set<ReadProgressChangeListener>();
  private static sLoader: AsyncStartPageLoader | null = null;
  private static readonly sPendingNotifyGids: Set<number> = new Set<number>();
  private static sNotifyTimer: number = -1;

  static setAsyncLoader(loader: AsyncStartPageLoader | null): void {
    ReadProgressCache.sLoader = loader;
  }

  static getCached(gid: number): number | undefined {
    if (gid <= 0) {
      return undefined;
    }
    return ReadProgressCache.sCache.get(gid);
  }

  private static putCacheEntry(gid: number, startPage: number): void {
    if (!ReadProgressCache.sCache.has(gid) && ReadProgressCache.sCache.size >= ReadProgressCache.MAX_ENTRIES) {
      const oldestKey: IteratorResult<number> = ReadProgressCache.sCache.keys().next();
      if (!oldestKey.done) {
        ReadProgressCache.sCache.delete(oldestKey.value);
      }
    }
    ReadProgressCache.sCache.set(gid, startPage);
  }

  private static emitChangedGids(gids: number[]): void {
    if (gids.length === 0) {
      return;
    }
    ReadProgressCache.sListeners.forEach((listener: ReadProgressChangeListener): void => {
      listener(gids);
    });
  }

  private static flushPendingNotifications(): void {
    if (ReadProgressCache.sNotifyTimer !== -1) {
      clearTimeout(ReadProgressCache.sNotifyTimer);
      ReadProgressCache.sNotifyTimer = -1;
    }
    if (ReadProgressCache.sPendingNotifyGids.size === 0) {
      return;
    }
    const batch: number[] = [];
    ReadProgressCache.sPendingNotifyGids.forEach((gid: number): void => {
      batch.push(gid);
    });
    ReadProgressCache.sPendingNotifyGids.clear();
    ReadProgressCache.emitChangedGids(batch);
  }

  private static scheduleNotification(gid: number): void {
    ReadProgressCache.sPendingNotifyGids.add(gid);
    if (ReadProgressCache.sNotifyTimer === -1) {
      ReadProgressCache.sNotifyTimer = setTimeout((): void => {
        ReadProgressCache.sNotifyTimer = -1;
        ReadProgressCache.flushPendingNotifications();
      }, ReadProgressCache.NOTIFY_DEBOUNCE_MS) as number;
    }
  }

  static update(gid: number, startPage: number): void {
    if (gid <= 0 || !Number.isFinite(gid)) {
      return;
    }
    const safePage: number = Number.isFinite(startPage) && startPage > 0 ? Math.floor(startPage) : 0;
    const prev: number | undefined = ReadProgressCache.sCache.get(gid);
    ReadProgressCache.putCacheEntry(gid, safePage);
    if (prev !== safePage) {
      ReadProgressCache.emitChangedGids([gid]);
    }
  }

  static remove(gid: number): void {
    ReadProgressCache.sCache.delete(gid);
  }

  static clear(): void {
    ReadProgressCache.sCache.clear();
  }

  static resetForTest(): void {
    if (ReadProgressCache.sNotifyTimer !== -1) {
      clearTimeout(ReadProgressCache.sNotifyTimer);
      ReadProgressCache.sNotifyTimer = -1;
    }
    ReadProgressCache.sCache.clear();
    ReadProgressCache.sInFlight.clear();
    ReadProgressCache.sPendingNotifyGids.clear();
    ReadProgressCache.sListeners.clear();
    ReadProgressCache.sLoader = null;
  }

  static addListener(listener: ReadProgressChangeListener): void {
    ReadProgressCache.sListeners.add(listener);
  }

  static removeListener(listener: ReadProgressChangeListener): void {
    ReadProgressCache.sListeners.delete(listener);
  }

  /**
   * Parses `startPage` directly from the first 1-2 ASCII lines of a `SpiderInfo` (`.ehviewer`) file,
   * matching `SpiderInfo.parseHeader` byte semantics.
   */
  static parseStartPageFromHeaderBytes(bytes: Uint8Array): number {
    if (bytes.length === 0) {
      return 0;
    }
    const line1End: number = ReadProgressCache.findLineEnd(bytes, 0);
    const line1: string = ReadProgressCache.decodeAsciiTrimmed(bytes, 0, line1End);
    if (line1.length === 0) {
      return 0;
    }
    let hexLine: string = line1;
    if (line1.startsWith('VERSION')) {
      const verNum: number = Number.parseInt(line1.substring('VERSION'.length), 10);
      if (verNum !== 2) {
        return 0;
      }
      const line2Start: number = ReadProgressCache.skipLineBreak(bytes, line1End);
      if (line2Start >= bytes.length) {
        return 0;
      }
      const line2End: number = ReadProgressCache.findLineEnd(bytes, line2Start);
      hexLine = ReadProgressCache.decodeAsciiTrimmed(bytes, line2Start, line2End);
    }
    return ReadProgressCache.parseHexStartPage(hexLine);
  }

  private static findLineEnd(bytes: Uint8Array, start: number): number {
    let i: number = start;
    while (i < bytes.length && bytes[i] !== 0x0a && bytes[i] !== 0x0d) {
      i++;
    }
    return i;
  }

  private static skipLineBreak(bytes: Uint8Array, pos: number): number {
    let i: number = pos;
    if (i < bytes.length && bytes[i] === 0x0d) {
      i++;
    }
    if (i < bytes.length && bytes[i] === 0x0a) {
      i++;
    }
    return i;
  }

  private static decodeAsciiTrimmed(bytes: Uint8Array, start: number, end: number): string {
    let out: string = '';
    for (let i = start; i < end; i++) {
      const ch: number = bytes[i];
      if (ch >= 0x20 && ch <= 0x7e) {
        out += String.fromCharCode(ch);
      }
    }
    return out.trim();
  }

  private static parseHexStartPage(raw: string): number {
    if (raw.length === 0) {
      return 0;
    }
    let startPage: number = 0;
    let hasDigit: boolean = false;
    for (let i = 0; i < raw.length; i++) {
      const code: number = raw.charCodeAt(i);
      if (code >= 0x30 && code <= 0x39) {
        startPage = startPage * 16 + (code - 0x30);
        hasDigit = true;
      } else if (code >= 0x61 && code <= 0x66) {
        startPage = startPage * 16 + (code - 0x61 + 10);
        hasDigit = true;
      } else if (code >= 0x41 && code <= 0x46) {
        startPage = startPage * 16 + (code - 0x41 + 10);
        hasDigit = true;
      } else {
        return 0;
      }
    }
    if (!hasDigit || !Number.isFinite(startPage) || startPage <= 0) {
      return 0;
    }
    return startPage;
  }

  static formatPagesLabel(
    gid: number,
    pages: number,
    showGalleryPages: boolean,
    showReadProgress: boolean
  ): string {
    if (pages <= 0 || !showGalleryPages) {
      return '';
    }
    if (!showReadProgress) {
      return `${pages}P`;
    }
    const cached: number | undefined = ReadProgressCache.sCache.get(gid);
    if (cached === undefined) {
      return `${pages}P`;
    }
    if (cached > 0) {
      const displayPage: number = Math.min(cached + 1, pages);
      return `${displayPage}/${pages}P`;
    }
    return `0/${pages}P`;
  }

  static async prefetchGids(gids: number[]): Promise<void> {
    const loader: AsyncStartPageLoader | null = ReadProgressCache.sLoader;
    if (loader === null || gids.length === 0) {
      return;
    }
    const queue: number[] = [];
    const queuedSet: Set<number> = new Set<number>();
    for (let i = 0; i < gids.length; i++) {
      const gid: number = gids[i];
      if (
        gid <= 0 ||
        !Number.isFinite(gid) ||
        queuedSet.has(gid) ||
        ReadProgressCache.sCache.has(gid) ||
        ReadProgressCache.sInFlight.has(gid)
      ) {
        continue;
      }
      queuedSet.add(gid);
      queue.push(gid);
      ReadProgressCache.sInFlight.add(gid);
    }
    if (queue.length === 0) {
      return;
    }

    let cursor: number = 0;
    const workerCount: number = Math.min(ReadProgressCache.MAX_CONCURRENCY, queue.length);
    const workers: Promise<void>[] = [];
    for (let w = 0; w < workerCount; w++) {
      workers.push((async (): Promise<void> => {
        while (cursor < queue.length) {
          const idx: number = cursor;
          cursor++;
          const gid: number = queue[idx];
          try {
            const loaded: number = await loader(gid);
            const safePage: number = Number.isFinite(loaded) && loaded > 0 ? Math.floor(loaded) : 0;
            ReadProgressCache.putCacheEntry(gid, safePage);
            ReadProgressCache.scheduleNotification(gid);
          } catch (_e) {
            // Keep uncached or treat transient read failures softly without blocking UI.
          } finally {
            ReadProgressCache.sInFlight.delete(gid);
          }
        }
      })());
    }
    await Promise.all(workers);
    if (ReadProgressCache.sInFlight.size === 0) {
      ReadProgressCache.flushPendingNotifications();
    }
  }
}
