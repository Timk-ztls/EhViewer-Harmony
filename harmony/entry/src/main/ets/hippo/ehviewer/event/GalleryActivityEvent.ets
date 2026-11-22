/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0152   上游: com/hippo/ehviewer/event/GalleryActivityEvent.java（10 行）
 * 目标   : harmony/entry/src/main/ets/hippo/ehviewer/event/GalleryActivityEvent.ets
 *
 * 平台差异：
 *  1. public 字段 → public 字段（上游就是可变公开字段，逐字保留；不改成 getter/setter，
 *     因为调用点是直接赋值语义）。
 *  2. `GalleryInfo` 来自 net-parse（已交付 `client/data/GalleryInfo`）。
 *  3. 上游无 `@NonNull` 但构造器必传 galleryInfo —— 保留为必填。
 */

import { GalleryInfo } from '../client/data/GalleryInfo';

export class GalleryActivityEvent {

  galleryInfo: GalleryInfo;
  pagePosition: number;

  constructor(pagePosition: number, galleryInfo: GalleryInfo) {
    this.galleryInfo = galleryInfo;
    this.pagePosition = pagePosition;
  }
}