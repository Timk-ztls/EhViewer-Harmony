/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0153   上游: com/hippo/ehviewer/event/SomethingNeedRefresh.java（40 行）
 * 目标   : harmony/entry/src/main/ets/hippo/ehviewer/event/SomethingNeedRefresh.ets
 *
 * 平台差异：无（纯数据类）。三个标志 + 三个静态工厂方法逐字照搬。
 * 注意：**静态工厂与构造器都保留** —— 上游既有 `new SomethingNeedRefresh()`（全 false）
 * 也有 `bookmarkDrawNeedRefresh()` 等一次性工厂，两者语义不同，不能合并。
 */

export class SomethingNeedRefresh {

  private bookmarkDrawNeed: boolean = false;
  private downloadLabelDrawNeed: boolean = false;
  private downloadInfoNeed: boolean = false;

  constructor() {
  }

  isBookmarkDrawNeed(): boolean {
    return this.bookmarkDrawNeed;
  }

  setBookmarkDrawNeed(v: boolean): void {
    this.bookmarkDrawNeed = v;
  }

  isDownloadLabelDrawNeed(): boolean {
    return this.downloadLabelDrawNeed;
  }

  setDownloadLabelDrawNeed(v: boolean): void {
    this.downloadLabelDrawNeed = v;
  }

  isDownloadInfoNeed(): boolean {
    return this.downloadInfoNeed;
  }

  setDownloadInfoNeed(v: boolean): void {
    this.downloadInfoNeed = v;
  }

  static bookmarkDrawNeedRefresh(): SomethingNeedRefresh {
    const refresh: SomethingNeedRefresh = new SomethingNeedRefresh();
    refresh.setBookmarkDrawNeed(true);
    return refresh;
  }

  static downloadLabelDrawNeedRefresh(): SomethingNeedRefresh {
    const refresh: SomethingNeedRefresh = new SomethingNeedRefresh();
    refresh.setDownloadLabelDrawNeed(true);
    return refresh;
  }

  static downloadInfoNeedRefresh(): SomethingNeedRefresh {
    const refresh: SomethingNeedRefresh = new SomethingNeedRefresh();
    refresh.setDownloadInfoNeed(true);
    return refresh;
  }
}