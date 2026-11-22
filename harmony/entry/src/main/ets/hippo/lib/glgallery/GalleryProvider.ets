/*
 * Copyright 2016 Hippo Seven
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

import { Image } from '../image/Image';
import { ImageWrapper } from '../glview/image/ImageWrapper';
import { ConcurrentPool } from '../yorozuya/ConcurrentPool';
import { MathUtils } from '../yorozuya/MathUtils';
import { OSUtils } from '../yorozuya/OSUtils';
import { GLRoot, GLRootOnGLIdleListener } from '../glview/view/GLRoot';
import { GLCanvas } from '../glview/glrenderer/GLCanvas';

/** 通知类型（上游用 `@IntDef` + `@Retention(SOURCE)` 注解，ArkTS 无注解 → 常量 + 枚举值文档）。 */
export class NotifyType {
  static readonly DATA_CHANGED: number = 0;
  static readonly WAIT: number = 1;
  static readonly PERCENT: number = 2;
  static readonly SUCCEED: number = 3;
  static readonly FAILED: number = 4;
}

/**
 * `com.hippo.lib.glgallery.GalleryProvider` 的 ArkTS 等价实现。
 *
 * 画廊的数据源抽象：子类负责"第 index 页的图从哪来"（本地目录 / Eh 网络 / 压缩包 / 下载），
 * 基类负责四件事：
 * 1. **请求去重与缓存**：命中 ImageCache 直接回调成功，否则交给子类 `onRequest`
 * 2. **跨线程通知**：子类在任意线程算完后调 `notifyPageXxx`，基类把通知包装成
 *    `NotifyTask` 挂到 `GLRoot` 的 idle 回调上，**在 GL 线程交给 Listener** ——
 *    这样 UI 侧拿到的 `ImageWrapper` 一定在 GL 上下文可用的时刻被消费
 * 3. **LRU 缓存与引用计数**：按 `宽*高*4` 字节计费，上限按总内存/16 clamp 到 32~128MB，
 *    淘汰时 `release()` 减引用
 * 4. **生命周期**：`start()` 只能一次（上游抛 IllegalStateException），`stop()` 清空缓存
 *
 * ## 子类契约（storage-db 需要实现的）
 * - `size()`：返回总页数；`STATE_WAIT`(-1) 表示数据未就绪、`STATE_ERROR`(-2) 表示失败，
 *   失败原因用 `getError()` 取
 * - `onRequest(index)`：开始加载；完成后调 `notifyPageSucceed/notifyPageFailed`
 * - `onForceRequest(index)`：忽略缓存强制重载（坏图重试走这里）
 * - `onCancelRequest(index)`：请求已不需要（页面滑出视野），应尽量中止
 * - `getError()`：`size()` 返回 STATE_ERROR 时的错误信息
 *
 * ## ArkTS 差异
 * - `@UiThread` 注解 → 注释；ArkTS 无线程校验 API（`OSUtils.checkMainLoop()` 恒 true）
 * - `LruCache<Integer,ImageWrapper>` → 本文件内的 `ImageCache`（`Map` 保序实现，
 *   语义按 Android LruCache：put 后超限从队首淘汰、get 命中后移到队尾）
 * - `synchronized` 去掉（ArkTS 单 VM 模型）
 */
export abstract class GalleryProvider {

  /** `size()` 的哨兵值：数据未就绪。 */
  static readonly STATE_WAIT: number = -1;

  /** `size()` 的哨兵值：加载失败，原因见 `getError()`。 */
  static readonly STATE_ERROR: number = -2;

  private readonly mNotifyTaskPool: ConcurrentPool<NotifyTask> = new ConcurrentPool<NotifyTask>(5);
  private mListener: GalleryListener | null = null;
  private mGLRoot: GLRoot | null = null;

  private readonly mImageCache: ImageCache = new ImageCache();

  private mStarted: boolean = false;

  /** 主线程调用：标记开始。重复调用抛错（与上游 IllegalStateException 对齐）。 */
  start(): void {
    if (this.mStarted) {
      throw new Error("Can't start it twice");
    }
    this.mStarted = true;
  }

  /** 主线程调用：清空缓存。 */
  stop(): void {
    this.mImageCache.evictAll();
  }

  setGLRoot(glRoot: GLRoot | null): void {
    this.mGLRoot = glRoot;
  }

  /**
   * @return `STATE_WAIT` 等待中 / `STATE_ERROR` 失败（原因见 `getError()`）/ 0 空 / >0 页数
   */
  abstract size(): number;

  /** 请求第 index 页：缓存命中直接通知成功，否则交给子类。 */
  request(index: number): void {
    const imageWrapper = this.mImageCache.get(index);
    if (imageWrapper !== null) {
      this.notifyPageSucceedWrapper(index, imageWrapper);
    } else {
      this.onRequest(index);
    }
  }

  /** 忽略缓存强制请求（坏图重试）。 */
  forceRequest(index: number): void {
    this.onForceRequest(index);
  }

