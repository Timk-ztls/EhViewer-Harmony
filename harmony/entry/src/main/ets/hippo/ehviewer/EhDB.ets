/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0150   上游: com/hippo/ehviewer/EhDB.java（958 行）
 * 目标   : harmony/entry/src/main/ets/hippo/ehviewer/EhDB.ets
 *
 * 【本批范围】按 Lead 排期，先落**不依赖 DownloadInfo 的 7 个方法**（download-sync 的
 * 7 个文件在等这几个）：
 *   getDownloadDirname / putDownloadDirname
 *   getAllDownloadLabelList / addDownloadLabel / updateDownloadLabel /
 *   removeDownloadLabel / moveDownloadLabel
 * 剩余（DownloadInfo 4 个 + bookmark/favorite/history/tags 等）后续批次继续补。
 *
 * 平台差异：
 *  1. **全层 async（D-012）**：上游 `EhDB` 的方法都是 `synchronized` + 同步返回；
 *     鸿蒙 `relationalStore` 只有异步 API → 全部返回 Promise。调用方必须 await。
 *  2. **没有 `DaoMaster/DaoSession` 的静态初始化**（上游靠 GreenDAO 生成的 sDaoSession）：
 *     ArkTS 版由启动时注入 —— `EhDB.attach(session: DaoSession)`（非上游 API），
 *     未 attach 时所有方法抛 `Error('EhDB is not attached')`（比返回空数组更早暴露接线遗漏）。
 *  3. **`addDownloadLabel` 两个 Java 重载合并**（ArkTS 禁重载，方案 §5-7）：
 *       `addDownloadLabel(String label)`   → 走"按 label 查重，无则插入"
 *       `addDownloadLabel(DownloadLabel)`  → 直接插入（尊重调用方给的 time）
 *     合并为 `addDownloadLabel(label: string | DownloadLabel): Promise<DownloadLabel>`。
 *     **判据是实参类型**（string → 查重路径；DownloadLabel → 直插路径），与上游两重载一致。
 *  4. **`moveDownloadLabel` 签名与 download-sync 转述的不同**：上游是
 *     `moveDownloadLabel(int fromPosition, int toPosition)`（**按位置**，不是按 label 对象），
 *     实现是"按 Time 升序取 [offset, offset+limit) 这段，把 Time 值轮转一格再 updateInTx"。
 *     本实现逐行照搬该算法（含 reverse 的分支与 step 方向）。
 *  5. `@Nullable` → `| null`（C-13）；`List<T>` → `T[]`；`long` → `number`。
 */

import { DaoSession } from './dao/DaoSession';
import { DaoMaster } from './dao/DaoMaster';
import { DownloadDirname } from './dao/DownloadDirname';
import { DownloadDirnameDao } from './dao/DownloadDirnameDao';
import { DownloadLabel } from './dao/DownloadLabel';
import { DownloadLabelDao } from './dao/DownloadLabelDao';
import { GalleryTags } from './dao/GalleryTags';
import { GalleryTagsDao } from './dao/GalleryTagsDao';
import { DownloadInfo } from './dao/DownloadInfo';
import { DownloadsDao } from './dao/DownloadsDao';
import { LocalFavoritesDao } from './dao/LocalFavoritesDao';
import { LocalFavoriteInfo } from './dao/LocalFavoriteInfo';
import { HistoryDao } from './dao/HistoryDao';
import { HistoryInfo } from './dao/HistoryInfo';
import { GalleryInfo } from './client/data/GalleryInfo';
import relationalStore from '@ohos.data.relationalStore';
import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import { ExceptionUtils } from '../util/ExceptionUtils';
import { Settings } from './Settings';
import { QuickSearch } from './dao/QuickSearch';
import { QuickSearchDao } from './dao/QuickSearchDao';
import { Filter } from './dao/Filter';
import { FilterDao } from './dao/FilterDao';
import { BlackList } from './dao/BlackList';
import { BlackListDao } from './dao/BlackListDao';
import { ObjectUtils } from '../lib/yorozuya/ObjectUtils';
import { FileUtils } from '../lib/yorozuya/FileUtils';

export class EhDB {

  private static sDaoSession: DaoSession | null = null;
  private static sContext: common.Context | null = null;
  private static sDatabaseDir: string | null = null;
  private static serialTail: Promise<void> = Promise.resolve();
  private static sBlackListChangeListener: (() => void) | null = null;

  static setBlackListChangeListener(listener: (() => void) | null): void {
    EhDB.sBlackListChangeListener = listener;
  }

  private static notifyBlackListChanged(): void {
    const listener: (() => void) | null = EhDB.sBlackListChangeListener;
    if (listener !== null) {
      listener();
    }
  }

  /**
   * 注入 DaoSession（非上游 API：ArkTS 无 GreenDAO 静态会话）。
   *
   * **顺带刷新 `MAX_HISTORY_COUNT`** —— 上游在 `DBOpenHelper.onCreate()`（EhDB.java:221）里
   * `MAX_HISTORY_COUNT = Settings.getHistoryInfoSize()`，即"**开库时读一次设置**"。
   * 放到 `attach` 里做，是因为 attach 正是"库可用"的那一刻：
   * 若依赖调用方在 attach 之后再补一行赋值，**忘了就是历史永不裁剪**（L-05 的成因）。
   * 幂等：重复 attach 会用当前设置值覆盖，没有副作用。
   */
  static attach(session: DaoSession, context?: common.Context | null, databaseDir?: string | null): void {
    EhDB.sDaoSession = session;
    EhDB.sContext = context !== undefined ? context : null;
    EhDB.sDatabaseDir = databaseDir !== undefined ? databaseDir : null;
    try {
      EhDB.MAX_HISTORY_COUNT = Settings.getHistoryInfoSize();
    } catch (e) {
      // Settings 尚未 attach（读设置会抛）→ 保持默认 100，不阻断 DB 可用性
      ExceptionUtils.throwIfFatal(e as Object);
    }
  }

  static isAttached(): boolean {
    return EhDB.sDaoSession !== null;
  }

  private static session(): DaoSession {
    const s: DaoSession | null = EhDB.sDaoSession;
    if (s === null) {
      throw new Error('EhDB is not attached');
    }
    return s;
  }

  /**
   * 内部串行 FIFO 队列：对位上游 `synchronized` 静态方法语义，
   * 避免异步 `await` 跨越 check-then-insert / 事务窗口发生并发交错。
   * 注意：已处于 serial 内的 `*Internal` 辅助方法绝不能再次调用 `serial()`。
   */
  private static serial<T>(task: () => Promise<T>): Promise<T> {
    const run: Promise<T> = EhDB.serialTail.then((): Promise<T> => task());
    EhDB.serialTail = run.then(
      (): void => {
      },
      (): void => {
      }
    );
    return run;
  }

  private static rotateTimes<T>(items: T[], reverse: boolean,
    getTime: (item: T) => number, setTime: (item: T, time: number) => void): void {
    const limit: number = items.length;
    const step: number = reverse ? 1 : -1;
    const start: number = reverse ? limit - 1 : 0;
    const end: number = reverse ? 0 : limit - 1;
    const toTime: number = getTime(items[end]);
    for (let i = end; reverse ? i < start : i > start; i += step) {
      setTime(items[i], getTime(items[i + step]));
    }
    setTime(items[start], toTime);
  }

  // ── 下载目录映射（上游 L484 / L497）──────────────────────────────────────

  /**
   * 对应上游 getDownloadDirname(long gid)：同步返回 String|null → 异步 string|null
   */
  static async getDownloadDirname(gid: number): Promise<string | null> {
    const raw: DownloadDirname | null =
      await EhDB.session().getDownloadDirnameDao().load(gid);
    if (raw !== null) {
      // getDirname() 的返回类型就是 string | null（C-13），直接透传
      return raw.getDirname();
    }
    return null;
  }

  /**
   * 对应上游 putDownloadDirname(long gid, String dirname)：Insert or update
   */
  static async putDownloadDirname(gid: number, dirname: string): Promise<void> {
    return EhDB.serial((): Promise<void> => EhDB.putDownloadDirnameInternal(gid, dirname));
  }

