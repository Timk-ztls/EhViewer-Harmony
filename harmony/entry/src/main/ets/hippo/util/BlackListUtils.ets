/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0483   上游: com/hippo/util/BlackListUtils.kt（16 行）
 * 目标   : harmony/entry/src/main/ets/hippo/util/BlackListUtils.ets
 *
 * 上游只有一句 `parseBlacklist(comment: GalleryComment): BlackList`：
 *   badgayname = comment.user / angrywith = comment.comment / mode = 1 / add_time = timeNow
 * 上游注释写着"只是稍微修一下，不然会运行报错"——这是**应急补丁**，字段就是这三个。
 *
 * 平台差异：
 *  1. `GalleryComment` 属 net-parse（未交付）→ 参数用最小结构 `GalleryCommentLike {user, comment}`。
 *  2. `BlackList` 是 storage-db 的实体（已交付）→ 直接 import。
 *  3. `timeNow` → 已落地的 `TimeUtils.getTimeNow()`（同一口径的手写格式化，格式与上游一致）。
 */

import { BlackList } from '../ehviewer/dao/BlackList';
import { TimeUtils } from './TimeUtils';

/** 上游 `GalleryComment` 用到的两个字段 */
export interface GalleryCommentLike {
  user: string;
  comment: string;
}

export class BlackListUtils {

  /** 对应上游 `parseBlacklist(comment)`；`mode` 固定 1（上游硬编码） */
  static parseBlacklist(comment: GalleryCommentLike): BlackList {
    const blackList: BlackList = new BlackList();
    blackList.badgayname = comment.user;
    blackList.angrywith = comment.comment;
    blackList.mode = 1;
    blackList.add_time = TimeUtils.getTimeNow();
    return blackList;
  }
}