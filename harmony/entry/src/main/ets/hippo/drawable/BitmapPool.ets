/**
 * 迁移自 app/src/main/java/com/hippo/drawable/BitmapPool.java（inventory S0026，上游 58 行）
 *
 * 上游语义：按**尺寸**复用位图（get(width,height) 找同尺寸空闲位图，没有就新建）。
 * 注意：上游池子**没有 key 概念**——匹配依据是宽高，不是键。本实现保持该契约不变。
 *
 * ============================ ArkTS 三个必要差异（Lead 已批准） ============================
 * 1) 无可观测的 WeakReference<PixelMap>：改为**强引用 + 容量上限 + LRU 淘汰**。
 *    **关键：put() 必须做 LRU 淘汰并 release 被挤掉的那个**（不能"满了拒绝"，
 *    否则调用方以为放进去了、实际没放，会静默丢失复用机会）。
 *    本实现：超出 capacity 时淘汰最久未使用的条目并 release；另加可选的空闲清理：
 *    超过 IDLE_TIMEOUT_MS(30s) 未访问的条目在下一次 put 时淘汰。
 * 2) createPixelMap 是异步的 → get() 返回 Promise；OOM/失败 → resolve(null)（对位上游返回 null）。
 * 3) 上游 ARGB_8888 → 鸿蒙 PixelMapFormat.RGBA_8888（通道顺序由 PixelMap 表达）。
 *
 * 池自管理（Lead 裁决）：不依赖页面调 clear()。clear() 仅作"提前释放"的优化，不是正确性依赖。
 */
import { image } from '@kit.ImageKit';

/** 池内条目：记录最后使用时间，用于空闲淘汰与 LRU */
class PoolEntry {
  pixelMap: image.PixelMap;
  lastUsedAt: number;

  constructor(pixelMap: image.PixelMap, now: number) {
    this.pixelMap = pixelMap;
    this.lastUsedAt = now;
  }
}

export class BitmapPool {
  /** 空闲条目超过该时长未使用，在下一次 put 时淘汰（可选优化，非正确性依赖） */
  static readonly IDLE_TIMEOUT_MS: number = 30000;

  private capacity: number;
  private entries: PoolEntry[] = [];

  constructor(capacity: number = 4) {
    this.capacity = capacity;
  }

  /**
   * 上游 put(Bitmap)：把不再使用的位图放回池子。
   * 满时**淘汰最久未使用**的条目并 release（LRU），绝不静默丢弃新放入的这张。
   */
  put(bitmap: image.PixelMap | null): void {
    if (bitmap === null) {
      return;
    }
    const now: number = Date.now();
    // 1) 空闲淘汰：超过 IDLE_TIMEOUT_MS 未访问
    const kept: PoolEntry[] = [];
    for (let i = 0; i < this.entries.length; i++) {
      const e: PoolEntry = this.entries[i];
      if (now - e.lastUsedAt > BitmapPool.IDLE_TIMEOUT_MS) {
        e.pixelMap.release();
      } else {
        kept.push(e);
      }
    }
    this.entries = kept;
    // 2) 满则 LRU 淘汰最旧（entries 按 lastUsedAt 升序：get() 取走即重排，put() 追加即最新）
    while (this.entries.length >= this.capacity && this.entries.length > 0) {
      const oldest: PoolEntry = this.entries.shift() as PoolEntry;
      oldest.pixelMap.release();
    }
    // 3) 放入新条目
    this.entries.push(new PoolEntry(bitmap, now));
  }

  /** 上游 get(w,h)：找同尺寸空闲位图（取最久未用的匹配项），没有就新建 */
  async get(width: number, height: number): Promise<image.PixelMap | null> {
    const now: number = Date.now();
    for (let i = 0; i < this.entries.length; i++) {
      const entry: PoolEntry = this.entries[i];
      const info: image.ImageInfo = await entry.pixelMap.getImageInfo();
      if (info.size.width === width && info.size.height === height) {
        // Remove from reusable list so it can't be used again.
        this.entries.splice(i, 1);
        entry.lastUsedAt = now;
        return entry.pixelMap;
      }
    }
    // Can not find reusable bitmap
    try {
      const opts: image.InitializationOptions = {
        size: { width: width, height: height },
        pixelFormat: image.PixelMapFormat.RGBA_8888,
        editable: true
      };
      return await image.createPixelMap(new ArrayBuffer(width * height * 4), opts);
    } catch (e) {
      // 对位上游 OutOfMemoryError → 记日志返回 null
      console.error('BitmapPool: createPixelMap failed (out of memory?)');
      return null;
    }
  }

  /** 提前释放（可选优化；不调用也不会泄漏——容量上限 + LRU + 空闲淘汰已兜住） */
  clear(): void {
    for (let i = 0; i < this.entries.length; i++) {
      this.entries[i].pixelMap.release();
    }
    this.entries = [];
  }

  /** 当前池内空闲数量 */
  size(): number {
    return this.entries.length;
  }

  /** 容量 */
  getCapacity(): number {
    return this.capacity;
  }
}