  private static async putDownloadDirnameInternal(gid: number, dirname: string): Promise<void> {
    const dao: DownloadDirnameDao = EhDB.session().getDownloadDirnameDao();
    const raw: DownloadDirname | null = await dao.load(gid);
    if (raw !== null) { // Update
      raw.setDirname(dirname);
      await dao.update(raw);
    } else { // Insert
      const created: DownloadDirname = new DownloadDirname();
      created.setGid(gid);
      created.setDirname(dirname);
      await dao.insert(created);
    }
  }

  /** 对应上游 removeDownloadDirname(long gid) */
  static async removeDownloadDirname(gid: number): Promise<void> {
    return EhDB.serial((): Promise<void> => EhDB.session().getDownloadDirnameDao().deleteByKey(gid));
  }

  /** 对应上游 updateDownloadDirname(long removeGid, long newGid, String dirname) */
  static async updateDownloadDirname(removeGid: number, newGid: number, dirname: string): Promise<void> {
    return EhDB.serial(async (): Promise<void> => {
      const dao: DownloadDirnameDao = EhDB.session().getDownloadDirnameDao();
      await dao.deleteByKey(removeGid);
      const raw: DownloadDirname | null = await dao.load(newGid);
      if (raw !== null) {
        raw.setDirname(dirname);
        await dao.update(raw);
      } else {
        const created: DownloadDirname = new DownloadDirname();
        created.setGid(newGid);
        created.setDirname(dirname);
        await dao.insert(created);
      }
    });
  }

  // ── 下载标签（上游 L520–L604）───────────────────────────────────────────

  /** 对应上游 getAllDownloadLabelList()：按 Time **升序** */
  static async getAllDownloadLabelList(): Promise<DownloadLabel[]> {
    const dao: DownloadLabelDao = EhDB.session().getDownloadLabelDao();
    return dao.queryBuilder().orderAsc(DownloadLabelDao.Properties.Time).list();
  }

  /**
   * 对应上游两个 addDownloadLabel 重载（见文件头差异 3）。
   * string  → 先按 label 查重，命中直接返回首条；未命中则插入（time = now）
   * DownloadLabel → id 置 null 后直接插入（保留调用方给的 time）
   */
  static async addDownloadLabel(label: string | DownloadLabel): Promise<DownloadLabel> {
    return EhDB.serial(async (): Promise<DownloadLabel> => {
      const dao: DownloadLabelDao = EhDB.session().getDownloadLabelDao();

      if (typeof label === 'string') {
        const found: DownloadLabel[] = await dao.queryBuilder()
          .where(DownloadLabelDao.Properties.Label.eq(label)).list();
        if (found.length > 0) {
          return found[0];
        }
        const raw: DownloadLabel = new DownloadLabel();
        raw.setLabel(label);
        raw.setTime(Date.now());
        raw.setId(await dao.insert(raw));
        return raw;
      }

      const raw: DownloadLabel = label;
      raw.setId(null);
      raw.setId(await dao.insert(raw));
      return raw;
    });
  }

  /** 对应上游 updateDownloadLabel(DownloadLabel raw) */
  static async updateDownloadLabel(raw: DownloadLabel): Promise<void> {
    return EhDB.serial((): Promise<void> => EhDB.session().getDownloadLabelDao().update(raw));
  }

  /** 对应上游 removeDownloadLabel(DownloadLabel raw) */
  static async removeDownloadLabel(raw: DownloadLabel): Promise<void> {
    return EhDB.serial((): Promise<void> => EhDB.session().getDownloadLabelDao().delete(raw));
  }

  /**
   * 对应上游 moveDownloadLabel(int fromPosition, int toPosition)（L575）。
   * **注意：按位置移动，不是按 label 对象**（download-sync 转述的签名不准确）。
   * 算法逐行照搬：取 [offset, offset+limit) 这段按 Time 升序的列表，
   * 把 Time 值沿移动方向轮转一格，最后一个位置接原 end 的 time，再 updateInTx。
   */
  static async moveDownloadLabel(fromPosition: number, toPosition: number): Promise<void> {
    return EhDB.serial(async (): Promise<void> => {
      if (fromPosition === toPosition || fromPosition < 0 || toPosition < 0) {
        return;
      }

      const reverse: boolean = fromPosition > toPosition;
      const offset: number = reverse ? toPosition : fromPosition;
      const limit: number = reverse
        ? fromPosition - toPosition + 1
        : toPosition - fromPosition + 1;

      const dao: DownloadLabelDao = EhDB.session().getDownloadLabelDao();
      const list: DownloadLabel[] = await dao.queryBuilder()
        .orderAsc(DownloadLabelDao.Properties.Time).offset(offset).limit(limit).list();

      if (list.length < limit || list.length <= 1) {
        return;
      }

      EhDB.rotateTimes(
        list,
        reverse,
        (item: DownloadLabel): number => item.getTime(),
        (item: DownloadLabel, time: number): void => {
          item.setTime(time);
        }
      );

      await dao.updateInTx(list);
    });
  }
  // ── 画廊标签（上游 L695–L727）────────────────────────────────────────────
  // 上游 inGalleryTags/queryGalleryTags 用 `queryRaw("where gid =" + gid)` 拼 SQL；
  // ArkTS 侧改用 QueryBuilder 的 `Properties.Gid.eq(gid)` —— **语义相同且不做字符串拼接**。

  /** 对应上游 getAllGalleryTags()：按 Gid **升序** */
  static async getAllGalleryTags(): Promise<GalleryTags[]> {
    const dao: GalleryTagsDao = EhDB.session().getGalleryTagsDao();
    return dao.queryBuilder().orderAsc(GalleryTagsDao.Properties.Gid).list();
  }

  /** 对应上游 inGalleryTags(long gid)：是否存在该 gid 的记录 */
  static async inGalleryTags(gid: number): Promise<boolean> {
    const dao: GalleryTagsDao = EhDB.session().getGalleryTagsDao();
    const list: GalleryTags[] = await dao.queryBuilder()
      .where(GalleryTagsDao.Properties.Gid.eq(gid)).list();
    return list.length !== 0;
  }

  /** 对应上游 queryGalleryTags(long gid)：首条或 null */
  static async queryGalleryTags(gid: number): Promise<GalleryTags | null> {
    const dao: GalleryTagsDao = EhDB.session().getGalleryTagsDao();
    const list: GalleryTags[] = await dao.queryBuilder()
      .where(GalleryTagsDao.Properties.Gid.eq(gid)).list();
    if (list.length === 0) {
      return null;
    }
    return list[0];
  }

  /**
   * 对应上游 insertGalleryTags(GalleryTags)：**覆盖 create_time 与 update_time 为当前时间**
   * （上游写死 `galleryTags.create_time = new Date(); update_time = create_time;`）
   */
  static async insertGalleryTags(galleryTags: GalleryTags): Promise<void> {
    return EhDB.serial((): Promise<void> => EhDB.insertGalleryTagsInternal(galleryTags));
  }

  private static async insertGalleryTagsInternal(galleryTags: GalleryTags): Promise<void> {
    const dao: GalleryTagsDao = EhDB.session().getGalleryTagsDao();
    const now: Date = new Date();
    galleryTags.create_time = now;
    galleryTags.update_time = now;
    await dao.insert(galleryTags);
  }

  /** 对应上游 updateGalleryTags(GalleryTags)：只刷新 update_time */
  static async updateGalleryTags(galleryTags: GalleryTags): Promise<void> {
    return EhDB.serial(async (): Promise<void> => {
      const dao: GalleryTagsDao = EhDB.session().getGalleryTagsDao();
      galleryTags.update_time = new Date();
      await dao.update(galleryTags);
    });
  }

  /** 对应上游 deleteGalleryTags(GalleryTags) */
  static async deleteGalleryTags(galleryTags: GalleryTags): Promise<void> {
    return EhDB.serial((): Promise<void> => EhDB.session().getGalleryTagsDao().delete(galleryTags));
  }
  // ── 下载任务（上游 L422 / L468 / L479）──────────────────────────────────

