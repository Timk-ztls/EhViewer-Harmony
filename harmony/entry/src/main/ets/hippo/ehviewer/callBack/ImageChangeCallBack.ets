/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0037   上游: com/hippo/ehviewer/callBack/ImageChangeCallBack.java
 * 目标   : harmony/entry/src/main/ets/hippo/ehviewer/callBack/ImageChangeCallBack.ets
 *
 * 平台差异：
 *  1. `java.io.File` → `string`（路径）——与 FileUtils / AppConfig 全批一致，
 *     回调方拿到的是**绝对路径**，需要句柄时自己用 `fileIo.openSync(path)`。
 *  2. Java interface → ArkTS interface（实现方显式 `implements`）。
 *  3. 上游无 `@NonNull` → 路径**允许为 null**（C-7 第 4 条）：上游在图片被清除时会传 null 表示"无背景图"。
 */

export interface ImageChangeCallBack {

  /** 背景图源变化：`path` 为 null 表示当前没有背景图 */
  backgroundSourceChange(path: string | null): void;
}