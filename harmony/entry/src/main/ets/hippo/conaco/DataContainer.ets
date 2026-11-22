/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0013   上游: com/hippo/conaco/DataContainer.java（42 行）
 * 目标   : harmony/entry/src/main/ets/hippo/conaco/DataContainer.ets
 *
 * 平台差异：
 *  1. `java.io.InputStream` → `InputStreamLike`（yorozuya/IOUtils 里定义的跨模块流契约，
 *     read(buffer) 返回 -1 表示 EOF，见 IOUtils.ets 文件头差异 1）。
 *  2. `com.hippo.streampipe.InputStreamPipe` → `streampipe/InputStreamPipe`（net-parse 落的
 *     Maven `com.hippo:streampipe` 等价层，方法为 obtain/release/open/close）。
 *  3. `long length` → `number`；`@Nullable` 语义 → `| null` 联合类型（ArkTS 编译期强制判空，
 *     比 Java 的注解更严格）。
 *  4. 上游注释里的 "Get 304 or something like that" 保留（onUrlMoved 的用途是重定向后修正
 *     URL 与缓存 key 的对应关系）。
 */

import { InputStreamLike } from '../lib/yorozuya/IOUtils';
import { InputStreamPipe } from '../streampipe/InputStreamPipe';
import { ProgressNotifier } from './ProgressNotifier';

export interface DataContainer {

  /**
   * Returns the enabled status for this DataContainer.
   */
  isEnabled(): boolean;

  /**
   * Get 304 or something like that
   */
  onUrlMoved(requestUrl: string, responseUrl: string): void;

  /**
   * Save the InputStream
   */
  save(is: InputStreamLike, length: number, mediaType: string | null,
    notify: ProgressNotifier | null): boolean;

  /**
   * Get InputStreamPipe for saved before
   */
  get(): InputStreamPipe | null;

  /**
   * Remove saved stuff
   */
  remove(): void;
}
