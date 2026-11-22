/*
 * 对位上游：app/src/main/java/com/hippo/ehviewer/dao/DownloadLabelDao.java（GreenDAO 生成 DAO）
 *
 * 表：DOWNLOAD_LABELS —— CREATE_TABLE_SQL 逐字取自上游 createTable（列名/类型/约束未改一字），
 * 因此可以直接读写既有 Android App 的 ehviewer.db（继承旧数据的前提）。
 *
 * 平台对位（D-012 RDB 异步化）：GreenDAO 的 AbstractDao 基类不存在 → 手写等价方法集；
 * 所有方法返回 Promise（relationalStore 无同步 API），调用方 await。无反射：映射显式写死。
 */

import relationalStore from '@ohos.data.relationalStore';
import { Column, SqlExpr } from '../../database/MSQLiteBuilder';
import { DownloadLabel } from './DownloadLabel';

/** 对位 GreenDAO 的 DownloadLabelDao.Properties。 */
export class DownloadLabelDaoProperties {
  readonly Id: Column = new Column('_id');
  readonly Label: Column = new Column('LABEL');
  readonly Time: Column = new Column('TIME');
}

/** 对位 GreenDAO QueryBuilder 的常用子集（where/orderAsc/orderDesc/limit/offset/list/count）。 */
export class DownloadLabelDaoQueryBuilder {
  private readonly dao: DownloadLabelDao;
  private whereExpr: SqlExpr | null = null;
  private orderCol: Column | null = null;
  private orderAscending: boolean = true;
  private limitValue: number = 0;
  private hasLimit: boolean = false;
  private offsetValue: number = 0;

  constructor(dao: DownloadLabelDao) {
    this.dao = dao;
  }

  where(expr: SqlExpr): DownloadLabelDaoQueryBuilder {
    this.whereExpr = this.whereExpr === null ? expr : this.whereExpr.and(expr);
    return this;
  }

  orderAsc(column: Column): DownloadLabelDaoQueryBuilder {
    this.orderCol = column;
    this.orderAscending = true;
    return this;
  }

  orderDesc(column: Column): DownloadLabelDaoQueryBuilder {
    this.orderCol = column;
    this.orderAscending = false;
    return this;
  }

  limit(limit: number): DownloadLabelDaoQueryBuilder {
    this.limitValue = limit;
    this.hasLimit = true;
    return this;
  }

  offset(offset: number): DownloadLabelDaoQueryBuilder {
    this.offsetValue = offset;
    return this;
  }

  async list(): Promise<DownloadLabel[]> {
    return this.dao.queryBy(this.sql(), this.args());
  }

  async listLazy(): Promise<DownloadLabel[]> {
    return this.list();
  }

  async count(): Promise<number> {
    return this.dao.countBy(this.whereExpr, this.args());
  }

