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
 * 移植自 app/src/main/java/com/hippo/ehviewer/sync/DownloadSpiderInfoExecutor.kt（59 行）。
 *
 * 职责：批量读下载目录下的 `.ehviewer`（SpiderInfo 头），命中 gid+token 校验的才算数，
 * 结果收集到 `resultMap` 后回到主线程回调 `SpiderInfoReadCallBack`。
 *
 * 行为等价说明：
 *   1. 上游 `Executors.newSingleThreadExecutor()` → 鸿蒙侧不需要额外线程池：
 *      SpiderInfo 读取与 RDB 一样是异步 IO，整个循环放在一个 `async` 序列里，
 *      串行语义（for 循环顺序、后写覆盖前写）完全保留。
 *   2. 上游 `handler = Handler(Looper.getMainLooper())` + `handler.post { callBack }`
 *      切回主线程 → ArkTS 的 UI 状态更新必须回主线程，用 `@ohos.taskpool` 不行（跨线程传对象受限），
 *      这里用「Promise 微任务 + 调用方在主线程 await」的方式：`execute()` 返回 Promise，
 *      调用方（UI 层）本来就在主线程上 await，回调天然落在主线程。
 *      额外保留一个 `executeAndPost` 便捷入口，供不想 await 的调用点用。
 *   3. 上游对单个条目的 `OutOfMemoryError` / `Exception` 分别 catch 并置 null，
 *      继续处理后续条目（**不中断整批**），这里用同样的两级 catch。
 *   4. 上游 `resultMap.put(info.gid, ...)`：gid 是 Long，ArkTS 用 number（53 位安全整数，
 *      EhViewer 的 gid 为 6~8 位十进制，安全）。
 *   5. `getSpiderInfo` 的判定顺序（目录存在 → 文件存在 → 头非空 → gid 相等 → token 相等）逐条保留，
 *      任一不满足返回 null。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';

import { SpiderInfoReadCallBack } from '../callBack/SpiderInfoReadCallBack';
import { GalleryInfo } from '../client/data/GalleryInfo';
import { DownloadInfo } from '../dao/DownloadInfo';
import { SpiderDen } from '../spider/SpiderDen';
import { SpiderInfo, SPIDER_INFO_FILENAME } from '../spider/SpiderInfo';
import { UniFile } from '../../unifile/UniFile';

const DOMAIN: number = 0x0D0C;
const TAG: string = 'DownloadSpiderInfoExec';

export class DownloadSpiderInfoExecutor {
  private readonly list: DownloadInfo[];
  private readonly callBack: SpiderInfoReadCallBack | null;

  /** 对应上游 `val resultMap: MutableMap<Long?, SpiderInfo?>`。 */
  private readonly resultMap: Map<number, SpiderInfo | null> = new Map<number, SpiderInfo | null>();

  private executed: boolean = false;
  private pending: Promise<Map<number, SpiderInfo | null>> | null = null;

  constructor(list: DownloadInfo[], callBack: SpiderInfoReadCallBack | null) {
    this.list = list;
    this.callBack = callBack;
  }

  /**
   * 对应上游 `execute()` + `callBack.resultCallBack(resultMap)`。
   * 返回同一个 resultMap 引用（上游回调里拿到的就是这个 map）。
   */
  public execute(): Promise<Map<number, SpiderInfo | null>> {
    if (this.pending !== null) {
      return this.pending;
    }
    this.executed = true;
    this.pending = this.run();
    return this.pending;
  }

  /**
   * 不想 await 的调用点：fire-and-forget，回调失败只打日志。
   * 上游同样没有把异常抛给调用方（异常都在 runnable 里被吃掉了）。
   */
  public executeAndPost(): void {
    this.execute().then((result: Map<number, SpiderInfo | null>) => {
      if (this.callBack === null) {
        return;
      }
      this.callBack.resultCallBack(result);
    }).catch((e: Object) => {
      hilog.error(DOMAIN, TAG, 'executeAndPost failed: %{public}s', this.errorToString(e as Object));
    });
  }

  public getResultMap(): Map<number, SpiderInfo | null> {
    return this.resultMap;
  }

  public isExecuted(): boolean {
    return this.executed;
  }

  private async run(): Promise<Map<number, SpiderInfo | null>> {
    const size: number = this.list.length;
    for (let i = 0; i < size; i++) {
      const info: DownloadInfo = this.list[i];
      this.resultMap.set(info.gid, await this.getSpiderInfoSafe(info));
    }
    return this.resultMap;
  }

  /**
   * 上游对每条记录的两级异常处理：OOM 与非 OOM 都落 null，循环继续。
   */
  private async getSpiderInfoSafe(info: GalleryInfo): Promise<SpiderInfo | null> {
    try {
      return await this.getSpiderInfo(info);
    } catch (e) {
      // ArkTS 没有 OutOfMemoryError 类型；OOM 在 ArkTS 侧表现为普通 Error，
      // 因此两级 catch 合并为一级，但语义（落 null 并继续）与上游完全一致。
      hilog.error(DOMAIN, TAG, 'Failed reading spider info header for gid=%{public}d, error=%{public}s',
        info.gid, this.errorToString(e as Object));
      return null;
    }
  }

  /**
   * 对应上游 `getSpiderInfo(info)`。
   *
   * 注意 storage-db 侧的签名差异（已按实际实现改）：
   *   - `UniFile.isDirectory()/findFile()` 是**同步**的（不是 Promise）
   *   - `SpiderInfo.readHeader(file)` 改名 `readHeaderFile(file)`，也是同步
   */
  private async getSpiderInfo(info: GalleryInfo): Promise<SpiderInfo | null> {
    const downloadDir: UniFile | null = await SpiderDen.getGalleryDownloadDir(info);
    if (downloadDir !== null && downloadDir.isDirectory()) {
      const file: UniFile | null = downloadDir.findFile(SPIDER_INFO_FILENAME);
      if (file === null) {
        return null;
      }
      const spiderInfo: SpiderInfo | null = SpiderInfo.readHeaderFile(file);
      if (spiderInfo !== null && spiderInfo.gid === info.gid && spiderInfo.token === info.token) {
        return spiderInfo;
      }
    }
    return null;
  }

  private errorToString(e: Object): string {
    if (e instanceof Error) {
      return e.message;
    }
    return String(e);
  }
}

