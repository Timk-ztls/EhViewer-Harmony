/*
 * 对位上游：app/src/main/java/com/hippo/ehviewer/dao/DownloadDirnameDao.java（GreenDAO 生成 DAO）
 *
 * 表：DOWNLOAD_DIRNAME —— CREATE_TABLE_SQL 逐字取自上游 createTable（列名/类型/约束未改一字），
 * 因此可以直接读写既有 Android App 的 ehviewer.db（继承旧数据的前提）。
 *
 * 平台对位（D-012 RDB 异步化）：GreenDAO 的 AbstractDao 基类不存在 → 手写等价方法集；
 * 所有方法返回 Promise（relationalStore 无同步 API），调用方 await。无反射：映射显式写死。
 */

import relationalStore from '@ohos.data.relationalStore';
import { Column, SqlExpr } from '../../database/MSQLiteBuilder';
import { DownloadDirname } from './DownloadDirname';

/** 对位 GreenDAO 的 DownloadDirnameDao.Properties。 */
export class DownloadDirnameDaoProperties {
  readonly Gid: Column = new Column('GID');
  readonly Dirname: Column = new Column('DIRNAME');
}

/** 对位 GreenDAO QueryBuilder 的常用子集（where/orderAsc/orderDesc/limit/offset/list/count）。 */
export class DownloadDirnameDaoQueryBuilder {
  private readonly dao: DownloadDirnameDao;
  private whereExpr: SqlExpr | null = null;
  private orderCol: Column | null = null;
  private orderAscending: boolean = true;
  private limitValue: number = 0;
  private hasLimit: boolean = false;
  private offsetValue: number = 0;

  constructor(dao: DownloadDirnameDao) {
    this.dao = dao;
  }

  where(expr: SqlExpr): DownloadDirnameDaoQueryBuilder {
    this.whereExpr = this.whereExpr === null ? expr : this.whereExpr.and(expr);
    return this;
  }

  orderAsc(column: Column): DownloadDirnameDaoQueryBuilder {
    this.orderCol = column;
    this.orderAscending = true;
    return this;
  }

  orderDesc(column: Column): DownloadDirnameDaoQueryBuilder {
    this.orderCol = column;
    this.orderAscending = false;
    return this;
  }

  limit(limit: number): DownloadDirnameDaoQueryBuilder {
    this.limitValue = limit;
    this.hasLimit = true;
    return this;
  }

  offset(offset: number): DownloadDirnameDaoQueryBuilder {
    this.offsetValue = offset;
    return this;
  }

  async list(): Promise<DownloadDirname[]> {
    return this.dao.queryBy(this.sql(), this.args());
  }

  async listLazy(): Promise<DownloadDirname[]> {
    return this.list();
  }

  async count(): Promise<number> {
    return this.dao.countBy(this.whereExpr, this.args());
  }

