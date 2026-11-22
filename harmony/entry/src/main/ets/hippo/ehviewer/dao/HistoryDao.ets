/*
 * 对位上游：app/src/main/java/com/hippo/ehviewer/dao/HistoryDao.java（GreenDAO 生成 DAO）
 *
 * 表：HISTORY —— CREATE_TABLE_SQL 逐字取自上游 createTable（列名/类型/约束未改一字），
 * 因此可以直接读写既有 Android App 的 ehviewer.db（继承旧数据的前提）。
 *
 * 平台对位（D-012 RDB 异步化）：GreenDAO 的 AbstractDao 基类不存在 → 手写等价方法集；
 * 所有方法返回 Promise（relationalStore 无同步 API），调用方 await。无反射：映射显式写死。
 */

import relationalStore from '@ohos.data.relationalStore';
import { Column, SqlExpr } from '../../database/MSQLiteBuilder';
import { HistoryInfo } from './HistoryInfo';

/** 对位 GreenDAO 的 HistoryDao.Properties。 */
export class HistoryDaoProperties {
  readonly Gid: Column = new Column('GID');
  readonly Token: Column = new Column('TOKEN');
  readonly Title: Column = new Column('TITLE');
  readonly TitleJpn: Column = new Column('TITLE_JPN');
  readonly Thumb: Column = new Column('THUMB');
  readonly Category: Column = new Column('CATEGORY');
  readonly Posted: Column = new Column('POSTED');
  readonly Uploader: Column = new Column('UPLOADER');
  readonly Rating: Column = new Column('RATING');
  readonly SimpleLanguage: Column = new Column('SIMPLE_LANGUAGE');
  readonly Mode: Column = new Column('MODE');
  readonly Time: Column = new Column('TIME');
}

/** 对位 GreenDAO QueryBuilder 的常用子集（where/orderAsc/orderDesc/limit/offset/list/count）。 */
export class HistoryDaoQueryBuilder {
  private readonly dao: HistoryDao;
  private whereExpr: SqlExpr | null = null;
  private orderCol: Column | null = null;
  private orderAscending: boolean = true;
  private limitValue: number = 0;
  private hasLimit: boolean = false;
  private offsetValue: number = 0;

  constructor(dao: HistoryDao) {
    this.dao = dao;
  }

  where(expr: SqlExpr): HistoryDaoQueryBuilder {
    this.whereExpr = this.whereExpr === null ? expr : this.whereExpr.and(expr);
    return this;
  }

  orderAsc(column: Column): HistoryDaoQueryBuilder {
    this.orderCol = column;
    this.orderAscending = true;
    return this;
  }

  orderDesc(column: Column): HistoryDaoQueryBuilder {
    this.orderCol = column;
    this.orderAscending = false;
    return this;
  }

  limit(limit: number): HistoryDaoQueryBuilder {
    this.limitValue = limit;
    this.hasLimit = true;
    return this;
  }

  offset(offset: number): HistoryDaoQueryBuilder {
    this.offsetValue = offset;
    return this;
  }

  async list(): Promise<HistoryInfo[]> {
    return this.dao.queryBy(this.sql(), this.args());
  }

  async listLazy(): Promise<HistoryInfo[]> {
    return this.list();
  }

  async count(): Promise<number> {
    return this.dao.countBy(this.whereExpr, this.args());
  }

  sql(): string {
    let sql: string = 'SELECT * FROM "HISTORY"';
    if (this.whereExpr !== null) {
      sql = sql + ' WHERE ' + this.whereExpr.sql;
    }
    if (this.orderCol !== null) {
      sql = sql + ' ORDER BY "' + this.orderCol.columnName + '" ' + (this.orderAscending ? 'ASC' : 'DESC');
    }
    if (this.hasLimit) {
      sql = sql + ' LIMIT ' + this.limitValue;
      if (this.offsetValue > 0) {
        sql = sql + ' OFFSET ' + this.offsetValue;
      }
    } else if (this.offsetValue > 0) {
      sql = sql + ' LIMIT -1 OFFSET ' + this.offsetValue;
    }
    return sql;
  }

  args(): relationalStore.ValueType[] {
    const out: relationalStore.ValueType[] = [];
    if (this.whereExpr !== null) {
      for (const a of this.whereExpr.args) {
        out.push(a as relationalStore.ValueType);
      }
    }
    return out;
  }
}