  /**
   * 对应上游 getAllDownloadInfo()：**按 Time 降序**，并把未完成的 STATE_WAIT/STATE_DOWNLOAD 重置为 STATE_NONE。
   */
  static async getAllDownloadInfo(): Promise<DownloadInfo[]> {
    const dao: DownloadsDao = EhDB.session().getDownloadsDao();
    const list: DownloadInfo[] = await dao.queryBuilder().orderDesc(DownloadsDao.Properties.Time).list();
    for (let i = 0; i < list.length; i++) {
      const info: DownloadInfo = list[i];
      if (info.state === DownloadInfo.STATE_WAIT || info.state === DownloadInfo.STATE_DOWNLOAD) {
        info.state = DownloadInfo.STATE_NONE;
      }
    }
    return list;
  }

  /** 对应上游 moveDownloadInfo(List<DownloadInfo> infos, int fromPosition, int toPosition) */
  static async moveDownloadInfo(infos: DownloadInfo[], fromPosition: number, toPosition: number): Promise<void> {
    return EhDB.serial(async (): Promise<void> => {
      if (fromPosition === toPosition || fromPosition < 0 || toPosition < 0) {
        return;
      }
      const reverse: boolean = fromPosition > toPosition;
      const offset: number = reverse ? toPosition : fromPosition;
      const limit: number = reverse
        ? fromPosition - toPosition + 1
        : toPosition - fromPosition + 1;
      if (offset + limit > infos.length) {
        return;
      }
      const list: DownloadInfo[] = infos.slice(offset, offset + limit);
      if (list.length <= 1) {
        return;
      }
      EhDB.rotateTimes(
        list,
        reverse,
        (item: DownloadInfo): number => item.getTime(),
        (item: DownloadInfo, time: number): void => {
          item.setTime(time);
        }
      );
      await EhDB.session().getDownloadsDao().updateInTx(list);
    });
  }

  /**
   * 对应上游 putDownloadInfo(DownloadInfo)：**load 命中 update，否则 insert**
   */
  static async putDownloadInfo(info: DownloadInfo): Promise<void> {
    return EhDB.serial(async (): Promise<void> => {
      const dao: DownloadsDao = EhDB.session().getDownloadsDao();
      const exist: DownloadInfo | null = await dao.load(info.gid);
      if (exist !== null) {
        await dao.update(info);
      } else {
        await dao.insert(info);
      }
    });
  }

  /** 对应上游 removeDownloadInfo(long gid)：按主键删除 */
  static async removeDownloadInfo(gid: number): Promise<void> {
    return EhDB.serial((): Promise<void> => EhDB.session().getDownloadsDao().deleteByKey(gid));
  }
  /** 对应上游 putHistoryInfo(GalleryInfo)（L837）：命中则只刷 time，否则 fromGalleryInfo 后插入 */
  static async putHistoryInfo(galleryInfo: GalleryInfo): Promise<void> {
    return EhDB.serial(async (): Promise<void> => {
      const dao = EhDB.session().getHistoryDao();
      const info: HistoryInfo | null = await dao.load(galleryInfo.gid);
      const now: number = Date.now();
      if (info !== null) {
        // Update time
        info.time = now;
        await dao.update(info);
      } else {
        // New history
        const created: HistoryInfo = HistoryInfo.fromGalleryInfo(galleryInfo);
        created.time = now;
        await dao.insert(created);
        // **只在"新增"分支裁剪**（上游 L849–L857：update 分支不裁剪）
        await EhDB.trimHistory(dao, EhDB.historyTrimOffset(EhDB.MAX_HISTORY_COUNT));
      }
    });
  }

  /**
   * 历史裁剪的 offset（上游 `putHistoryInfo(GalleryInfo)` L850–L856）：
   * `MAX_HISTORY_COUNT < 1` 时**用 100 兜底**（不是 0 —— offset 0 会把整表删光）。
   */
  static historyTrimOffset(maxHistoryCount: number): number {
    return (maxHistoryCount < 1) ? 100 : maxHistoryCount;
  }

  /**
   * 列表版裁剪的 offset（上游 `putHistoryInfo(List)` L869–L871）：
   * ⚠️ **这个重载没有 `< 1` 的兜底**（与单条版不一致，是上游缺陷）。
   * 若 `MAX_HISTORY_COUNT` 被改成 0/负数，这里会 `offset(≤0)` → **历史被清空**。
   * 照搬上游（两处不一致本身是行为），但把差异显式写成两个方法，避免后人"顺手统一"。
   */
  static historyListTrimOffset(maxHistoryCount: number): number {
    return maxHistoryCount;
  }

  /**
   * 按 Time 降序保留最新的 N 条，删除其余（上游 `dao.queryBuilder().orderDesc(Time).limit(-1).offset(N).list()` + `deleteInTx`）。
   * @returns 实际删除的条数
   */
  static async trimHistory(dao: HistoryDao, offset: number): Promise<number> {
    if (offset <= 0) {
      // offset <= 0 时 SQL 会变成"从头取全部 → 全删"，上游在此处靠调用方保证 offset>0。
      // 单条版有 100 兜底；列表版没有 → 这里**保守不删**（比"静默清空历史"安全，B 类修复）。
      return 0;
    }
    const list: HistoryInfo[] = await dao.queryBuilder()
      .orderDesc(HistoryDao.Properties.Time)
      .limit(-1)
      .offset(offset)
      .list();
    if (list.length === 0) {
      return 0;
    }
    await dao.deleteInTx(list);
    return list.length;
  }

  /**
   * 对应上游 `putHistoryInfo(List<HistoryInfo>)`（L861–L872）：
   * **只插入不存在的**（不刷 time）。
   *
   * ⚠️ **末尾不裁剪**（R-12）：上游这个方法体在 for 循环后就结束了，**没有 trim**。
   * 只有单条版 `putHistoryInfo(GalleryInfo)` 才在插入后裁剪。
   * 之前的实现多了一句 trim（L-05 的修复被溢用到这里），后果是
   * **导入 500 条历史当场只留 100 条 → 400 条永久消失**（源库若已删不可恢复）。
   * 现在是"导入多少留多少，之后随浏览逐步裁" —— 与上游一致。
   */
  static async putHistoryInfoList(historyInfoList: HistoryInfo[]): Promise<void> {
    return EhDB.serial((): Promise<void> => EhDB.putHistoryInfoListInternal(historyInfoList));
  }

  private static async putHistoryInfoListInternal(historyInfoList: HistoryInfo[]): Promise<void> {
    const dao = EhDB.session().getHistoryDao();
    for (let i = 0; i < historyInfoList.length; i++) {
      const info: HistoryInfo = historyInfoList[i];
      const existing: HistoryInfo | null = await dao.load(info.gid);
      if (existing === null) {
        await dao.insert(info);
      }
    }
  }


  // ── 数据库迁移（上游 EhDB.upgradeDB，L109–L185）──────────────────────────
  // 六级链，**逐字保留上游 SQL 文本**（表名/列名/顺序/默认值全部一致，P3 验收要求能导入原 App 的 .db）。
  //
  // 三点与上游的**刻意差异**（Lead 已批准）：
  //  1. Java `switch` 依赖 fall-through（`case 2:` 无 break）；ArkTS 虽然也 fall-through，
  //     但改用 `if (oldVersion < n)` **顺序判断** —— 防止后来者补一个 break 就静默改变语义。
  //  2. **整条迁移包在一个事务里**：任一级抛错 → rollBack。半迁移的库比旧库更危险。
  //  3. 两条 `ALTER TABLE ... ADD COLUMN` 单独 try/catch 吞"列已存在"（老库可能已被更早版本改过），
  //     与上游一致；其余语句的错误**不吞**，直接冒泡触发回滚。

