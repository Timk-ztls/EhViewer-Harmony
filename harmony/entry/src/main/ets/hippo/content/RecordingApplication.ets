/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0021   上游: com/hippo/content/RecordingApplication.java（79 行）
 * 目标   : harmony/entry/src/main/ets/hippo/content/RecordingApplication.ets
 *
 * 目的：**记录所有存活的 Activity**，以便 `recreate()` 时让它们全部重建（切换语言/主题后生效）。
 *
 * 上游实现：
 * ```java
 * private List<WeakReference<Activity>> list = new LinkedList<>();
 * onActivityCreated:   list.add(new WeakReference<>(activity));
 * onActivityDestroyed: 遍历 → a == null || a == activity 时 iterator.remove();   // 顺手清理已回收的
 * recreate():          拷贝出非 null 的 → **倒序** 逐个 recreate()
 * ```
 *
 * ## 可移植的三条语义（断言钉住）
 * 1. **注册/注销配对**：created 加入、destroyed 移除
 * 2. **destroyed 时顺手清理"已失效"的条目**（上游 `a == null` 分支）——
 *    鸿蒙没有 `WeakReference`，用"令牌 + 存活标记"表达：`purgeDead()` 移除已标记失效的
 * 3. **`recreate()` 必须倒序**（`for (int i = size - 1; i >= 0; --i)`）——
 *    倒序是为了**先重建栈顶**：正的按栈底到栈顶重建会让用户看到的页面闪回。
 *
 * ## 平台差异
 *  1. `WeakReference<Activity>` → `WeakRef` 概念在 ArkTS 里没有 → 本类不持有页面对象，
 *     只持有**调用方给的不透明 key**（`string`）+ 一个 `onRecreate` 回调。
 *     内存安全由调用方保证（页面 destroy 时必须调 `onActivityDestroyed`）。
 *  2. `ActivityLifecycleCallbacks` → 本类暴露 `onActivityCreated/onActivityDestroyed`，
 *     由 `AppWiring`/`UIAbility` 的生命周期接到这里（鸿蒙的 `UIAbilityLifecycleCallback`）。
 *  3. `SceneApplication`（上游基类，含 Scene 栈）不在本条范围内。
 */

/** 一个被记录的页面（key 由调用方提供，通常用 ability 的唯一标识） */
export class RecordedPage {
  key: string;
  /** 重建动作（对应上游 `activity.recreate()`） */
  onRecreate: () => void;
  /** 是否已失效（对应上游 `WeakReference.get() == null`） */
  dead: boolean = false;

  constructor(key: string, onRecreate: () => void) {
    this.key = key;
    this.onRecreate = onRecreate;
  }
}

export abstract class RecordingApplication {

  /** 上游 `List<WeakReference<Activity>> list`（保持插入顺序） */
  private pages: RecordedPage[] = [];

  /** 对应上游 `onCreate()` 里注册回调 —— 这里只提供注册入口，接线由 AppWiring 做 */
  abstract onCreate(): void;

  /** 对应上游 `onActivityCreated(activity, savedInstanceState)` */
  onActivityCreated(key: string, onRecreate: () => void): void {
    this.pages.push(new RecordedPage(key, onRecreate));
  }

  /**
   * 对应上游 `onActivityDestroyed(activity)`：
   * **移除目标 + 顺手清理所有已失效的条目**（上游 `if (a == null || a == activity) iterator.remove()`）。
   */
  onActivityDestroyed(key: string): void {
    const kept: RecordedPage[] = [];
    for (let i = 0; i < this.pages.length; i++) {
      const p: RecordedPage = this.pages[i];
      if (p.dead || p.key === key) {
        continue; // 清理已失效的 + 移除目标
      }
      kept.push(p);
    }
    this.pages = kept;
  }

  /** 标记某个页面已失效（对应 GC 回收后的 `WeakReference.get() == null`） */
  markDead(key: string): void {
    for (let i = 0; i < this.pages.length; i++) {
      if (this.pages[i].key === key) {
        this.pages[i].dead = true;
      }
    }
  }

  /** 当前记录的页面 key（按插入顺序；诊断/测试用） */
  getKeys(): string[] {
    const keys: string[] = [];
    for (let i = 0; i < this.pages.length; i++) {
      if (!this.pages[i].dead) {
        keys.push(this.pages[i].key);
      }
    }
    return keys;
  }

  /** 存活条目数（含 dead 标记的；诊断用） */
  size(): number {
    return this.pages.length;
  }

  /**
   * 对应上游 `recreate()`：
   * 1. 拷贝出**非 null**（非失效）的条目
   * 2. **倒序**逐个 `recreate()`
   * @returns 实际重建的 key 顺序（倒序）
   */
  recreate(): string[] {
    // 1. 拷贝（跳过已失效）
    const copy: RecordedPage[] = [];
    for (let i = 0; i < this.pages.length; i++) {
      if (!this.pages[i].dead) {
        copy.push(this.pages[i]);
      }
    }
    // 2. **倒序**重建
    const order: string[] = [];
    for (let i = copy.length - 1; i >= 0; --i) {
      copy[i].onRecreate();
      order.push(copy[i].key);
    }
    return order;
  }
}
