/*
 * 对位上游：app/src/main/java/com/hippo/ehviewer/dao/DaoSession.java（GreenDAO 生成）
 *
 * 职责不变：持有一个数据库连接 + 10 个 DAO 实例，下游通过 `session.getXxxDao()` 取。
 *
 * 平台对位：
 *   - 上游 `extends AbstractDaoSession`，DAO 实例在构造时通过 `registerDao(...)` 一次性创建。
 *     ArkTS 无反射也无泛型注册表 → 改为**显式惰性 getter**（首取才 new），
 *     语义等价（DAO 本身无状态，只有 store 引用），且避免开库时一次性构造 10 个对象。
 *   - 上游的 `IdentityScopeType.Session`（同一 session 内同主键返回同一对象实例）在 ArkTS 无对位，
 *     且 EhViewer 的调用点从不依赖引用相等（列表项都是整体重新查询），
 *     故**不实现 identity scope**：每次 query 返回新对象。这是唯一的行为差异，已在本文件与 MR 登记。
 *   - 全部 DAO 方法 async（D-012），getter 本身保持同步（只构造对象，不碰 DB）。
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

export class DaoSession {
  private readonly store: relationalStore.RdbStore;

  private galleryTagsDao: GalleryTagsDao | null = null;
  private downloadsDao: DownloadsDao | null = null;
  private downloadLabelDao: DownloadLabelDao | null = null;
  private downloadDirnameDao: DownloadDirnameDao | null = null;
  private historyDao: HistoryDao | null = null;
  private quickSearchDao: QuickSearchDao | null = null;
  private blackListDao: BlackListDao | null = null;
  private localFavoritesDao: LocalFavoritesDao | null = null;
  private bookmarksBao: BookmarksBao | null = null;
  private filterDao: FilterDao | null = null;

  constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  /**
   * 以**任意** store 构造一个 session（对位上游 `new DaoSession(db)` 在 `EhDB` 里的第二种用法）。
   *
   * 为什么需要它：`EhDB.exportDB` / `importDB` 要把行读/写进**第二个库**（导出的目标库或导入的源库），
   * 而本类默认绑定单库（单例语义由调用方保证：`EhDB` 只持有一个默认 session）。
   * 没有这个入口，调用方只能手拼 SQL —— 那会绕过 DAO 层的字段↔列映射（D-033 那类漂移）。
   *
   * 与构造器的关系：
   *   - `constructor(store)` 是唯一真正干活的地方；本工厂只是语义化入口，**不引入任何额外状态**
   *   - 每次调用返回**新实例**（DAO 实例也是新的），与上游 `new DaoSession(db)` 一致；
   *     不要用它替换 `EhDB` 的默认 session，否则会丢掉默认 session 上的 DAO 缓存
   */
  static fromStore(store: relationalStore.RdbStore): DaoSession {
    return new DaoSession(store);
  }



  getGalleryTagsDao(): GalleryTagsDao {
    if (this.galleryTagsDao === null) {
      this.galleryTagsDao = new GalleryTagsDao(this.store);
    }
    return this.galleryTagsDao;
  }

  getDownloadsDao(): DownloadsDao {
    if (this.downloadsDao === null) {
      this.downloadsDao = new DownloadsDao(this.store);
    }
    return this.downloadsDao;
  }

  getDownloadLabelDao(): DownloadLabelDao {
    if (this.downloadLabelDao === null) {
      this.downloadLabelDao = new DownloadLabelDao(this.store);
    }
    return this.downloadLabelDao;
  }

  getDownloadDirnameDao(): DownloadDirnameDao {
    if (this.downloadDirnameDao === null) {
      this.downloadDirnameDao = new DownloadDirnameDao(this.store);
    }
    return this.downloadDirnameDao;
  }

  getHistoryDao(): HistoryDao {
    if (this.historyDao === null) {
      this.historyDao = new HistoryDao(this.store);
    }
    return this.historyDao;
  }

  getQuickSearchDao(): QuickSearchDao {
    if (this.quickSearchDao === null) {
      this.quickSearchDao = new QuickSearchDao(this.store);
    }
    return this.quickSearchDao;
  }

  getBlackListDao(): BlackListDao {
    if (this.blackListDao === null) {
      this.blackListDao = new BlackListDao(this.store);
    }
    return this.blackListDao;
  }

  getLocalFavoritesDao(): LocalFavoritesDao {
    if (this.localFavoritesDao === null) {
      this.localFavoritesDao = new LocalFavoritesDao(this.store);
    }
    return this.localFavoritesDao;
  }

  getBookmarksBao(): BookmarksBao {
    if (this.bookmarksBao === null) {
      this.bookmarksBao = new BookmarksBao(this.store);
    }
    return this.bookmarksBao;
  }

  getFilterDao(): FilterDao {
    if (this.filterDao === null) {
      this.filterDao = new FilterDao(this.store);
    }
    return this.filterDao;
  }

  /** 底层 store（对位上游 `getDatabase()`），EhDB 备份/恢复与迁移脚本用。 */
  getStore(): relationalStore.RdbStore {
    return this.store;
  }

  /** 对位上游 `clear()`：清空 identity scope（本 port 无 scope，等价于空操作）。 */
  clear(): void {
    // ArkTS 侧不做对象级缓存，无需清理
  }
}
