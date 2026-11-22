/*
 * 对位上游：app/src/main/java/com/hippo/ehviewer/dao/DaoMaster.java（GreenDAO 生成）
 *
 * 职责不变：持有 SCHEMA_VERSION(=8)、按固定顺序建/删 10 张表、创建 DaoSession。
 *
 * 平台对位：
 *   - 上游 `extends AbstractDaoMaster` + `registerDaoClass(XxxDao.class)`（反射注册）。
 *     ArkTS 无反射（方案 §5-①），注册表改为 DaoSession 里的显式惰性 getter。
 *   - 建表顺序必须与上游逐行一致（Gallery_Tags → DOWNLOADS → DOWNLOAD_LABELS →
 *     DOWNLOAD_DIRNAME → HISTORY → QUICK_SEARCH → Black_List → LOCAL_FAVORITES →
 *     BOOKMARKS → FILTER）：SQLite 里表顺序不影响查询，但**旧库比对新旧 schema 时顺序影响
 *     `sqlite_master` 的 rowid 顺序**，保持一致的比对输出才能做冒烟核对。
 *   - `OpenHelper`/`DevOpenHelper`（上游内部类）在鸿蒙由 `@ohos.data.relationalStore` 的开库流程
 *     与 core-runtime 的 `EhDB.ets`（S0150）承担，且 RDB 无同步 API（D-012），
 *     故这里只保留 `createAllTables/dropAllTables/newSession`，均 async。
 *     交接点：EhDB.ets 负责 open(StoreConfig) → 首次建库调 DaoMaster.createAllTables(store, false)；
 *     版本升级/降级沿用 `database/MSQLiteOpenHelper.ets`（PRAGMA user_version 语义）。
 */

import relationalStore from '@ohos.data.relationalStore';
import { GalleryTagsDao } from './GalleryTagsDao';
import { DownloadsDao } from './DownloadsDao';
import { DownloadLabelDao } from './DownloadLabelDao';
import { DownloadDirnameDao } from './DownloadDirnameDao';
import { HistoryDao } from './HistoryDao';
import { QuickSearchDao } from './QuickSearchDao';
import { BlackListDao } from './BlackListDao';
import { LocalFavoritesDao } from './LocalFavoritesDao';
import { BookmarksBao } from './BookmarksBao';
import { FilterDao } from './FilterDao';
import { DaoSession } from './DaoSession';

export class DaoMaster {
  /** 对位上游 SCHEMA_VERSION（v8：含 DOWNLOADS.ARCHIVE_URI 与 Gallery_Tags.LOCATION）。 */
  static readonly SCHEMA_VERSION: number = 8;

  private readonly store: relationalStore.RdbStore;

  constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  /**
   * 对位上游 `createAllTables(Database db, boolean ifNotExists)`。
   * 顺序与上游逐行一致（见文件头说明）。
   */
  static async createAllTables(store: relationalStore.RdbStore, ifNotExists: boolean): Promise<void> {
    await GalleryTagsDao.createTable(store, ifNotExists);
    await DownloadsDao.createTable(store, ifNotExists);
    await DownloadLabelDao.createTable(store, ifNotExists);
    await DownloadDirnameDao.createTable(store, ifNotExists);
    await HistoryDao.createTable(store, ifNotExists);
    await QuickSearchDao.createTable(store, ifNotExists);
    await BlackListDao.createTable(store, ifNotExists);
    await LocalFavoritesDao.createTable(store, ifNotExists);
    await BookmarksBao.createTable(store, ifNotExists);
    await FilterDao.createTable(store, ifNotExists);
  }

  /** 对位上游 `dropAllTables(Database db, boolean ifExists)`（顺序同上）。 */
  static async dropAllTables(store: relationalStore.RdbStore, ifExists: boolean): Promise<void> {
    await GalleryTagsDao.dropTable(store, ifExists);
    await DownloadsDao.dropTable(store, ifExists);
    await DownloadLabelDao.dropTable(store, ifExists);
    await DownloadDirnameDao.dropTable(store, ifExists);
    await HistoryDao.dropTable(store, ifExists);
    await QuickSearchDao.dropTable(store, ifExists);
    await BlackListDao.dropTable(store, ifExists);
    await LocalFavoritesDao.dropTable(store, ifExists);
    await BookmarksBao.dropTable(store, ifExists);
    await FilterDao.dropTable(store, ifExists);
  }

  /** 对位上游 `newSession()`（IdentityScopeType.Session 在 ArkTS 无对应，见 DaoSession 注释）。 */
  newSession(): DaoSession {
    return new DaoSession(this.store);
  }

  /** 底层 store（对位上游 `db` 字段，供 EhDB 做迁移脚本）。 */
  getStore(): relationalStore.RdbStore {
    return this.store;
  }
}