  static async migrate(store: relationalStore.RdbStore, oldVersion: number): Promise<void> {
    if (oldVersion >= 8) {
      return;
    }
    store.beginTransaction();
    try {
      // 1 → 2：建 FILTER 表（上游 SCHEMA_VERSION 2 新增）
      if (oldVersion < 2) {
        await FilterDao.createTable(store, true);
      }

      // 2 → 3：给 FILTER 加 ENABLE 列（重建表 + 拷数据，ENABLE 默认拷 1）
      if (oldVersion < 3) {
        await store.executeSql('CREATE TABLE "FILTER2" ('
          + '"_id" INTEGER PRIMARY KEY ,'
          + '"MODE" INTEGER NOT NULL ,'
          + '"TEXT" TEXT,'
          + '"ENABLE" INTEGER);');
        await store.executeSql('INSERT INTO "FILTER2" ('
          + '_id, MODE, TEXT, ENABLE)'
          + 'SELECT _id, MODE, TEXT, 1 FROM [FILTER];');
        await store.executeSql('DROP TABLE [FILTER]');
        await store.executeSql('ALTER TABLE FILTER2 RENAME TO [FILTER]');
      }

      // 3 → 4：给 QUICK_SEARCH 加 PAGE_FROM / PAGE_TO（默认拷 -1）
      if (oldVersion < 4) {
        await store.executeSql('CREATE TABLE "QUICK_SEARCH2" ('
          + '"_id" INTEGER PRIMARY KEY ,'
          + '"NAME" TEXT,'
          + '"MODE" INTEGER NOT NULL ,'
          + '"CATEGORY" INTEGER NOT NULL ,'
          + '"KEYWORD" TEXT,'
          + '"ADVANCE_SEARCH" INTEGER NOT NULL ,'
          + '"MIN_RATING" INTEGER NOT NULL ,'
          + '"PAGE_FROM" INTEGER NOT NULL ,'
          + '"PAGE_TO" INTEGER NOT NULL ,'
          + '"TIME" INTEGER NOT NULL );');
        await store.executeSql('INSERT INTO "QUICK_SEARCH2" ('
          + '_id, NAME, MODE, CATEGORY, KEYWORD, ADVANCE_SEARCH, MIN_RATING, PAGE_FROM, PAGE_TO, TIME)'
          + 'SELECT _id, NAME, MODE, CATEGORY, KEYWORD, ADVANCE_SEARCH, MIN_RATING, -1, -1, TIME FROM QUICK_SEARCH;');
        await store.executeSql('DROP TABLE QUICK_SEARCH');
        await store.executeSql('ALTER TABLE QUICK_SEARCH2 RENAME TO QUICK_SEARCH');
      }

      // 4 → 5：重建 Black_List（上游是 DROP + CREATE，数据不保留）
      if (oldVersion < 5) {
        await store.executeSql('DROP TABLE IF EXISTS "Black_List"');
        await store.executeSql('CREATE TABLE "Black_List" ('
          + '"_id" INTEGER PRIMARY KEY AUTOINCREMENT ,'
          + '"BADGAYNAME" TEXT,'
          + '"REASON" TEXT,'
          + '"ANGRYWITH" TEXT,'
          + '"ADD_TIME" TEXT,'
          + '"MODE" INTEGER);');
      }

      // 5 → 6：重建 Gallery_Tags（16 列，上游同样 DROP + CREATE）
      if (oldVersion < 6) {
        await store.executeSql('DROP TABLE IF EXISTS "Gallery_Tags"');
        await store.executeSql('CREATE TABLE "Gallery_Tags" ('
          + '"GID" INTEGER PRIMARY KEY NOT NULL ,'
          + '"ROWS" TEXT,'
          + '"ARTIST" TEXT,'
          + '"COSPLAYER" TEXT,'
          + '"CHARACTER" TEXT,'
          + '"FEMALE" TEXT,'
          + '"GROUP" TEXT,'
          + '"LANGUAGE" TEXT,'
          + '"MALE" TEXT,'
          + '"MISC" TEXT,'
          + '"MIXED" TEXT,'
          + '"OTHER" TEXT,'
          + '"PARODY" TEXT,'
          + '"RECLASS" TEXT,'
          + '"CREATE_TIME" INTEGER,'
          + '"UPDATE_TIME" INTEGER);');
      }

      // 6 → 7：DOWNLOADS 加 ARCHIVE_URI（列可能已存在）
      if (oldVersion < 7) {
        try {
          await store.executeSql('ALTER TABLE "DOWNLOADS" ADD COLUMN "ARCHIVE_URI" TEXT');
        } catch (e) {
          // Column might already exist, ignore the error
        }
      }

      // 7 → 8：Gallery_Tags 加 LOCATION（列可能已存在）
      if (oldVersion < 8) {
        try {
          await store.executeSql('ALTER TABLE "Gallery_Tags" ADD COLUMN "LOCATION" TEXT');
        } catch (e) {
          // Column might already exist, ignore the error
        }
      }

      // **迁移完成后写回 user_version**（R-10）。
      // 上游是 `if (oldVersion < newVersion) { upgradeDB(...); db.setVersion(newVersion); }`
      // —— 写版本与迁移是**同一个动作**。之前把它留给调用方：`AppWiring` 补了、`importDB` 没补
      // → 同一个 migrate 的两个调用方行为不一致（导入的外部库版本停在旧值 → 再导入会重跑整条迁移链）。
      // 放在 commit 之前：version 写失败则整条迁移一起回滚，不会留下"表已改、版本还是旧的"。
      await EhDB.setStoreVersion(store, DaoMaster.SCHEMA_VERSION);

      store.commit();
    } catch (e) {
      store.rollBack();
      throw e as Error;
    }
  }

  /**
   * 写 `user_version`（对应上游 `db.setVersion(int)`）。
   * ⚠️ SQLite 的 `PRAGMA user_version = ?` **不支持参数绑定** → 只能拼字面量；
   * 这里用整数校验挡住注入（版本号本来就只能是整数）。
   */
  static async setStoreVersion(store: relationalStore.RdbStore, version: number): Promise<void> {
    if (!Number.isSafeInteger(version) || version < 0) {
      throw new Error(`invalid schema version: ${version}`);
    }
    await store.executeSql(`PRAGMA user_version = ${version}`);
  }

  /** 对应上游 clearDownloadDirname()：清空 DOWNLOAD_DIRNAME 表（dao.deleteAll） */
  static async clearDownloadDirname(): Promise<void> {
    return EhDB.serial((): Promise<void> => EhDB.session().getDownloadDirnameDao().deleteAll());
  }
  // ── 本地收藏（上游 L605–L663）────────────────────────────────────────────
  // 上游 `List<GalleryInfo>` 里装的实际是 `LocalFavoriteInfo`（子类），故直接返回子类数组。
  // 上游 `searchLocalFavorites(long)` 是**返回单个 GalleryInfo** 且 `list.get(0)` 空表会抛；
  // 按 C-13 本实现返回 `LocalFavoriteInfo | null`（空表 → null），语义比上游更安全。

  /** 上游 MAX_HISTORY_COUNT = 100（L84，public static int，可被改） */
  static MAX_HISTORY_COUNT: number = 100;

  /** 对应上游 getAllLocalFavorites()：按 Time **降序** */
  static async getAllLocalFavorites(): Promise<LocalFavoriteInfo[]> {
    const dao: LocalFavoritesDao = EhDB.session().getLocalFavoritesDao();
    return dao.queryBuilder().orderDesc(LocalFavoritesDao.Properties.Time).list();
  }

  /** 对应上游 searchLocalFavorites(String query)：按标题模糊匹配，Time 降序 */
  static async searchLocalFavorites(query: string): Promise<LocalFavoriteInfo[]> {
    const dao: LocalFavoritesDao = EhDB.session().getLocalFavoritesDao();
    // 上游用 SqlUtils.sqlEscapeString("%"+query+"%") 再 like；ArkTS 侧 like() 走参数绑定，无需手工转义
    return dao.queryBuilder().orderDesc(LocalFavoritesDao.Properties.Time)
      .where(LocalFavoritesDao.Properties.Title.like(`%${query}%`)).list();
  }