  removeCache(index: number): void {
    this.mImageCache.remove(index);
  }

  protected abstract onRequest(index: number): void;

  protected abstract onForceRequest(index: number): void;

  /** 取消第 index 页的请求。 */
  cancelRequest(index: number): void {
    this.onCancelRequest(index);
  }

  protected abstract onCancelRequest(index: number): void;

  abstract getError(): string;

  setListener(listener: GalleryListener | null): void {
    this.mListener = listener;
  }

  // ==========================================================================
  // 通知入口（子类在任意线程调用）
  // ==========================================================================

  notifyDataChanged(): void {
    this.notify(NotifyType.DATA_CHANGED, -1, 0.0, null, null);
  }

  notifyDataChangedAt(index: number): void {
    this.notify(NotifyType.DATA_CHANGED, index, 0.0, null, null);
  }

  notifyPageWait(index: number): void {
    this.notify(NotifyType.WAIT, index, 0.0, null, null);
  }

  notifyPagePercent(index: number, percent: number): void {
    this.notify(NotifyType.PERCENT, index, percent, null, null);
  }

  /** 成功：先包一层 ImageWrapper 并放入缓存，再通知。 */
  notifyPageSucceed(index: number, image: Image | null): void {
    if (image === null) {
      this.notifyPageFailed(index, 'image == null');
      return;
    }
    const imageWrapper = new ImageWrapper(image);
    this.mImageCache.add(index, imageWrapper);
    this.notifyPageSucceedWrapper(index, imageWrapper);
  }

  /** 成功（已是 wrapper）：不重复入缓存，直接通知。 */
  notifyPageSucceedWrapper(index: number, imageWrapper: ImageWrapper | null): void {
    this.notify(NotifyType.SUCCEED, index, 0.0, imageWrapper, null);
  }

  notifyPageFailed(index: number, error: string | null): void {
    this.notify(NotifyType.FAILED, index, 0.0, null, error);
  }

  /**
   * 把通知投递到 GL 线程：没有 listener 或没有 GLRoot 时**直接丢弃**
   * （上游如此 —— 此时 UI 已经不关心了，不缓存也不补发）。
   */
  private notify(type: number, index: number, percent: number, image: ImageWrapper | null,
    error: string | null): void {
    const listener = this.mListener;
    if (listener === null) {
      return;
    }
    const glRoot = this.mGLRoot;
    if (glRoot === null) {
      return;
    }

    let task = this.mNotifyTaskPool.pop();
    if (task === undefined) {
      task = new NotifyTask(this.mNotifyTaskPool);
    }
    task.setData(listener, type, index, percent, image, error);
    glRoot.addOnGLIdleListener(task);
  }
}

/**
 * `GalleryProvider.Listener`。ArkTS interface 不能嵌套，提成顶层导出；
 * 下游 `implements GalleryProvider.Listener` 写成 `implements GalleryListener`。
 */
export interface GalleryListener {
  onDataChanged(): void;

  onPageWait(index: number): void;

  onPagePercent(index: number, percent: number): void;

  onPageSucceed(index: number, image: ImageWrapper): void;

  onPageFailed(index: number, error: string): void;

  onDataChangedAt(index: number): void;
}

/**
 * 一次通知的载体，实现 `GLRoot.OnGLIdleListener`：
 * 被 GL 线程调用一次即消费，随后归还对象池（上游 `notify` 的池化设计，避免每页分配）。
 *
 * 上游把 listener 存在池对象里（构造时传），这里改为 `setData` 时传入 ——
 * 因为 `GalleryProvider.setListener` 可以在两次通知之间更换 listener，
 * 池化对象不能固化旧的 listener（上游其实也有这个隐患，这里顺手修掉并登记）。
 */
class NotifyTask implements GLRootOnGLIdleListener {
  private readonly mPool: ConcurrentPool<NotifyTask>;

  private mListener: GalleryListener | null = null;
  private mType: number = 0;
  private mIndex: number = 0;
  private mPercent: number = 0;
  private mImage: ImageWrapper | null = null;
  private mError: string | null = null;

  constructor(pool: ConcurrentPool<NotifyTask>) {
    this.mPool = pool;
  }

  setData(listener: GalleryListener, type: number, index: number, percent: number,
    image: ImageWrapper | null, error: string | null): void {
    this.mListener = listener;
    this.mType = type;
    this.mIndex = index;
    this.mPercent = percent;
    this.mImage = image;
    this.mError = error;
  }

  onGLIdle(_canvas: GLCanvas, _renderRequested: boolean): boolean {
    const listener = this.mListener;
    if (listener !== null) {
      switch (this.mType) {
        case NotifyType.DATA_CHANGED:
          if (this.mIndex < 0) {
            listener.onDataChanged();
          } else {
            listener.onDataChangedAt(this.mIndex);
          }
          break;
        case NotifyType.WAIT:
          listener.onPageWait(this.mIndex);
          break;
        case NotifyType.PERCENT:
          listener.onPagePercent(this.mIndex, this.mPercent);
          break;
        case NotifyType.SUCCEED:
          if (this.mImage !== null) {
            listener.onPageSucceed(this.mIndex, this.mImage);
          }
          break;
        case NotifyType.FAILED:
          listener.onPageFailed(this.mIndex, this.mError === null ? '' : this.mError);
          break;
        default:
          break;
      }
    }

    // 清理引用（防止池对象持有最后一帧的图导致泄漏）
    this.mListener = null;
    this.mImage = null;
    this.mError = null;
    // 归还池
    this.mPool.push(this);

    return false;
  }
}

