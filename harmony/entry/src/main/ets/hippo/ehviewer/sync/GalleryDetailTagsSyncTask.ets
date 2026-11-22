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
 * 移植自 app/src/main/java/com/hippo/ehviewer/sync/GalleryDetailTagsSyncTask.kt（65 行）。
 *
 * 行为等价说明：
 *   1. 上游是 `class GalleryDetailTagsSyncTask(val detail: GalleryDetail) : Thread()`，
 *      把详情页解析出来的 `GalleryTagGroup` 列表摊平成 `GalleryTags` 行写进库：
 *      `EhDB.inGalleryTags(gid)` 为真用 update，否则 insert。这里逐行搬过来，
 *      只是把「派生 Thread」换成「异步方法 + Promise」——ArkTS 没有 Thread，
 *      而 RDB 访问本身就是异步的（`@ohos.data.relationalStore` 全异步 API），
 *      所以 IO 已经天然离开 UI 线程，语义等价。
 *   2. 上游 `@Synchronized override fun start()` 只保证不并发启动；`Thread` 二次 start
 *      会抛 IllegalThreadStateException。这里保持「二次 start 无效 + 打日志」，不抛异常
 *      （调用方是 fire-and-forget，抛异常只会变成未捕获 Promise 拒绝）。
 *   3. `run()` 里 `try { ... } catch (e: Exception) { Log.e(TAG, e.toString()) }`：
 *      失败吞掉不重试，与上游一致。
 *   4. `getTagString(size, group)` 的拼接规则（`,` 分隔、末尾不加逗号）逐字符保留。
 *   5. 未知 groupName 走 `else -> {}`，即静默忽略，与上游一致。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';

import { EhDB } from '../EhDB';
import { GalleryTagGroup } from '../client/data/GalleryTagGroup';
import { GalleryDetail } from '../client/data/GalleryDetail';
import { GalleryTags } from '../dao/GalleryTags';

const DOMAIN: number = 0x0D0C;
const TAG: string = 'GalleryDetailTagsSyncTask';

export class GalleryDetailTagsSyncTask {
  private readonly detail: GalleryDetail;

  /**
   * 上游 `Thread` 的一次性状态：start 过就不再启动。
   * ArkTS 不允许静态可变全局状态跨 Ability 生命周期，所以把状态放在实例上。
   */
  private started: boolean = false;

  /** 当前这一轮的 Promise，供测试/收尾方 join（上游可用 Thread.join()）。 */
  private running: Promise<void> | null = null;

  constructor(detail: GalleryDetail) {
    this.detail = detail;
  }

  /**
   * 对应上游 `start()`：立即返回，不阻塞调用线程。
   */
  public start(): void {
    if (this.started) {
      hilog.warn(DOMAIN, TAG, 'start() ignored: task already started, gid=%{public}d', this.detail.gid);
      return;
    }
    this.started = true;
    this.running = this.run();
  }

  /**
   * 对应上游 `Thread.join()`：等待本次写入结束（含异常已被吞掉的情况）。
   * 未 start 过时立即 resolve。
   */
  public async join(): Promise<void> {
    const pending: Promise<void> | null = this.running;
    if (pending === null) {
      return;
    }
    await pending;
  }

  /**
   * 对应上游 `run()`。
   */
  private async run(): Promise<void> {
    const galleryTags: GalleryTags = this.tags();
    try {
      const exist: boolean = await EhDB.inGalleryTags(this.detail.gid);
      if (exist) {
        await EhDB.updateGalleryTags(galleryTags);
      } else {
        await EhDB.insertGalleryTags(galleryTags);
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'write GalleryTags failed, gid=%{public}d, error=%{public}s',
        this.detail.gid, this.errorToString(e as Object));
    }
  }

  /**
   * 对应上游 `private val tags: GalleryTags`。
   * 注意：`detail.tags` 在 ArkTS 侧为可空的 `GalleryTagGroup[] | null`（上游是 ArrayList，恒非空）。
   */
  private tags(): GalleryTags {
    const tags: GalleryTags = new GalleryTags(this.detail.gid);
    // storage-db 的 GalleryDetail.tags 是 GalleryTagGroup[] | null（详情未解析完时为空）
    const groups: GalleryTagGroup[] | null = this.detail.tags;
    if (groups === null) {
      return tags;
    }
    for (let i = 0; i < groups.length; i++) {
      this.parserData(tags, groups[i]);
    }
    return tags;
  }

  /**
   * 对应上游 `parserData(tags, group)`：按 groupName 落到 GalleryTags 的同名列。
   */
  private parserData(tags: GalleryTags, group: GalleryTagGroup): void {
    const size: number = group.size();
    switch (group.groupName) {
      case 'rows':
        tags.rows = this.getTagString(size, group);
        break;
      case 'artist':
        tags.artist = this.getTagString(size, group);
        break;
      case 'cosplayer':
        tags.cosplayer = this.getTagString(size, group);
        break;
      case 'character':
        tags.character = this.getTagString(size, group);
        break;
      case 'female':
        tags.female = this.getTagString(size, group);
        break;
      case 'group':
        tags.group = this.getTagString(size, group);
        break;
      case 'language':
        tags.language = this.getTagString(size, group);
        break;
      case 'male':
        tags.male = this.getTagString(size, group);
        break;
      case 'misc':
        tags.misc = this.getTagString(size, group);
        break;
      case 'mixed':
        tags.mixed = this.getTagString(size, group);
        break;
      case 'other':
        tags.other = this.getTagString(size, group);
        break;
      case 'parody':
        tags.parody = this.getTagString(size, group);
        break;
      case 'reclass':
        tags.reclass = this.getTagString(size, group);
        break;
      case 'location':
        tags.location = this.getTagString(size, group);
        break;
      default:
        // 上游 `else -> {}`：未知分组静默忽略
        break;
    }
  }

  /**
   * 对应上游 `getTagString(size, group)`：逗号分隔，末尾不留逗号。
   */
  private getTagString(size: number, group: GalleryTagGroup): string {
    let builder: string = '';
    for (let i = 0; i < size; i++) {
      if (i === size - 1) {
        builder += group.getTagAt(i);
      } else {
        builder += group.getTagAt(i) + ',';
      }
    }
    return builder;
  }

  private errorToString(e: Object): string {
    if (e instanceof Error) {
      return e.message;
    }
    return String(e);
  }
}