  /** 对应上游 searchLocalFavorites(long query)：按 gid 精确查，空表返回 null（上游 get(0) 会抛） */
  static async searchLocalFavoritesByGid(query: number): Promise<LocalFavoriteInfo | null> {
    const dao: LocalFavoritesDao = EhDB.session().getLocalFavoritesDao();
    const list: LocalFavoriteInfo[] = await dao.queryBuilder()
      .orderDesc(LocalFavoritesDao.Properties.Time)
      .where(LocalFavoritesDao.Properties.Gid.eq(query)).list();
    if (list.length === 0) {
      return null;
    }
    return list[0];
  }

  /** 对应上游 removeLocalFavorites(long gid) */
  static async removeLocalFavorites(gid: number): Promise<void> {
    return EhDB.serial((): Promise<void> => EhDB.session().getLocalFavoritesDao().deleteByKey(gid));
  }

  /** 对应上游 removeLocalFavorites(long[] gidArray)：逐个 deleteByKey */
  static async removeLocalFavoritesRange(gidArray: number[]): Promise<void> {
    return EhDB.serial(async (): Promise<void> => {
      const dao: LocalFavoritesDao = EhDB.session().getLocalFavoritesDao();
      for (let i = 0; i < gidArray.length; i++) {
        await dao.deleteByKey(gidArray[i]);
      }
    });
  }

  /** 对应上游 containLocalFavorites(long gid) */
  static async containLocalFavorites(gid: number): Promise<boolean> {
    const dao: LocalFavoritesDao = EhDB.session().getLocalFavoritesDao();
    return (await dao.load(gid)) !== null;
  }

  static async putLocalFavorite(galleryInfo: GalleryInfo): Promise<void> {
    return EhDB.serial((): Promise<void> => EhDB.putLocalFavoriteInternal(galleryInfo));
  }

  private static async putLocalFavoriteInternal(galleryInfo: GalleryInfo): Promise<void> {
    const dao: LocalFavoritesDao = EhDB.session().getLocalFavoritesDao();
    if ((await dao.load(galleryInfo.gid)) !== null) {
      return;
    }
    let info: LocalFavoriteInfo;
    if (galleryInfo instanceof LocalFavoriteInfo) {
      info = galleryInfo as LocalFavoriteInfo;
    } else {
      info = LocalFavoriteInfo.fromGalleryInfo(galleryInfo);
      info.time = Date.now();
    }
    await dao.insert(info);
  }

  /** 对应上游 putLocalFavorites(List)：逐个 putLocalFavorite（逐个判存在，与上游一致） */
  static async putLocalFavorites(galleryInfoList: GalleryInfo[]): Promise<void> {
    return EhDB.serial(async (): Promise<void> => {
      for (let i = 0; i < galleryInfoList.length; i++) {
        await EhDB.putLocalFavoriteInternal(galleryInfoList[i]);
      }
    });
  }

  // ── 历史（上游 L833–L881）────────────────────────────────────────────────

  /** 对应上游 getHistoryLazyList()：LazyList → 数组（按 Time 降序） */
  static async getHistoryLazyList(): Promise<HistoryInfo[]> {
    const dao: HistoryDao = EhDB.session().getHistoryDao();
    return dao.queryBuilder().orderDesc(HistoryDao.Properties.Time).listLazy();
  }

  /** 对应上游 deleteHistoryInfo(HistoryInfo) */
  static async deleteHistoryInfo(info: HistoryInfo): Promise<void> {
    return EhDB.serial((): Promise<void> => EhDB.session().getHistoryDao().delete(info));
  }

  /** 对应上游 clearHistoryInfo()：deleteAll */
  static async clearHistoryInfo(): Promise<void> {
    return EhDB.serial((): Promise<void> => EhDB.session().getHistoryDao().deleteAll());
  }

  // ── 快速搜索 / 过滤器 / 黑名单（importDB 逐表合并要用；语义照搬上游）──────

  /** 对应上游 getAllQuickSearch()：按 Time 升序 */
  static async getAllQuickSearch(): Promise<QuickSearch[]> {
    const dao: QuickSearchDao = EhDB.session().getQuickSearchDao();
    return dao.queryBuilder().orderAsc(QuickSearchDao.Properties.Time).list();
  }

  /**
   * 对应上游 `insertQuickSearch(QuickSearch)`（L737–L745）：
   * **id 强制置 null**（= 由库分配新主键，避免与目标库已有 id 冲撞）；`time == 0` 时补当前时间。
   */
  static async insertQuickSearch(quickSearch: QuickSearch): Promise<void> {
    return EhDB.serial((): Promise<void> => EhDB.insertQuickSearchInternal(quickSearch));
  }

  private static async insertQuickSearchInternal(quickSearch: QuickSearch): Promise<void> {
    const dao: QuickSearchDao = EhDB.session().getQuickSearchDao();
    quickSearch.id = null;
    if (quickSearch.time === 0) {
      quickSearch.time = Date.now();
    }
    quickSearch.id = await dao.insert(quickSearch);
  }

  /** 对应上游 insertQuickSearchList(List<QuickSearch>) */
  static async insertQuickSearchList(quickSearchList: QuickSearch[]): Promise<void> {
    return EhDB.serial(async (): Promise<void> => {
      const dao: QuickSearchDao = EhDB.session().getQuickSearchDao();
      for (let i = 0; i < quickSearchList.length; i++) {
        const search: QuickSearch = quickSearchList[i];
        search.id = null;
        search.time = Date.now();
        search.id = await dao.insert(search);
      }
    });
  }

  /** 对应上游 takeOverQuickSearchList(List<QuickSearch>)：按 keyword 去重增量接管 */
  static async takeOverQuickSearchList(quickSearchList: QuickSearch[]): Promise<void> {
    return EhDB.serial(async (): Promise<void> => {
      const dao: QuickSearchDao = EhDB.session().getQuickSearchDao();
      const allList: QuickSearch[] = await dao.queryBuilder()
        .orderAsc(QuickSearchDao.Properties.Time).list();
      for (let i = 0; i < quickSearchList.length; i++) {
        const newSearch: QuickSearch = quickSearchList[i];
        let shouldInsert: boolean = true;
        for (let j = 0; j < allList.length; j++) {
          const exist: QuickSearch = allList[j];
          if (ObjectUtils.equal(exist.keyword, newSearch.keyword)) {
            shouldInsert = false;
            break;
          }
        }
        if (shouldInsert) {
          newSearch.id = null;
          newSearch.time = Date.now();
          newSearch.id = await dao.insert(newSearch);
          allList.push(newSearch);
        }
      }
    });
  }

  /** 对应上游 updateQuickSearch(QuickSearch) */
  static async updateQuickSearch(quickSearch: QuickSearch): Promise<void> {
    return EhDB.serial((): Promise<void> => EhDB.session().getQuickSearchDao().update(quickSearch));
  }

  /** 对应上游 deleteQuickSearch(QuickSearch) */
  static async deleteQuickSearch(quickSearch: QuickSearch): Promise<void> {
    return EhDB.serial((): Promise<void> => EhDB.session().getQuickSearchDao().delete(quickSearch));
  }

  /** 对应上游 moveQuickSearch(int fromPosition, int toPosition) */
  static async moveQuickSearch(fromPosition: number, toPosition: number): Promise<void> {
    return EhDB.serial(async (): Promise<void> => {
      if (fromPosition === toPosition || fromPosition < 0 || toPosition < 0) {
        return;
      }
      const reverse: boolean = fromPosition > toPosition;
      const offset: number = reverse ? toPosition : fromPosition;
      const limit: number = reverse
        ? fromPosition - toPosition + 1
        : toPosition - fromPosition + 1;
      const dao: QuickSearchDao = EhDB.session().getQuickSearchDao();
      const list: QuickSearch[] = await dao.queryBuilder()
        .orderAsc(QuickSearchDao.Properties.Time).offset(offset).limit(limit).list();
      if (list.length < limit || list.length <= 1) {
        return;
      }
      EhDB.rotateTimes(
        list,
        reverse,
        (item: QuickSearch): number => item.getTime(),
        (item: QuickSearch, time: number): void => {
          item.setTime(time);
        }
      );
      await dao.updateInTx(list);
    });
  }