/**
 * `GalleryProvider.ImageCache`：按字节计费的 LRU。
 *
 * 语义按 `android.util.LruCache`：
 * - 容量上限 = `clamp(总内存/16, 32MB, 128MB)`（上游原式）
 * - 计费 = `width * height * 4`（上游 `sizeOf`，注意上游有两份 return，等价）
 * - `put` 超限 → 从**最久未使用**端淘汰并回调 `entryRemoved(true, ...)`
 * - `get` 命中后把条目移到最新端
 * - `remove` / `evictAll` 也回调 `entryRemoved(false, ...)`
 *
 * 为什么不用 ArkTS 现成容器：`@ohos.util.LruCache` 的 key 只支持 string/number，
 * 且不支持自定义 `sizeOf` 与淘汰回调 —— 而"淘汰时必须 release 引用"是正确性要求，
 * 不能省。
 */
class ImageCache {
  private static readonly MAX_CACHE_SIZE: number = 128 * 1024 * 1024;
  private static readonly MIN_CACHE_SIZE: number = 32 * 1024 * 1024;

  /** Map 保持插入顺序：队首 = 最久未使用，队尾 = 最近使用。 */
  private readonly mMap: Map<number, ImageWrapper> = new Map<number, ImageWrapper>();
  private readonly mMaxSize: number;
  private mSize: number = 0;

  constructor() {
    this.mMaxSize = Math.trunc(MathUtils.clamp(OSUtils.getTotalMemory() / 16,
      ImageCache.MIN_CACHE_SIZE, ImageCache.MAX_CACHE_SIZE));
  }

  /** 上游 `ImageCache.add`：动画图不入缓存（动图靠 Image1 自行管理），且必须 obtain 成功。 */
  add(key: number, value: ImageWrapper): void {
    if (!value.getAnimated() && value.obtain()) {
      this.put(key, value);
    }
  }

  get(key: number): ImageWrapper | null {
    const value = this.mMap.get(key);
    if (value === undefined) {
      return null;
    }
    // 命中 → 移到最新端
    this.mMap.delete(key);
    this.mMap.set(key, value);
    return value;
  }

  put(key: number, value: ImageWrapper): void {
    const previous = this.mMap.get(key);
    if (previous !== undefined) {
      this.mMap.delete(key);
      this.mSize -= this.sizeOf(previous);
      this.entryRemoved(false, previous);
    }
    this.mMap.set(key, value);
    this.mSize += this.sizeOf(value);
    this.trimToSize(this.mMaxSize);
  }

  remove(key: number): void {
    const previous = this.mMap.get(key);
    if (previous !== undefined) {
      this.mMap.delete(key);
      this.mSize -= this.sizeOf(previous);
      this.entryRemoved(false, previous);
    }
  }

  evictAll(): void {
    const values: ImageWrapper[] = [];
    this.mMap.forEach((v: ImageWrapper) => {
      values.push(v);
    });
    this.mMap.clear();
    this.mSize = 0;
    for (let i = 0; i < values.length; i++) {
      this.entryRemoved(false, values[i]);
    }
  }

  /** 淘汰到不超过 maxSize。 */
  trimToSize(maxSize: number): void {
    while (this.mSize > maxSize && this.mMap.size > 0) {
      // Map 迭代顺序即插入顺序，第一个就是最久未使用
      let oldestKey: number = -1;
      let oldestValue: ImageWrapper | null = null;
      this.mMap.forEach((v: ImageWrapper, k: number) => {
        if (oldestValue === null) {
          oldestKey = k;
          oldestValue = v;
        }
      });
      if (oldestValue === null) {
        break;
      }
      this.mMap.delete(oldestKey);
      this.mSize -= this.sizeOf(oldestValue);
      this.entryRemoved(true, oldestValue);
    }
  }

  /** 字节计费：宽*高*4（上游 `sizeOf`）。 */
  private sizeOf(value: ImageWrapper): number {
    return value.getWidth() * value.getHeight() * 4;
  }

  private entryRemoved(evicted: boolean, oldValue: ImageWrapper): void {
    // 上游不管 evicted 与否都 release（引用计数归零才真正 recycle）
    oldValue.release();
  }

  /** 调试/单测：当前计费字节数。 */
  size(): number {
    return this.mSize;
  }

  /** 调试/单测：当前条目数。 */
  entryCount(): number {
    return this.mMap.size;
  }

  /** 调试/单测：容量上限。 */
  maxSize(): number {
    return this.mMaxSize;
  }
}