  sql(): string {
    let sql: string = 'SELECT * FROM "DOWNLOAD_LABELS"';
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

export class DownloadLabelDao {
  public static readonly TABLENAME: string = 'DOWNLOAD_LABELS';
  public static readonly PK_COLUMN: string = '_id';
  /** 上游 DownloadLabelDao.createTable 的 DDL，逐字保留。 */
  public static readonly CREATE_TABLE_SQL: string =
    'CREATE TABLE IF NOT EXISTS "DOWNLOAD_LABELS" ("_id" INTEGER PRIMARY KEY ,"LABEL" TEXT,"TIME" INTEGER NOT NULL );';
  public static readonly DROP_TABLE_SQL: string = 'DROP TABLE IF EXISTS "DOWNLOAD_LABELS"';
  public static readonly Properties: DownloadLabelDaoProperties = new DownloadLabelDaoProperties();

  private readonly store: relationalStore.RdbStore;

  constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  /** 对位上游静态 createTable(db, ifNotExists)。 */
  static async createTable(store: relationalStore.RdbStore, ifNotExists: boolean): Promise<void> {
    const sql: string = ifNotExists
      ? DownloadLabelDao.CREATE_TABLE_SQL
      : DownloadLabelDao.CREATE_TABLE_SQL.replace('IF NOT EXISTS ', '');
    await store.executeSql(sql);

  }

  /** 对位上游静态 dropTable(db, ifExists)。 */
  static async dropTable(store: relationalStore.RdbStore, ifExists: boolean): Promise<void> {
    await store.executeSql(ifExists ? DownloadLabelDao.DROP_TABLE_SQL : 'DROP TABLE "DOWNLOAD_LABELS"');
  }

  queryBuilder(): DownloadLabelDaoQueryBuilder {
    return new DownloadLabelDaoQueryBuilder(this);
  }

  async insert(entity: DownloadLabel): Promise<number> {
    return this.store.insert(DownloadLabelDao.TABLENAME, this.toBucket(entity));
  }

  async insertOrReplace(entity: DownloadLabel): Promise<number> {
    return this.store.insert(DownloadLabelDao.TABLENAME, this.toBucket(entity),
      relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  async save(entity: DownloadLabel): Promise<void> {
    if (entity.getId() !== null) {
      await this.update(entity);
    } else {
      const rowId: number = await this.insert(entity);
      entity.setId(rowId);
    }
  }

  async update(entity: DownloadLabel): Promise<void> {
    const key: number | null = entity.getId();
    if (key === null) {
      throw new Error('Cannot update entity without key - was it inserted before?');
    }
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates(DownloadLabelDao.TABLENAME);
    predicates.equalTo(DownloadLabelDao.PK_COLUMN, key);
    await this.store.update(this.toBucket(entity), predicates);
  }

  async delete(entity: DownloadLabel): Promise<void> {
    const key: number | null = entity.getId();
    if (key === null) {
      throw new Error('Cannot delete entity without key');
    }
    await this.deleteByKey(key);
  }

  async deleteByKey(key: number): Promise<void> {
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates(DownloadLabelDao.TABLENAME);
    predicates.equalTo(DownloadLabelDao.PK_COLUMN, key);
    await this.store.delete(predicates);
  }

  async deleteAll(): Promise<void> {
    await this.store.executeSql('DELETE FROM "DOWNLOAD_LABELS"');
  }

  async load(key: number): Promise<DownloadLabel | null> {
    const rows: DownloadLabel[] = await this.queryBy(
      'SELECT * FROM "DOWNLOAD_LABELS" WHERE "_id" = ?', [key]);
    return rows.length > 0 ? rows[0] : null;
  }

  async loadAll(): Promise<DownloadLabel[]> {
    return this.queryBy('SELECT * FROM "DOWNLOAD_LABELS"', []);
  }

  async count(): Promise<number> {
    return this.countBy(null, []);
  }

  async insertInTx(entities: DownloadLabel[]): Promise<void> {
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

  async updateInTx(entities: DownloadLabel[]): Promise<void> {
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

  async deleteInTx(entities: DownloadLabel[]): Promise<void> {
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
  toBucket(entity: DownloadLabel): relationalStore.ValuesBucket {
    const v_Id: number | null = entity.getId();
    const v_Label: string | null = entity.getLabel();
    const bucket: relationalStore.ValuesBucket = {
      '_id': v_Id !== null ? v_Id : null,
      'LABEL': v_Label !== null ? v_Label : null,
      'TIME': entity.getTime()
    };
    return bucket;
  }

  /** ResultSet 当前行 → 实体。 */
  fromResultSet(rs: relationalStore.ResultSet): DownloadLabel {
    const entity: DownloadLabel = new DownloadLabel();
    entity.setId(readNullableLong(rs, '_id'));
    entity.setLabel(readNullableString(rs, 'LABEL'));
    entity.setTime(readLong(rs, 'TIME'));
    return entity;
  }

  async queryBy(sql: string, args: relationalStore.ValueType[]): Promise<DownloadLabel[]> {
    const rs: relationalStore.ResultSet = await this.store.querySql(sql, args);
    const out: DownloadLabel[] = [];
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
    let sql: string = 'SELECT COUNT(*) AS C FROM "DOWNLOAD_LABELS"';
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
