/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0011   上游: com/hippo/conaco/Conaco.java（182 行）
 * 目标   : harmony/entry/src/main/ets/hippo/conaco/Conaco.ets
 *
 * 平台差异：
 *  1. **执行器落地**（上游两处线程）：
 *       disk    : `SerialThreadExecutor(3000L, LinkedList, PriorityThreadFactory("Conaco-Disk", BACKGROUND))`
 *                 → 同名构造，保活 3000ms、FIFO、线程名 "Conaco-Disk"
 *       network : `ThreadPoolExecutor(3, 3, 5s, LinkedBlockingQueue, PriorityThreadFactory("Conaco-Network"))`
 *                 → `IoThreadPoolExecutor`（并发上限 4；上游是 3 核心 3 上限固定 + 无界队列，
 *                   二者都是"固定并发 + 排队回压"，见 IoThreadPoolExecutor 的 DEVIATION）
 *       **差异**：并发上限 4 vs 上游 3。保留 Lead 已批准的取值；如需与上游严格一致可传 3。
 *  2. `AtomicInteger mIdGenerator` + `while ((id = getAndIncrement()) == INVALID_ID);`
 *     → `IntIdGenerator`（已移植，其 nextId() 内部跳过 INVALID_ID，自旋语义等价）。
 *  3. **`ConacoTask.Builder.setConaco(this)` → `setConaco(finishCallback)`**：
 *     上游把 `Conaco` 实例存进 task，task 完成时回调 `mConaco.finishConacoTask(this)`。
 *     ArkTS 里 Conaco ↔ ConacoTask 互相引用会形成 **循环 import**（ArkTS 对模块初始化顺序敏感），
 *     故改成注入一个回调闭包 `(task) => this.finishConacoTask(task)`，**行为完全等价**，
 *     且切断了循环依赖。这是本文件唯一的结构性改写。
 *  4. `@UiThread` / `@IntDef` 注解 → 注释保留（ArkTS 无注解处理，见已批准的平台口径）。
 *  5. `Log.d/Log.e` → hilog。
 *  6. **`conaco/Build` 相关**：`builder.isValid()` 在 ConacoTask.Builder 里实现为显式抛错
 *     （上游抛 `IllegalStateException`，ArkTS 统一用 `Error`）。
 */

import hilog from '@ohos.hilog';
import { BeerBelly, BeerBellyParams } from '../beerbelly/BeerBelly';
import { ValueCache } from './ValueCache';
import { ValueHelper } from './ValueHelper';
import { Register } from './Register';
import { ConacoTask, Builder as TaskBuilder } from './ConacoTask';
import { Unikery, UNIKERY_INVALID_ID } from './Unikery';
import { SerialThreadExecutor } from '../lib/yorozuya/thread/SerialThreadExecutor';
import { PriorityThreadFactory } from '../lib/yorozuya/thread/PriorityThreadFactory';
import { IntIdGenerator } from '../lib/yorozuya/IntIdGenerator';
import { IoThreadPoolExecutor } from '../util/IoThreadPoolExecutor';
import { OkHttpClient } from '../okhttp/OkHttpClient';

const TAG: string = 'Conaco';
const DOMAIN: number = 0x0001;

/** 上游 Process.THREAD_PRIORITY_BACKGROUND */
const THREAD_PRIORITY_BACKGROUND: number = -10;

export class Conaco<V> {

  // 来源常量（上游 0/1/2）。ConacoTask 内部有同值镜像常量以避免循环依赖。
  static readonly SOURCE_MEMORY: number = 0;
  static readonly SOURCE_DISK: number = 1;
  static readonly SOURCE_NETWORK: number = 2;

  private readonly mHelper: ValueHelper<V>;
  private readonly mCache: ValueCache<V>;
  private readonly mOkHttpClient: OkHttpClient;
  private readonly mRegister: Register<V, ConacoTask<V>>;
  private readonly mDiskExecutor: SerialThreadExecutor;
  private readonly mNetworkExecutor: IoThreadPoolExecutor;
  private readonly mIdGenerator: IntIdGenerator = new IntIdGenerator();
  private readonly mDebug: boolean;

  /** 上游是 private 构造 + Builder；ArkTS 的 ConacoBuilder 是同文件独立类，无法访问 private 构造，故放开 */
  constructor(builder: ConacoBuilder<V>) {
    this.mHelper = builder.objectHelper as ValueHelper<V>;

    const beerBellyParams: BeerBellyParams = new BeerBellyParams();
    beerBellyParams.hasMemoryCache = builder.hasMemoryCache;
    beerBellyParams.memoryCacheMaxSize = builder.memoryCacheMaxSize;
    beerBellyParams.hasDiskCache = builder.hasDiskCache;
    beerBellyParams.diskCacheDir = builder.diskCacheDir;
    beerBellyParams.diskCacheMaxSize = builder.diskCacheMaxSize;

    this.mCache = new ValueCache<V>(beerBellyParams, this.mHelper);
    this.mOkHttpClient = builder.okHttpClient as OkHttpClient;

    this.mRegister = new Register<V, ConacoTask<V>>();

    // disk：SerialThreadExecutor(3000L) + "Conaco-Disk"
    this.mDiskExecutor = new SerialThreadExecutor(3000, [], new PriorityThreadFactory('Conaco-Disk',
      THREAD_PRIORITY_BACKGROUND));
    // network：上游 ThreadPoolExecutor(3,3,5s, LinkedBlockingQueue) → IoThreadPoolExecutor（见差异 1）
    this.mNetworkExecutor = new IoThreadPoolExecutor(3);

    this.mDebug = builder.debug;
  }