  /** 整表读取 QuickSearch（兼容已有调用方；按 Time 升序优先用 getAllQuickSearch） */
  static async getQuickSearchList(): Promise<QuickSearch[]> {
    return await EhDB.session().getQuickSearchDao().loadAll();
  }

  /** 对应上游 `addFilter(Filter)`（L888–L891）：id 置 null 后插入并回填 id */
  static async addFilter(filter: Filter): Promise<void> {
    return EhDB.serial((): Promise<void> => EhDB.addFilterInternal(filter));
  }

  private static async addFilterInternal(filter: Filter): Promise<void> {
    filter.setId(null);
    const id: number = await EhDB.session().getFilterDao().insert(filter);
    filter.setId(id);
  }

  /** 整表读取（importDB 按 `Filter.equals`（mode+text）去重要用） */
  static async getAllFilter(): Promise<Filter[]> {
    return await EhDB.session().getFilterDao().loadAll();
  }

  /**
   * 对应上游 `deleteFilter(Filter)`。
   * @param filter 必须有 id（`addFilter` 会把插入后的 id 回填）
   */
  static async deleteFilter(filter: Filter): Promise<void> {
    return EhDB.serial((): Promise<void> => EhDB.session().getFilterDao().delete(filter));
  }

  /**
   * 对应上游 `triggerFilter(Filter)`（`EhDB.java:897`）：翻转 enable 并落库。
   */
  static async triggerFilter(filter: Filter): Promise<void> {
    return EhDB.serial(async (): Promise<void> => {
      filter.enable = !(filter.enable === true);
      await EhDB.session().getFilterDao().update(filter);
    });
  }

  /** 对应上游 getAllBlackList()：按 Add_time 升序 */
  static async getAllBlackList(): Promise<BlackList[]> {
    const dao: BlackListDao = EhDB.session().getBlackListDao();
    return dao.queryBuilder().orderAsc(BlackListDao.Properties.Add_time).list();
  }

  /** 对应上游 inBlackList(String badgayname)：参数化查询（防止 SQL 注入） */
  static async inBlackList(badgayname: string): Promise<boolean> {
    const dao: BlackListDao = EhDB.session().getBlackListDao();
    const list: BlackList[] = await dao.queryBuilder()
      .where(BlackListDao.Properties.Badgayname.eq(badgayname)).list();
    return list.length !== 0;
  }

  /**
   * 对应上游 `insertBlackList(BlackList)`（L676–L684）：
   * **`badgayname == null` 直接 return（静默丢弃！）**、id 置 null 后插入。
   */
  static async insertBlackList(blackList: BlackList): Promise<void> {
    await EhDB.serial((): Promise<void> => EhDB.insertBlackListInternal(blackList));
    if (blackList.badgayname !== null) {
      EhDB.notifyBlackListChanged();
    }
  }

  private static async insertBlackListInternal(blackList: BlackList): Promise<void> {
    const dao: BlackListDao = EhDB.session().getBlackListDao();
    blackList.id = null;
    if (blackList.badgayname === null) {
      return;
    }
    await dao.insert(blackList);
  }

  /** 对应上游 updateBlackList(BlackList) */
  static async updateBlackList(blackList: BlackList): Promise<void> {
    await EhDB.serial((): Promise<void> => EhDB.session().getBlackListDao().update(blackList));
    EhDB.notifyBlackListChanged();
  }

  /** 对应上游 deleteBlackList(BlackList) */
  static async deleteBlackList(blackList: BlackList): Promise<void> {
    await EhDB.serial((): Promise<void> => EhDB.session().getBlackListDao().delete(blackList));
    EhDB.notifyBlackListChanged();
  }

  /** 整表读取（importDB 用；上游靠 `contains` 引用比较 → 恒 false） */
  static async getBlackListList(): Promise<BlackList[]> {
    return await EhDB.session().getBlackListDao().loadAll();
  }

  // ── 数据库导出/导入（上游 L913–L1070，Lead 裁定归 core-runtime）──────────
  //
  // 上游 exportDB：
  //   1) 确保源库有 ARCHIVE_URI 列（try/catch 吞"已存在"）
  //   2) 删旧导出库 → 建临时库 "eh.export.db"
  //   3) copyDao 逐表拷贝 8 张表（Downloads / DownloadLabel / DownloadDirname / History /
  //      QuickSearch / LocalFavorites / Bookmarks / Filter）
  //   4) 把临时库文件复制到目标路径；任何失败 → 删目标文件并返回 false
  //   5) finally 删临时库
  // 上游 importDB：
  //   1) 打开源文件库，比对版本：低于当前 → upgradeDB + setVersion；高于当前 → 返回 "无法读取"
  //   2) 依次合并 label/downloads(dirname/history/quicksearch/favorites/filter/blacklist/tags)，
  //      进度 10/50/90 三次回调
  //   3) 返回**错误消息字符串**，null 表示成功
  //
  // 平台改写：
  //   · `File` → `string` 路径（与 ImageChangeCallBack / AppConfig 一致）
  //   · `Handler` 进度 → 回调 `(percent) => void`
  //   · 临时库用 `relationalStore.getRdbStore(ctx, {name:'eh.export.db'})`；拷表用
  //     `loadAll()` + `insertInTx()`（逐表，任一失败返回 false，与上游 copyDao 语义一致）
  //   · **文件级复制**需要数据库文件的真实路径：`store.path` 若不可用，则退化为
  //     "导出一份空库 + 逐表拷贝后由调用方决定落点"（见 exportDB 注释）
  //   · **Downloads / DownloadLabel 的合并走 DownloadManager**（download-sync 作用域），
  //     这里用回调注入 `mergeDownloads/mergeLabels`，其余表在本类内直接合并。

  /** 导出临时库名（上游 `eh.export.db`） */
  static readonly EXPORT_DB_NAME: string = 'eh.export.db';

  private static resolveExportDbFilePath(): string | null {
    if (EhDB.sDatabaseDir === null || EhDB.sDatabaseDir.length === 0) {
      return null;
    }
    const candidates: string[] = [
      EhDB.sDatabaseDir + '/rdb/' + EhDB.EXPORT_DB_NAME,
      EhDB.sDatabaseDir + '/' + EhDB.EXPORT_DB_NAME
    ];
    for (let i = 0; i < candidates.length; i++) {
      const p: string = candidates[i];
      try {
        if (fs.accessSync(p) && fs.statSync(p).isFile()) {
          return p;
        }
      } catch (e) {
        // try next candidate path
      }
    }
    return null;
  }

