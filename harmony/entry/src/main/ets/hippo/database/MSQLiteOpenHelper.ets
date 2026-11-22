/*
 * 对位上游：app/src/main/java/com/hippo/database/MSQLiteOpenHelper.java
 *
 * 平台对位（关键差异，已报 lead 作为 DEVIATIONS 候选 D-010「RDB 异步化」）：
 *   - 上游继承 android SQLiteOpenHelper，getWritableDb() 是**同步**的，onCreate/onUpgrade 同步执行 SQL。
 *     鸿蒙 relationalStore 的 getRdbStore / executeSql / querySql **全部是 Promise**，没有同步变体。
 *     因此 open() 返回 Promise<RdbStore>，生命周期回调是 async。这是全工程唯一的同步→异步转折点，
 *     dao/ 与 spider/ 的所有 DB 方法都因此是 async（见各文件注释与 MR）。
 *   - 版本管理：上游由 SQLiteOpenHelper 的构造参数 version + 系统 PRAGMA user_version 承担；
 *     鸿蒙 RdbStore 有 `version` 属性（读写 user_version），语义等价，本类显式对照。
 *   - onDowngrade：上游 SqlUtils.dropAllTable(db) → 这里实现为「查 sqlite_master 后逐表 DROP」，
 *     保持「降级即清库」的上游行为（仅开发期会触发）。
 */

import relationalStore from '@ohos.data.relationalStore';
import common from '@ohos.app.ability.common';
import { Utils } from '../unifile/Utils';
import { MSQLiteBuilder } from './MSQLiteBuilder';

const TAG: string = 'MSQLiteOpenHelper';

export class MSQLiteOpenHelper {
  private readonly context: common.Context;
  private readonly name: string;
  private readonly versionValue: number;
  private readonly builder: MSQLiteBuilder;
  private store: relationalStore.RdbStore | null = null;

  constructor(context: common.Context, name: string, version: number, builder: MSQLiteBuilder) {
    this.context = context;
    this.name = name;
    this.versionValue = version;
    this.builder = builder;
  }

  /**
   * 对位上游 SQLiteOpenHelper.getWritableDb()。
   * 首次打开（version==0）执行 onCreate；版本不等时执行 upgrade/downgrade 并把版本写回。
   */
  async open(): Promise<relationalStore.RdbStore> {
    const config: relationalStore.StoreConfig = {
      name: this.name,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    const store: relationalStore.RdbStore = await relationalStore.getRdbStore(this.context, config);
    const oldVersion: number = store.version;
    if (oldVersion === 0) {
      await this.onCreate(store);
      store.version = this.versionValue;
    } else if (oldVersion < this.versionValue) {
      await this.onUpgrade(store, oldVersion, this.versionValue);
      store.version = this.versionValue;
    } else if (oldVersion > this.versionValue) {
      await this.onDowngrade(store, oldVersion, this.versionValue);
      store.version = this.versionValue;
    }
    this.store = store;
    return store;
  }

  /** 对位上游 onCreate：等价于 onUpgrade(db, 0, version)。 */
  private async onCreate(store: relationalStore.RdbStore): Promise<void> {
    await this.execStatements(store, 0, this.versionValue);
  }

  /** 对位上游 onUpgrade。 */
  private async onUpgrade(store: relationalStore.RdbStore, oldVersion: number, newVersion: number): Promise<void> {
    await this.execStatements(store, oldVersion, newVersion);
  }

  /** 对位上游 onDowngrade：整库清空后重建（仅开发期）。 */
  private async onDowngrade(store: relationalStore.RdbStore, oldVersion: number, newVersion: number): Promise<void> {
    Utils.logW(TAG, `Downgrade from ${oldVersion} to ${newVersion}, drop all tables`);
    await MSQLiteOpenHelper.dropAllTable(store);
    await this.onCreate(store);
  }

  private async execStatements(store: relationalStore.RdbStore, oldVersion: number, newVersion: number): Promise<void> {
    const statements: string[] = this.builder.getStatements(oldVersion, newVersion);
    store.beginTransaction();
    try {
      for (const sql of statements) {
        await store.executeSql(sql);
      }
      store.commit();
    } catch (e) {
      store.rollBack();
      Utils.throwIfFatal(e);
      Utils.logE(TAG, `Migration failed: ${e}`);
      throw e as Error;
    }
  }

  /** 已打开的 store；未 open 时抛（避免调用方拿到 null 继续用）。 */
  getStore(): relationalStore.RdbStore {
    if (this.store === null) {
      throw new Error('MSQLiteOpenHelper.open() must be awaited first');
    }
    return this.store;
  }

  /** 对位 com.hippo.util.SqlUtils.dropAllTable：删除除系统表外的全部用户表。 */
  static async dropAllTable(store: relationalStore.RdbStore): Promise<void> {
    const rs: relationalStore.ResultSet = await store.querySql(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'ohos_%'");
    const names: string[] = [];
    try {
      while (rs.goToNextRow()) {
        if (!rs.isColumnNull(0)) {
          names.push(rs.getString(0));
        }
      }
    } finally {
      rs.close();
    }
    for (const name of names) {
      await store.executeSql(`DROP TABLE IF EXISTS "${name}"`);
    }
  }
}