  /** 对应上游 getBeerBelly()：mCache 本身就是 BeerBelly 子类 */
  getBeerBelly(): BeerBelly<V> {
    return this.mCache;
  }

  private onUnregisterConacoTask(task: ConacoTask<V>): void {
    const next: ConacoTask<V> | null = this.mRegister.getByKey(task.getKey());
    if (next !== null) {
      this.startConacoTask(next);
    }
  }

  private startConacoTask(task: ConacoTask<V>): void {
    const unikery: Unikery<V> | null = task.getUnikery();

    // Can't unikery is gone, finish the task now
    if (unikery === null) {
      this.finishConacoTask(task);
      return;
    }

    const key: string | null = task.getKey();
    let value: V | null = null;

    // Get from memory
    if (key !== null && task.useMemoryCache() && this.mHelper.useMemoryCache(key, null)) {
      value = this.mCache.getFromMemory(key);
    }

    if (value === null || !unikery.onGetValue(value, Conaco.SOURCE_MEMORY)) {
      unikery.onMiss(Conaco.SOURCE_MEMORY);
      task.start();
    } else {
      // Get the object, finish the task
      this.finishConacoTask(task);
    }
  }

  /** 对应上游 load(Builder)（@UiThread） */
  /** 上游签名是 `load(ConacoTask.Builder<V>)` —— 注意与 Conaco 自己的 `ConacoBuilder` 是两个类 */
  load(builder: TaskBuilder<V>): void {
    builder.isValid();

    if (this.mDebug) {
      hilog.debug(DOMAIN, TAG, 'Key %{public}s', `${builder.getKey()}`);
      hilog.debug(DOMAIN, TAG, 'Url %{public}s', `${builder.getUrl()}`);
    }

    const unikery: Unikery<V> | null = builder.getUnikery();

    // Cancel first
    if (unikery === null) {
      return;
    }
    this.cancel(unikery);

    // Build conaco task（IntIdGenerator.nextId() 内部已跳过 INVALID_ID，等价上游自旋）
    const id: number = this.mIdGenerator.nextId();
    unikery.setTaskId(id);

    // 差异 3：注入 finish 回调而不是 Conaco 实例（切断循环 import）
    builder.setId(id)
      .setHelper(this.mHelper)
      .setCache(this.mCache)
      .setOkHttpClient(this.mOkHttpClient)
      .setDiskExecutor(this.mDiskExecutor)
      .setNetworkExecutor(this.mNetworkExecutor)
      .setConaco((task: ConacoTask<V>) => {
        this.finishConacoTask(task);
      });

    const task: ConacoTask<V> = builder.build();

    if (!this.mRegister.register(id, task)) {
      this.startConacoTask(task);
    } else {
      // The key is repeated, wait
      unikery.onWait();
    }
  }

  /** 对应上游 cancel(Unikery)（@UiThread） */
  cancel(unikery: Unikery<V>): void {
    const id: number = unikery.getTaskId();
    if (id !== UNIKERY_INVALID_ID) {
      unikery.setTaskId(UNIKERY_INVALID_ID);
      const task: ConacoTask<V> | null = this.mRegister.unregister(id);
      if (task !== null) {
        task.stop();
        // Don't need unikery anymore
        task.clearUnikery();
        // Callback
        this.onUnregisterConacoTask(task);
      } else {
        hilog.error(DOMAIN, TAG, "Can't find conaco task by id %{public}d", id);
      }
    }
  }

  isLoading(unikery: Unikery<V>): boolean {
    const id: number = unikery.getTaskId();
    return id !== UNIKERY_INVALID_ID && this.mRegister.contain(id);
  }

  /**
   * Unregister task, reset unikery id, clear unikery in task, call next
   */
  finishConacoTask(task: ConacoTask<V>): void {
    this.mRegister.unregister(task.getId());
    const unikery: Unikery<V> | null = task.getUnikery();
    if (unikery !== null) {
      unikery.setTaskId(UNIKERY_INVALID_ID);
    }
    task.clearUnikery();

    this.onUnregisterConacoTask(task);
  }
}

/**
 * 上游 `Conaco.Builder<T> extends BeerBelly.BeerBellyParams`。
 * ArkTS 无类继承自"参数对象"的习惯用法，但这里**照搬继承**以保持字段一一对应
 * （`hasMemoryCache/memoryCacheMaxSize/hasDiskCache/diskCacheDir/diskCacheMaxSize` 来自基类）。
 */
export class ConacoBuilder<T> extends BeerBellyParams {

  /** The client to get image from internet */
  okHttpClient: OkHttpClient | null = null;

  /** Decode, get size and others */
  objectHelper: ValueHelper<T> | null = null;

  debug: boolean = false;

  /** 对应上游 isValid()：缺 http client 直接抛（上游抛 IllegalStateException） */
  isValid(): void {
    if (this.okHttpClient === null) {
      throw new Error('No http client? How can I load image via url?');
    }
    if (this.objectHelper === null) {
      throw new Error('No object helper? How can I decode value?');
    }
  }

  build(): Conaco<T> {
    this.isValid();
    return new Conaco<T>(this);
  }
}
