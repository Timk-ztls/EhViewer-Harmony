/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0119（配套，崩溃捕获的**安装入口**）
 * 目标   : harmony/entry/src/main/ets/hippo/ehviewer/CrashObserver.ets
 *
 * 上游是 `Thread.setDefaultUncaughtExceptionHandler(...)`；鸿蒙的对应能力是
 * `errorManager.on('error', observer)`（`@ohos.app.ability.errorManager`，SDK 20 d.ts:86）：
 * ```ts
 * function on(type: 'error', observer: ErrorObserver): number;
 * ```
 * **它收 `ErrorObserver` 类实例，不是回调函数** —— 所以必须 `extends ErrorObserver`。
 * `ErrorObserver` 的 d.ts 在 `api/application/ErrorObserver.d.ts`（**无 `declare module` 行**，
 * 是 `export default class`）→ 模块名 `@ohos.app.ability.application.ErrorObserver`。
 * （试过 `@ohos.app.ability.ErrorObserver` 不行 —— 那个路径下没有这个文件。）
 *
 * `ErrorObserver` 的两个回调（d.ts:65 / d.ts:90）：
 *   · `onUnhandledException(errMsg: string)` —— **只有消息 + 栈文本**，没有 Error 对象
 *   · `onException?(errObject: Error)`       —— 有 Error 对象（可选方法）
 * **同一次崩溃可能两个都触发** → 会写两个日志文件。故加**去重**（见 `CrashDeduper`）。
 */

import { errorManager } from '@kit.AbilityKit';
import hilog from '@ohos.hilog';

/** 供 `Crash.saveCrashLog` 使用的崩溃载体（把两种回调统一成"消息 + 栈文本"） */
export class CrashError {
  message: string;
  stackText: string;

  constructor(message: string, stackText: string) {
    this.message = message;
    this.stackText = stackText;
  }
}

/**
 * 去重器：同一次崩溃可能同时触发 `onUnhandledException` 与 `onException`。
 * 规则（Lead 建议的"消息 + 1 秒窗口"）：
 *   · 同一 key（消息）在 `windowMillis` 内只放行一次
 *   · 不同消息互不影响（两次不同崩溃都应记录）
 * 纯逻辑，`now` 注入 → 可断言。
 */
export class CrashDeduper {
  private readonly windowMillis: number;
  private readonly now: () => number;
  private lastKey: string | null = null;
  private lastTime: number = 0;

  constructor(windowMillis: number = 1000, now: () => number = () => Date.now()) {
    this.windowMillis = windowMillis;
    this.now = now;
  }

  /** @returns true = 放行（应记录）；false = 判定为重复（跳过） */
  shouldSave(key: string): boolean {
    const t: number = this.now();
    if (this.lastKey === key && (t - this.lastTime) < this.windowMillis) {
      return false;
    }
    this.lastKey = key;
    this.lastTime = t;
    return true;
  }
}

/** 安装状态（避免重复注册 observer） */
let sObserver: AppErrorObserver | null = null;
let sObserverId: number = -1;

/**
 * 崩溃观察者：把系统的两种回调归一成**一次** `handleCrash`。
 * @param handleCrash 由 `AppWiring` 提供（内部会重新求值 `Crash.shouldSave(...)`）
 */
export class AppErrorObserver {
  private readonly handleCrash: (t: CrashError) => void;
  private readonly deduper: CrashDeduper;

  constructor(handleCrash: (t: CrashError) => void, deduper: CrashDeduper = new CrashDeduper()) {
    this.handleCrash = handleCrash;
    this.deduper = deduper;
  }

  /** 无 Error 对象，只有消息 + 栈文本（d.ts:65） */
  onUnhandledException(errMsg: string): void {
    this.dispatch(errMsg, errMsg);
  }

  /** 有 Error 对象（d.ts:90，可选方法，但**必须实现**——否则这条路径静默丢弃） */
  onException(errObject: Error): void {
    const message: string = (errObject.message === undefined) ? `${errObject}` : errObject.message;
    const stack: string | undefined = errObject.stack;
    this.dispatch(message, (stack === undefined) ? message : stack);
  }

  private dispatch(message: string, stackText: string): void {
    if (!this.deduper.shouldSave(message)) {
      hilog.debug(0x0001, 'CrashObserver', 'duplicate crash within window, skipped: %{public}s', message);
      return;
    }
    try {
      this.handleCrash(new CrashError(message, stackText));
    } catch (e) {
      // 崩溃处理本身失败不能再崩（否则会形成递归）
      hilog.error(0x0001, 'CrashObserver', 'handleCrash failed: %{public}s', `${(e as Error).message}`);
    }
  }
}

/**
 * 安装崩溃捕获。**幂等**：重复调用返回同一个 observer id，不会重复注册。
 * @param handleCrash 崩溃回调（`AppWiring` 内做 shouldSave 判定 + 落盘）
 * @returns `errorManager.on` 返回的 id；安装失败 → -1
 */
export function installCrashHandler(handleCrash: (t: CrashError) => void): number {
  if (sObserver !== null) {
    return sObserverId;
  }
  try {
    sObserver = new AppErrorObserver(handleCrash);
    // errorManager.ErrorObserver 是 **type alias**
    // （`export type ErrorObserver = _ErrorObserver.default;`，d.ts:455）→ 只能当类型用，
    // 无法 `extends`，所以本类**结构实现**那三个成员，再断言成该类型传入。
    sObserverId = errorManager.on('error', sObserver as errorManager.ErrorObserver);
    hilog.info(0x0001, 'CrashObserver', 'crash handler installed, id=%{public}d', sObserverId);
    return sObserverId;
  } catch (e) {
    hilog.error(0x0001, 'CrashObserver', 'installCrashHandler failed: %{public}s', `${(e as Error).message}`);
    sObserver = null;
    sObserverId = -1;
    return -1;
  }
}

/** 是否已安装（`AppWiring` 断言/诊断用） */
export function isCrashHandlerInstalled(): boolean {
  return sObserver !== null;
}