export class HistoryDao {
  public static readonly TABLENAME: string = 'HISTORY';
  public static readonly PK_COLUMN: string = 'GID';
  /** 上游 HistoryDao.createTable 的 DDL，逐字保留。 */
  public static readonly CREATE_TABLE_SQL: string =
    'CREATE TABLE IF NOT EXISTS "HISTORY" ("GID" INTEGER PRIMARY KEY NOT NULL ,"TOKEN" TEXT,"TITLE" TEXT,"TITLE_JPN" TEXT,"THUMB" TEXT,"CATEGORY" INTEGER NOT NULL ,"POSTED" TEXT,"UPLOADER" TEXT,"RATING" REAL NOT NULL ,"SIMPLE_LANGUAGE" TEXT,"MODE" INTEGER NOT NULL ,"TIME" INTEGER NOT NULL );';
  public static readonly DROP_TABLE_SQL: string = 'DROP TABLE IF EXISTS "HISTORY"';
  public static readonly Properties: HistoryDaoProperties = new HistoryDaoProperties();

  private readonly store: relationalStore.RdbStore;

  constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  /** 对位上游静态 createTable(db, ifNotExists)。 */
  static async createTable(store: relationalStore.RdbStore, ifNotExists: boolean): Promise<void> {
    const sql: string = ifNotExists
      ? HistoryDao.CREATE_TABLE_SQL
      : HistoryDao.CREATE_TABLE_SQL.replace('IF NOT EXISTS ', '');
    await store.executeSql(sql);

  }

  /** 对位上游静态 dropTable(db, ifExists)。 */
  static async dropTable(store: relationalStore.RdbStore, ifExists: boolean): Promise<void> {
    await store.executeSql(ifExists ? HistoryDao.DROP_TABLE_SQL : 'DROP TABLE "HISTORY"');
  }

  queryBuilder(): HistoryDaoQueryBuilder {
    return new HistoryDaoQueryBuilder(this);
  }

  async insert(entity: HistoryInfo): Promise<number> {
    return this.store.insert(HistoryDao.TABLENAME, this.toBucket(entity));
  }

