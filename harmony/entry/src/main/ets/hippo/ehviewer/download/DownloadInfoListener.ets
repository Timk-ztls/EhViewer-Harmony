/*
 * Copyright 2026 ehviewer-harmony contributors
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

/**
 * 移植自 app/src/main/java/com/hippo/ehviewer/download/DownloadInfoListener.java（40 行）。
 *
 * 上游这个接口有**两份**：一份是本文件的顶层 `com.hippo.ehviewer.download.DownloadInfoListener`，
 * 另一份是 `DownloadManager.java` 内部的嵌套 `public interface DownloadInfoListener`（成员完全相同，
 * 是历史遗留的重复声明）。外部调用方（DownloadsScene / DownloadAdapter / DownloadFragment …）
 * 用的是顶层那份；`DownloadManager` 内部的字段用的是嵌套那份（同文件作用域优先）。
 *
 * ArkTS 不允许同包同名接口重复声明，所以这里只保留顶层这份，`DownloadManager.ets` import 它。
 * 这是**声明去重**，不是行为变更：两边成员逐一相同，见下方逐条对照。
 *
 * 逐条对照（左：上游 Java，右：本文件）：
 *   onAdd(@NonNull DownloadInfo, @NonNull List<DownloadInfo>, int position)
 *   onReplace(@NonNull DownloadInfo newInfo, @NonNull DownloadInfo oldInfo)
 *   onUpdate(@NonNull DownloadInfo, @NonNull List<DownloadInfo>, LinkedList<DownloadInfo> waitList)
 *   onUpdateAll()
 *   onReload()
 *   onChange()
 *   onRenameLabel(String from, String to)
 *   onRemove(@NonNull DownloadInfo, @NonNull List<DownloadInfo>, int position)
 *   onUpdateLabels()
 *
 * 类型映射：`List<DownloadInfo>` → `DownloadInfo[]`；`LinkedList<DownloadInfo>`（waitList）→ `DownloadInfo[]`
 * （同一份数组引用，调用方不要写它——上游也是只读观察）。
 */

import { DownloadInfo } from '../dao/DownloadInfo';

export interface DownloadInfoListener {
  /**
   * 新增一条下载记录到 `list` 的 `position` 位置。
   */
  onAdd(info: DownloadInfo, list: DownloadInfo[], position: number): void;

  /**
   * 旧记录被新纪录替换（同一 gid）。
   */
  onReplace(newInfo: DownloadInfo, oldInfo: DownloadInfo): void;

  /**
   * 某条记录状态变了。`waitList` 是当前等待队列（只读）。
   */
  onUpdate(info: DownloadInfo, list: DownloadInfo[], waitList: DownloadInfo[]): void;

  /**
   * 全部数据可能变了，但条数不变（批量状态刷新）。
   */
  onUpdateAll(): void;

  /**
   * 全部数据可能变了，条数也可能变了（重新拉全量）。
   */
  onReload(): void;

  /**
   * 该列表已不存在，请回退到默认列表（删除标签时触发）。
   */
  onChange(): void;

  /**
   * 标签改名。
   */
  onRenameLabel(from: string, to: string): void;

  /**
   * 从 `list` 的 `position` 位置移除一条记录。
   */
  onRemove(info: DownloadInfo, list: DownloadInfo[], position: number): void;

  /**
   * 标签列表本身变了（增删改序）。
   */
  onUpdateLabels(): void;
}