  /**
   * 对应上游 exportDB(Context, File)。
   * @param store 已打开的源库（通常是 DaoMaster 建的那个）
   * @param targetPath 导出目标路径（.db）
   * @param openExportStore 由调用方提供"创建临时库"的能力（`relationalStore.getRdbStore` 的薄封装）
   */
  static async exportDB(store: relationalStore.RdbStore, targetPath: string,
    openExportStore: (name: string) => Promise<relationalStore.RdbStore>,
    deleteExportStore?: ((name: string) => Promise<void>) | null,
    copyExportFile?: ((exportDbName: string, destPath: string) => Promise<boolean>) | null): Promise<boolean> {
    return EhDB.serial(async (): Promise<boolean> => {
      // 1) 确保源库有 ARCHIVE_URI 列（列可能已存在）
      try {
        await store.executeSql('ALTER TABLE "DOWNLOADS" ADD COLUMN "ARCHIVE_URI" TEXT');
      } catch (e) {
        ExceptionUtils.throwIfFatal(e as Object);
      }

      const cleanExportDb = async (): Promise<void> => {
        try {
          if (deleteExportStore !== undefined && deleteExportStore !== null) {
            await deleteExportStore(EhDB.EXPORT_DB_NAME);
          } else if (EhDB.sContext !== null) {
            await relationalStore.deleteRdbStore(EhDB.sContext, EhDB.EXPORT_DB_NAME);
          }
        } catch (e) {
          ExceptionUtils.throwIfFatal(e as Object);
        }
      };

      let exportStore: relationalStore.RdbStore | null = null;
      let storeClosed: boolean = false;
      try {
        // 2) 清旧导出临时库，再建 schema v8
        await cleanExportDb();
        exportStore = await openExportStore(EhDB.EXPORT_DB_NAME);
        await DaoMaster.createAllTables(exportStore, false);
        exportStore.version = DaoMaster.SCHEMA_VERSION;

        // 3) 逐表拷贝（任一失败 → 整体失败，与上游 copyDao 短路一致）
        const session: DaoSession = EhDB.session();
        const exportSession: DaoSession = DaoSession.fromStore(exportStore);
        const tables: string[] = [
          'DOWNLOADS',
          'DOWNLOAD_LABELS',
          'DOWNLOAD_DIRNAME',
          'HISTORY',
          'QUICK_SEARCH',
          'LOCAL_FAVORITES',
          'BOOKMARKS',
          'FILTER',
          'Black_List',
          'Gallery_Tags'
        ];
        for (let i = 0; i < tables.length; i++) {
          await EhDB.copyTableByName(session, exportSession, tables[i]);
        }

        await exportStore.close();
        storeClosed = true;

        // 4) 写出真实导出文件到 targetPath
        if (copyExportFile !== undefined && copyExportFile !== null) {
          const copied: boolean = await copyExportFile(EhDB.EXPORT_DB_NAME, targetPath);
          if (!copied) {
            FileUtils.delete(targetPath);
            return false;
          }
          return true;
        }

        const srcPath: string | null = EhDB.resolveExportDbFilePath();
        if (srcPath === null) {
          FileUtils.delete(targetPath);
          return false;
        }
        const slashIdx: number = targetPath.lastIndexOf('/');
        if (slashIdx > 0) {
          FileUtils.ensureDirectory(targetPath.substring(0, slashIdx));
        }
        FileUtils.delete(targetPath);
        fs.copyFileSync(srcPath, targetPath);
        return true;
      } catch (e) {
        ExceptionUtils.throwIfFatal(e as Object);
        FileUtils.delete(targetPath);
        return false;
      } finally {
        if (exportStore !== null && !storeClosed) {
          try {
            await exportStore.close();
          } catch (closeErr) {
            ExceptionUtils.throwIfFatal(closeErr as Object);
          }
        }
        await cleanExportDb();
      }
    });
  }

  /**
   * 逐表拷贝：源 session 的 `loadAll()` → 目标 session 的 `insertInTx()`。
   * ArkTS 禁对象字面量作类型、禁 `Function.call/apply`，故按表名显式分支（不用反射）。
   */
  private static async copyTableByName(from: DaoSession, to: DaoSession, table: string): Promise<void> {
    if (table === 'DOWNLOADS') {
      await to.getDownloadsDao().insertInTx(await from.getDownloadsDao().loadAll());
    } else if (table === 'DOWNLOAD_LABELS') {
      await to.getDownloadLabelDao().insertInTx(await from.getDownloadLabelDao().loadAll());
    } else if (table === 'DOWNLOAD_DIRNAME') {
      await to.getDownloadDirnameDao().insertInTx(await from.getDownloadDirnameDao().loadAll());
    } else if (table === 'HISTORY') {
      await to.getHistoryDao().insertInTx(await from.getHistoryDao().loadAll());
    } else if (table === 'QUICK_SEARCH') {
      await to.getQuickSearchDao().insertInTx(await from.getQuickSearchDao().loadAll());
    } else if (table === 'LOCAL_FAVORITES') {
      await to.getLocalFavoritesDao().insertInTx(await from.getLocalFavoritesDao().loadAll());
    } else if (table === 'BOOKMARKS') {
      await to.getBookmarksBao().insertInTx(await from.getBookmarksBao().loadAll());
    } else if (table === 'FILTER') {
      await to.getFilterDao().insertInTx(await from.getFilterDao().loadAll());
    } else if (table === 'Black_List') {
      await to.getBlackListDao().insertInTx(await from.getBlackListDao().loadAll());
    } else if (table === 'Gallery_Tags') {
      await to.getGalleryTagsDao().insertInTx(await from.getGalleryTagsDao().loadAll());
    }
  }

  /**
   * 对应上游 importDB(Context, File, Handler)。
   * **返回错误消息，null 表示成功**（上游 `@return error string, null for no error`）。
   *
   * @param sourceStore 已打开的外部 .db（调用方用 `getRdbStore` 指向该文件后传入）
   * @param onProgress 进度回调（上游 Handler，10/50/90 三次）
   * @param mergeDownloads 注入：合并外部 Downloads（接收迁至 v8 后读出的 DownloadInfo[]）
   * @param mergeLabels 注入：合并外部 DownloadLabel（接收迁至 v8 后读出的 DownloadLabel[]）
   */
  static async importDB(sourceStore: relationalStore.RdbStore,
    onProgress: ((percent: number) => void) | null,
    mergeDownloads: ((list: DownloadInfo[]) => Promise<void>) | null,
    mergeLabels: ((list: DownloadLabel[]) => Promise<void>) | null): Promise<string | null> {
    try {
      // 1) 版本比对与迁移（须在读 DOWNLOADS / DOWNLOAD_LABELS 前完成，确保 ARCHIVE_URI 等列已就绪）
      const currentVersion: number = DaoMaster.SCHEMA_VERSION;
      const sourceVersion: number = await EhDB.getStoreVersion(sourceStore);
      if (sourceVersion > currentVersion) {
        return 'cant_read_the_file';
      }
      if (sourceVersion < currentVersion) {
        await EhDB.migrate(sourceStore, sourceVersion);
      }

      EhDB.sendImportProgress(onProgress, 10);
      // 2) 先在 serial 锁外合并标签与下载（避免 DownloadManager 回调 EhDB.addDownloadLabel/putDownloadInfo 重入锁死锁）
      if (mergeLabels !== null) {
        const externalLabels: DownloadLabel[] =
          await EhDB.readExternal<DownloadLabel>(sourceStore, 'DOWNLOAD_LABELS');
        await mergeLabels(externalLabels);
      }
      if (mergeDownloads !== null) {
        const externalDownloads: DownloadInfo[] =
          await EhDB.readExternal<DownloadInfo>(sourceStore, 'DOWNLOADS');
        await mergeDownloads(externalDownloads);
      }

      EhDB.sendImportProgress(onProgress, 50);
      const dirnames: DownloadDirname[] = await EhDB.readExternal<DownloadDirname>(sourceStore,
        'DOWNLOAD_DIRNAME');
      const historyList: HistoryInfo[] = await EhDB.readExternal<HistoryInfo>(sourceStore, 'HISTORY');
      const quickSearchList: QuickSearch[] = await EhDB.readExternal<QuickSearch>(sourceStore, 'QUICK_SEARCH');
      const favList: LocalFavoriteInfo[] =
        await EhDB.readExternal<LocalFavoriteInfo>(sourceStore, 'LOCAL_FAVORITES');
      const filterList: Filter[] = await EhDB.readExternal<Filter>(sourceStore, 'FILTER');
      const blackList: BlackList[] = await EhDB.readExternal<BlackList>(sourceStore, 'Black_List');
      const galleryTagsList: GalleryTags[] =
        await EhDB.readExternal<GalleryTags>(sourceStore, 'Gallery_Tags');

      // 3) 目标库其余表的合并放在同一 serial 事务内原子提交
      await EhDB.serial(async (): Promise<void> => {
        const targetStore: relationalStore.RdbStore = EhDB.session().getStore();
        targetStore.beginTransaction();
        try {
          for (let i = 0; i < dirnames.length; i++) {
            const d: DownloadDirname = dirnames[i];
            const dirname: string | null = d.getDirname();
            if (dirname !== null) {
              await EhDB.putDownloadDirnameInternal(d.getGid(), dirname);
            }
          }

          EhDB.sendImportProgress(onProgress, 90);

          await EhDB.putHistoryInfoListInternal(historyList);

          const currentQuickSearchList: QuickSearch[] =
            await EhDB.session().getQuickSearchDao().loadAll();
          for (let i = 0; i < quickSearchList.length; i++) {
            const qs: QuickSearch = quickSearchList[i];
            if (EhDB.quickSearchNameDuplicated(currentQuickSearchList, qs.name)) {
              continue;
            }
            await EhDB.insertQuickSearchInternal(qs);
            currentQuickSearchList.push(qs);
          }

          for (let i = 0; i < favList.length; i++) {
            await EhDB.putLocalFavoriteInternal(favList[i]);
          }

          // Bookmarks：上游 L1042–L1043 是 TODO，保持跳过

          const currentFilterList: Filter[] = await EhDB.session().getFilterDao().loadAll();
          for (let i = 0; i < filterList.length; i++) {
            const f: Filter = filterList[i];
            if (EhDB.filterAlreadyPresent(currentFilterList, f)) {
              continue;
            }
            await EhDB.addFilterInternal(f);
            currentFilterList.push(f);
          }

          const currentBlackList: BlackList[] = await EhDB.session().getBlackListDao().loadAll();
          for (let i = 0; i < blackList.length; i++) {
            const b: BlackList = blackList[i];
            if (!EhDB.blackListAlreadyPresent(currentBlackList, b)) {
              await EhDB.insertBlackListInternal(b);
              if (b.badgayname !== null) {
                currentBlackList.push(b);
              }
            }
          }

          for (let i = 0; i < galleryTagsList.length; i++) {
            const t: GalleryTags = galleryTagsList[i];
            if (!(await EhDB.galleryTagsExists(t.gid))) {
              await EhDB.insertGalleryTagsInternal(t);
            }
          }

          targetStore.commit();
        } catch (txErr) {
          targetStore.rollBack();
          throw txErr as Error;
        }
      });

      if (blackList.length > 0) {
        EhDB.notifyBlackListChanged();
      }
      return null;
    } catch (e) {
      ExceptionUtils.throwIfFatal(e as Object);
      return 'cant_read_the_file';
    }
  }