  sql(): string {
    let sql: string = 'SELECT * FROM "DOWNLOAD_DIRNAME"';
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

export class DownloadDirnameDao {
  public static readonly TABLENAME: string = 'DOWNLOAD_DIRNAME';
  public static readonly PK_COLUMN: string = 'GID';
  /** 上游 DownloadDirnameDao.createTable 的 DDL，逐字保留。 */
  public static readonly CREATE_TABLE_SQL: string =
    'CREATE TABLE IF NOT EXISTS "DOWNLOAD_DIRNAME" ("GID" INTEGER PRIMARY KEY NOT NULL ,"DIRNAME" TEXT);';
  public static readonly DROP_TABLE_SQL: string = 'DROP TABLE IF EXISTS "DOWNLOAD_DIRNAME"';
  public static readonly Properties: DownloadDirnameDaoProperties = new DownloadDirnameDaoProperties();

  private readonly store: relationalStore.RdbStore;

  constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  /** 对位上游静态 createTable(db, ifNotExists)。 */
  static async createTable(store: relationalStore.RdbStore, ifNotExists: boolean): Promise<void> {
    const sql: string = ifNotExists
      ? DownloadDirnameDao.CREATE_TABLE_SQL
      : DownloadDirnameDao.CREATE_TABLE_SQL.replace('IF NOT EXISTS ', '');
    await store.executeSql(sql);

  }

  /** 对位上游静态 dropTable(db, ifExists)。 */
  static async dropTable(store: relationalStore.RdbStore, ifExists: boolean): Promise<void> {
    await store.executeSql(ifExists ? DownloadDirnameDao.DROP_TABLE_SQL : 'DROP TABLE "DOWNLOAD_DIRNAME"');
  }

  queryBuilder(): DownloadDirnameDaoQueryBuilder {
    return new DownloadDirnameDaoQueryBuilder(this);
  }

  async insert(entity: DownloadDirname): Promise<number> {
    return this.store.insert(DownloadDirnameDao.TABLENAME, this.toBucket(entity));
  }

  async insertOrReplace(entity: DownloadDirname): Promise<number> {
    return this.store.insert(DownloadDirnameDao.TABLENAME, this.toBucket(entity),
      relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  async save(entity: DownloadDirname): Promise<void> {
    const exists: DownloadDirname | null = await this.load(entity.getGid());
    if (exists !== null) {
      await this.update(entity);
    } else {
      await this.insert(entity);
    }
  }

  async update(entity: DownloadDirname): Promise<void> {
    const key: number | null = entity.getGid();
    if (key === null) {
      throw new Error('Cannot update entity without key - was it inserted before?');
    }
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates(DownloadDirnameDao.TABLENAME);
    predicates.equalTo(DownloadDirnameDao.PK_COLUMN, key);
    await this.store.update(this.toBucket(entity), predicates);
  }

  async delete(entity: DownloadDirname): Promise<void> {
    const key: number | null = entity.getGid();
    if (key === null) {
      throw new Error('Cannot delete entity without key');
    }
    await this.deleteByKey(key);
  }

  async deleteByKey(key: number): Promise<void> {
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates(DownloadDirnameDao.TABLENAME);
    predicates.equalTo(DownloadDirnameDao.PK_COLUMN, key);
    await this.store.delete(predicates);
  }

  async deleteAll(): Promise<void> {
    await this.store.executeSql('DELETE FROM "DOWNLOAD_DIRNAME"');
  }

  async load(key: number): Promise<DownloadDirname | null> {
    const rows: DownloadDirname[] = await this.queryBy(
      'SELECT * FROM "DOWNLOAD_DIRNAME" WHERE "GID" = ?', [key]);
    return rows.length > 0 ? rows[0] : null;
  }

  async loadAll(): Promise<DownloadDirname[]> {
    return this.queryBy('SELECT * FROM "DOWNLOAD_DIRNAME"', []);
  }

  async count(): Promise<number> {
    return this.countBy(null, []);
  }

  async insertInTx(entities: DownloadDirname[]): Promise<void> {
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

  async updateInTx(entities: DownloadDirname[]): Promise<void> {
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

  async deleteInTx(entities: DownloadDirname[]): Promise<void> {
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
  toBucket(entity: DownloadDirname): relationalStore.ValuesBucket {
    const v_Dirname: string | null = entity.getDirname();
    const bucket: relationalStore.ValuesBucket = {
      'GID': entity.getGid(),
      'DIRNAME': v_Dirname !== null ? v_Dirname : null
    };
    return bucket;
  }

  /** ResultSet 当前行 → 实体。 */
  fromResultSet(rs: relationalStore.ResultSet): DownloadDirname {
    const entity: DownloadDirname = new DownloadDirname();
    entity.setGid(readLong(rs, 'GID'));
    entity.setDirname(readNullableString(rs, 'DIRNAME'));
    return entity;
  }

  async queryBy(sql: string, args: relationalStore.ValueType[]): Promise<DownloadDirname[]> {
    const rs: relationalStore.ResultSet = await this.store.querySql(sql, args);
    const out: DownloadDirname[] = [];
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
    let sql: string = 'SELECT COUNT(*) AS C FROM "DOWNLOAD_DIRNAME"';
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