  async insertOrReplace(entity: HistoryInfo): Promise<number> {
    return this.store.insert(HistoryDao.TABLENAME, this.toBucket(entity),
      relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  async save(entity: HistoryInfo): Promise<void> {
    const exists: HistoryInfo | null = await this.load(entity.getGid());
    if (exists !== null) {
      await this.update(entity);
    } else {
      await this.insert(entity);
    }
  }

  async update(entity: HistoryInfo): Promise<void> {
    const key: number | null = entity.getGid();
    if (key === null) {
      throw new Error('Cannot update entity without key - was it inserted before?');
    }
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates(HistoryDao.TABLENAME);
    predicates.equalTo(HistoryDao.PK_COLUMN, key);
    await this.store.update(this.toBucket(entity), predicates);
  }

  async delete(entity: HistoryInfo): Promise<void> {
    const key: number | null = entity.getGid();
    if (key === null) {
      throw new Error('Cannot delete entity without key');
    }
    await this.deleteByKey(key);
  }

  async deleteByKey(key: number): Promise<void> {
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates(HistoryDao.TABLENAME);
    predicates.equalTo(HistoryDao.PK_COLUMN, key);
    await this.store.delete(predicates);
  }

  async deleteAll(): Promise<void> {
    await this.store.executeSql('DELETE FROM "HISTORY"');
  }

  async load(key: number): Promise<HistoryInfo | null> {
    const rows: HistoryInfo[] = await this.queryBy(
      'SELECT * FROM "HISTORY" WHERE "GID" = ?', [key]);
    return rows.length > 0 ? rows[0] : null;
  }

  async loadAll(): Promise<HistoryInfo[]> {
    return this.queryBy('SELECT * FROM "HISTORY"', []);
  }

  async count(): Promise<number> {
    return this.countBy(null, []);
  }

  async insertInTx(entities: HistoryInfo[]): Promise<void> {
    this.store.beginTransaction();
    try {
      for (const e of entities) {
        await this.insert(e);
      }
      this.store.commit();
    } catch (err) {
      this.store.rollBack();
      throw err as Error;
    }
  }

  async updateInTx(entities: HistoryInfo[]): Promise<void> {
    this.store.beginTransaction();
    try {
      for (const e of entities) {
        await this.update(e);
      }
      this.store.commit();
    } catch (err) {
      this.store.rollBack();
      throw err as Error;
    }
  }

  async deleteInTx(entities: HistoryInfo[]): Promise<void> {
    this.store.beginTransaction();
    try {
      for (const e of entities) {
        await this.delete(e);
      }
      this.store.commit();
    } catch (err) {
      this.store.rollBack();
      throw err as Error;
    }
  }

  /** 实体 → ValuesBucket（列名逐字对齐 DDL，NULL 用 null 表达）。 */
  toBucket(entity: HistoryInfo): relationalStore.ValuesBucket {
    const v_SimpleLanguage: string | null = entity.getSimpleLanguage();
    const bucket: relationalStore.ValuesBucket = {
      'GID': entity.getGid(),
      'TOKEN': entity.getToken(),
      'TITLE': entity.getTitle(),
      'TITLE_JPN': entity.getTitleJpn(),
      'THUMB': entity.getThumb(),
      'CATEGORY': entity.getCategory(),
      'POSTED': entity.getPosted(),
      'UPLOADER': entity.getUploader(),
      'RATING': entity.getRating(),
      'SIMPLE_LANGUAGE': v_SimpleLanguage !== null ? v_SimpleLanguage : null,
      'MODE': entity.getMode(),
      'TIME': entity.getTime()
    };
    return bucket;
  }

  /** ResultSet 当前行 → 实体。 */
  fromResultSet(rs: relationalStore.ResultSet): HistoryInfo {
    const entity: HistoryInfo = new HistoryInfo();
    entity.setGid(readLong(rs, 'GID'));
    entity.setToken(readString(rs, 'TOKEN'));
    entity.setTitle(readString(rs, 'TITLE'));
    entity.setTitleJpn(readString(rs, 'TITLE_JPN'));
    entity.setThumb(readString(rs, 'THUMB'));
    entity.setCategory(readLong(rs, 'CATEGORY'));
    entity.setPosted(readString(rs, 'POSTED'));
    entity.setUploader(readString(rs, 'UPLOADER'));
    entity.setRating(readDouble(rs, 'RATING'));
    entity.setSimpleLanguage(readNullableString(rs, 'SIMPLE_LANGUAGE'));
    entity.setMode(readLong(rs, 'MODE'));
    entity.setTime(readLong(rs, 'TIME'));
    return entity;
  }

  async queryBy(sql: string, args: relationalStore.ValueType[]): Promise<HistoryInfo[]> {
    const rs: relationalStore.ResultSet = await this.store.querySql(sql, args);
    const out: HistoryInfo[] = [];
    try {
      while (rs.goToNextRow()) {
        out.push(this.fromResultSet(rs));
      }
    } finally {
      rs.close();
    }
    return out;
  }

  async countBy(whereExpr: SqlExpr | null, args: relationalStore.ValueType[]): Promise<number> {
    let sql: string = 'SELECT COUNT(*) AS C FROM "HISTORY"';
    if (whereExpr !== null) {
      sql = sql + ' WHERE ' + whereExpr.sql;
    }
    const rs: relationalStore.ResultSet = await this.store.querySql(sql, args);
    let n: number = 0;
    try {
      if (rs.goToNextRow()) {
        n = rs.getLong(0);
      }
    } finally {
      rs.close();
    }
    return n;
  }
}


/** 读非空 REAL 列（GreenDAO float → SQLite REAL）。 */
function readDouble(rs: relationalStore.ResultSet, column: string): number {
  const idx: number = rs.getColumnIndex(column);
  if (idx < 0 || rs.isColumnNull(idx)) {
    return 0;
  }
  return rs.getDouble(idx);
}

/** 读可空 INTEGER 列（NULL → null，C-13 统一契约）。 */
function readNullableLong(rs: relationalStore.ResultSet, column: string): number | null {
  const idx: number = rs.getColumnIndex(column);
  if (idx < 0 || rs.isColumnNull(idx)) {
    return null;
  }
  return rs.getLong(idx);
}

/** 读非空 INTEGER 列（NULL 视为 0，与建表 NOT NULL 一致）。 */
function readLong(rs: relationalStore.ResultSet, column: string): number {
  const idx: number = rs.getColumnIndex(column);
  if (idx < 0 || rs.isColumnNull(idx)) {
    return 0;
  }
  return rs.getLong(idx);
}

/** 读可空 TEXT 列。 */
function readNullableString(rs: relationalStore.ResultSet, column: string): string | null {
  const idx: number = rs.getColumnIndex(column);
  if (idx < 0 || rs.isColumnNull(idx)) {
    return null;
  }
  return rs.getString(idx);
}

/** 读非空 TEXT 列。 */
function readString(rs: relationalStore.ResultSet, column: string): string {
  const idx: number = rs.getColumnIndex(column);
  if (idx < 0 || rs.isColumnNull(idx)) {
    return '';
  }
  return rs.getString(idx);
}

/** 读可空 INTEGER(0/1) 列为 boolean（NULL → null）。 */
function readNullableBoolean(rs: relationalStore.ResultSet, column: string): boolean | null {
  const idx: number = rs.getColumnIndex(column);
  if (idx < 0 || rs.isColumnNull(idx)) {
    return null;
  }
  return rs.getLong(idx) !== 0;
}

/** 读可空 INTEGER(ms) 列为 Date（NULL → null）。 */
function readNullableDate(rs: relationalStore.ResultSet, column: string): Date | null {
  const idx: number = rs.getColumnIndex(column);
  if (idx < 0 || rs.isColumnNull(idx)) {
    return null;
  }
  return new Date(rs.getLong(idx));
}
