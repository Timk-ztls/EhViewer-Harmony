/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0408   上游: com/hippo/lib/yorozuya/ConcurrentPool.java（44 行）
 * 目标   : harmony/entry/src/main/ets/hippo/lib/yorozuya/ConcurrentPool.ets
 *
 * 是否有调用方（决定 port 还是 na）：**有**。upstream download/DownloadManager.java:96、ui/GalleryActivity.java:184、glgallery/GalleryProvider.java:41
 *   `private final Pool<GalleryPageView> mGalleryPageViewPool = new Pool<>(5);`
 *   即 下载/画廊的 NotifyTask 复用池，LIFO 复用语义（push 到底、pop 栈顶）必须 1:1，
 *   故不标 na（TaskPool 是任务调度池，不是对象复用池，替代不了这个语义）。
 *
 * 平台差异：
 *  1. (T[]) new Object[size] → Array<T | undefined>；pop() 对空池返回 undefined（对应 Java null）。
 *     上游 pop() 之后把槽位写 null（尽早释放引用）；ArkTS 这里写 undefined——同一目的，
 *     且对<T|undefined> 是合法值，不需要 null 强转。
 *  2. IllegalStateException → Error，消息串逐字保留 "Pool size must > 0, it is N"。
 *  3. Push()/pop() 在上游带 synchronized。ArkTS 无 synchronized 关键字；方案 §5-4 规定
 *     TaskPool/Worker 不共享对象，本类实例不会被跨 VM 线程并发访问，故同步语义无可观察差异。
 *     保留 ConcurrentPool 这个类名（不合并进 Pool），因为上游类型出现在 DownloadManager/
 *     GalleryActivity/GalleryProvider 的字段声明里，合并会改变跨模块签名。
 */

export class ConcurrentPool<T> {

  private readonly mArray: Array<T | undefined>;
  private readonly mMaxSize: number;
  private mSize: number = 0;

  constructor(size: number) {
    if (size <= 0) {
      throw new Error(`Pool size must > 0, it is ${size}`);
    }
    this.mArray = new Array<T | undefined>(size);
    this.mMaxSize = size;
    this.mSize = 0;
  }

  push(t: T): void {
    if (t !== null && t !== undefined && this.mSize < this.mMaxSize) {
      this.mArray[this.mSize] = t;
      this.mSize++;
    }
  }

  pop(): T | undefined {
    if (this.mSize > 0) {
      this.mSize--;
      const t: T | undefined = this.mArray[this.mSize];
      this.mArray[this.mSize] = undefined;
      return t;
    } else {
      return undefined;
    }
  }
}