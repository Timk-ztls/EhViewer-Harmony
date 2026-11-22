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
 * 下载目录里 `.ehviewer` 元数据文件的**线格式常量**（无依赖叶子模块）。
 *
 * 为什么要单独一个文件：
 *   这两个值原本放在 `DownloadManager.ets`（它 import EhDB → RDB → @ohos.data.relationalStore）。
 *   于是任何"只想拿这两个字符串"的消费者（典型是设置页的导入/导出）都会被拖进整条
 *   RDB 依赖图 —— 宿主单测环境加载不动（实测 `TypeError: Cannot read properties of undefined`），
 *   且 UI 层本不该依赖数据层实现。
 *
 *   移到这里后：`DownloadManager` 继续**re-export**（既有 import 全部不变），
 *   新消费者直接从这里取。**常量只有一处定义**（避免"两处同规则会漂移"）。
 */

/** 下载目录内记录下载元数据的文件名（上游 `DownloadInfo` 的落盘 companion）。 */
export const DOWNLOAD_INFO_FILENAME: string = '.ehviewer';

/** 该文件首行的列定义（顺序即解析顺序，必须与写入端一致）。 */
export const DOWNLOAD_INFO_HEADER: string =
  'gid,token,title,title_jpn,thumb,category,posted,uploader,rating,rated,' +
    'simple_lang,simple_tags,thumb_width,thumb_height,span_size,span_index,' +
    'span_group_index,favorite_slot,favorite_name,pages';