  // ── importDB 的去重判据（抽出来才能单独断言）────────────────────────────────
  // 前两条**照搬上游**（`QuickSearch` 按 name；`Filter` 有**手写 equals** → 本来就按值去重，**不要动它**）。
  // 后两条是 **D-072 的修复**（`BlackList` / `GalleryTags` 没写 equals 却用 contains → 恒 false）。
  // ⚠️ **绝不能靠"补 equals"修**：两者的内容都含跨库必然不同的时间字段
  //    （`BlackList.add_time` / `GalleryTags.create_time`+`update_time`）→ 比较内容恒不等 → 照样冲突。
  //    必须按**主键/业务键**判存在。

  /** 上游 L1019–L1034：与当前库**同名**则跳过（`ObjectUtils.equal(name)`，null==null 也算同名） */
  static quickSearchNameDuplicated(current: QuickSearch[], name: string | null): boolean {
    for (let i = 0; i < current.length; i++) {
      if (ObjectUtils.equal(current[i].name, name)) {
        return true;
      }
    }
    return false;
  }

  /**
   * 上游 L1046–L1052：`Filter` **手写了 `equals`/`hashCode`**（只有 `mode` + `text`，不含 id）
   * ⇒ 上游的 `currentFilterList.contains(filter)` **本来就是按值去重的，是对的**。
   * **D-072 不覆盖 Filter** —— 按"这两个也没 equals，一起改"的批量思路动它，会把对的改错。
   */
  static filterAlreadyPresent(current: Filter[], incoming: Filter): boolean {
    for (let i = 0; i < current.length; i++) {
      if (current[i].equals(incoming)) {
        return true;
      }
    }
    return false;
  }

  /**
   * **D-072 修复**：按业务键 `badgayname` 判重（与上游 `inBlackList` 的查询条件一致：
   * `where Badgayname = '...'`）。
   * 上游症状：`contains` 恒 false → **每次导入把黑名单整表再插一遍（重复行）**。
   * 为什么只用 `badgayname` 单键：上游所有黑名单查询/去重都只按它，单键与上游行为等价。
   * @returns true = 已存在（不要插入）
   */
  static blackListAlreadyPresent(current: BlackList[], incoming: BlackList): boolean {
    for (let i = 0; i < current.length; i++) {
      if (current[i].badgayname === incoming.badgayname) {
        return true;
      }
    }
    return false;
  }

  /**
   * **D-072 修复**：`Gallery_Tags.GID` 是 `INTEGER PRIMARY KEY NOT NULL`（**不自增**）。
   * 上游症状比"重复行"更严重：`insertGalleryTags` 带着源库的 gid 直接 insert，
   * 而 `store.insert` 默认冲突策略是 **ABORT** → 目标库已有该 gid 时**抛约束错误**
   * → 冒到 `importDB` 的 catch → 返回 `cant_read_the_file` → **整条导入失败**
   * （且前面的表已写入 = 部分导入）。**第二次导入同一个库必然失败**，P3 验收会稳定复现。
   *
   * 因此这里走**主键存在性查询**（`dao.load(gid)`），而不是内存里比内容：
   * 内容里有 `create_time/update_time`，跨库必然不同 → 比内容永远判不等 → 照样冲突。
   * @returns true = 该 gid 已在目标库（不要插入）
   */
  static async galleryTagsExists(gid: number): Promise<boolean> {
    const existing: GalleryTags | null = await EhDB.session().getGalleryTagsDao().load(gid);
    return existing !== null;
  }

  /** 对应上游 sendImportProgress(Handler, int) */
  private static sendImportProgress(onProgress: ((percent: number) => void) | null, percent: number): void {
    if (onProgress !== null) {
      onProgress(percent);
    }
  }

  /** 读外部库的 user_version（对应上游 `db.getVersion()`） */
  private static async getStoreVersion(store: relationalStore.RdbStore): Promise<number> {
    const resultSet: relationalStore.ResultSet = await store.querySql('PRAGMA user_version');
    try {
      if (resultSet.goToFirstRow()) {
        return resultSet.getLong(0);
      }
      return 0;
    } finally {
      resultSet.close();
    }
  }

  /** 从外部库整表读取并映射为实体（对应上游 `session.getXxxDao().queryBuilder().list()`） */
  /**
   * 从外部库整表读取：**用 `DaoSession.fromStore(store)` 造一个绑定该 store 的会话**，
   * 再按表名取对应 DAO（storage-db `29cb2782` 交付；语义约束：每次返回新实例、不替换默认 session）。
   */
  private static async readExternal<T>(store: relationalStore.RdbStore,
    table: string): Promise<T[]> {
    const external: DaoSession = DaoSession.fromStore(store);
    if (table === 'DOWNLOAD_DIRNAME') {
      return await external.getDownloadDirnameDao().loadAll() as T[];
    }
    if (table === 'DOWNLOAD_LABELS') {
      return await external.getDownloadLabelDao().loadAll() as T[];
    }
    if (table === 'DOWNLOADS') {
      return await external.getDownloadsDao().loadAll() as T[];
    }
    if (table === 'HISTORY') {
      return await external.getHistoryDao().loadAll() as T[];
    }
    if (table === 'QUICK_SEARCH') {
      return await external.getQuickSearchDao().loadAll() as T[];
    }
    if (table === 'LOCAL_FAVORITES') {
      return await external.getLocalFavoritesDao().loadAll() as T[];
    }
    if (table === 'BOOKMARKS') {
      return await external.getBookmarksBao().loadAll() as T[];
    }
    if (table === 'FILTER') {
      return await external.getFilterDao().loadAll() as T[];
    }
    if (table === 'Gallery_Tags') {
      return await external.getGalleryTagsDao().loadAll() as T[];
    }
    if (table === 'Black_List') {
      return await external.getBlackListDao().loadAll() as T[];
    }
    return [];
  }
}
