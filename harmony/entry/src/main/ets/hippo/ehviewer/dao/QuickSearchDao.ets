/*
 * 对位上游：app/src/main/java/com/hippo/ehviewer/dao/QuickSearchDao.java（GreenDAO 生成 DAO）
 *
 * 表：QUICK_SEARCH —— CREATE_TABLE_SQL 逐字取自上游 createTable（列名/类型/约束未改一字），
 * 因此可以直接读写既有 Android App 的 ehviewer.db（继承旧数据的前提）。
 *
 * 平台对位（D-012 RDB 异步化）：GreenDAO 的 AbstractDao 基类不存在 → 手写等价方法集；
 * 所有方法返回 Promise（relationalStore 无同步 API），调用方 await。无反射：映射显式写死。
 */

import relationalStore from '@ohos.data.relationalStore';
import { Column, SqlExpr } from '../../database/MSQLiteBuilder';
import { QuickSearch } from './QuickSearch';

/** 对位 GreenDAO 的 QuickSearchDao.Properties。 */
export class QuickSearchDaoProperties {
  readonly Id: Column = new Column('_id');
  readonly Name: Column = new Column('NAME');
  readonly Mode: Column = new Column('MODE');
  readonly Category: Column = new Column('CATEGORY');
  readonly Keyword: Column = new Column('KEYWORD');
  readonly AdvanceSearch: Column = new Column('ADVANCE_SEARCH');
  readonly MinRating: Column = new Column('MIN_RATING');
  readonly PageFrom: Column = new Column('PAGE_FROM');
  readonly PageTo: Column = new Column('PAGE_TO');
  readonly Time: Column = new Column('TIME');
}

/** 对位 GreenDAO QueryBuilder 的常用子集（where/orderAsc/orderDesc/limit/offset/list/count）。 */
export class QuickSearchDaoQueryBuilder {
  private readonly dao: QuickSearchDao;
  private whereExpr: SqlExpr | null = null;
  private orderCol: Column | null = null;
  private orderAscending: boolean = true;
  private limitValue: number = 0;
  private hasLimit: boolean = false;
  private offsetValue: number = 0;

  constructor(dao: QuickSearchDao) {
    this.dao = dao;
  }

  where(expr: SqlExpr): QuickSearchDaoQueryBuilder {
    this.whereExpr = this.whereExpr === null ? expr : this.whereExpr.and(expr);
    return this;
  }

  orderAsc(column: Column): QuickSearchDaoQueryBuilder {
    this.orderCol = column;
    this.orderAscending = true;
    return this;
  }

  orderDesc(column: Column): QuickSearchDaoQueryBuilder {
    this.orderCol = column;
    this.orderAscending = false;
    return this;
  }

  limit(limit: number): QuickSearchDaoQueryBuilder {
    this.limitValue = limit;
    this.hasLimit = true;
    return this;
  }

  offset(offset: number): QuickSearchDaoQueryBuilder {
    this.offsetValue = offset;
    return this;
  }

  async list(): Promise<QuickSearch[]> {
    return this.dao.queryBy(this.sql(), this.args());
  }

  async listLazy(): Promise<QuickSearch[]> {
    return this.list();
  }

  async count(): Promise<number> {
    return this.dao.countBy(this.whereExpr, this.args());
  }

  sql(): string {
    let sql: string = 'SELECT * FROM "QUICK_SEARCH"';
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

export class QuickSearchDao {
  public static readonly TABLENAME: string = 'QUICK_SEARCH';
  public static readonly PK_COLUMN: string = '_id';
  /** 上游 QuickSearchDao.createTable 的 DDL，逐字保留。 */
  public static readonly CREATE_TABLE_SQL: string =
    'CREATE TABLE IF NOT EXISTS "QUICK_SEARCH" ("_id" INTEGER PRIMARY KEY ,"NAME" TEXT,"MODE" INTEGER NOT NULL ,"CATEGORY" INTEGER NOT NULL ,"KEYWORD" TEXT,"ADVANCE_SEARCH" INTEGER NOT NULL ,"MIN_RATING" INTEGER NOT NULL ,"PAGE_FROM" INTEGER NOT NULL ,"PAGE_TO" INTEGER NOT NULL ,"TIME" INTEGER NOT NULL );';
  public static readonly DROP_TABLE_SQL: string = 'DROP TABLE IF EXISTS "QUICK_SEARCH"';
  public static readonly Properties: QuickSearchDaoProperties = new QuickSearchDaoProperties();

  private readonly store: relationalStore.RdbStore;

  constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  /** 对位上游静态 createTable(db, ifNotExists)。 */
  static async createTable(store: relationalStore.RdbStore, ifNotExists: boolean): Promise<void> {
    const sql: string = ifNotExists
      ? QuickSearchDao.CREATE_TABLE_SQL
      : QuickSearchDao.CREATE_TABLE_SQL.replace('IF NOT EXISTS ', '');
    await store.executeSql(sql);

  }

  /** 对位上游静态 dropTable(db, ifExists)。 */
  static async dropTable(store: relationalStore.RdbStore, ifExists: boolean): Promise<void> {
    await store.executeSql(ifExists ? QuickSearchDao.DROP_TABLE_SQL : 'DROP TABLE "QUICK_SEARCH"');
  }

  queryBuilder(): QuickSearchDaoQueryBuilder {
    return new QuickSearchDaoQueryBuilder(this);
  }

  async insert(entity: QuickSearch): Promise<number> {
    return this.store.insert(QuickSearchDao.TABLENAME, this.toBucket(entity));
  }

  async insertOrReplace(entity: QuickSearch): Promise<number> {
    return this.store.insert(QuickSearchDao.TABLENAME, this.toBucket(entity),
      relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  async save(entity: QuickSearch): Promise<void> {
    if (entity.getId() !== null) {
      await this.update(entity);
    } else {
      const rowId: number = await this.insert(entity);
      entity.setId(rowId);
    }
  }

  async update(entity: QuickSearch): Promise<void> {
    const key: number | null = entity.getId();
    if (key === null) {
      throw new Error('Cannot update entity without key - was it inserted before?');
    }
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates(QuickSearchDao.TABLENAME);
    predicates.equalTo(QuickSearchDao.PK_COLUMN, key);
    await this.store.update(this.toBucket(entity), predicates);
  }

  async delete(entity: QuickSearch): Promise<void> {
    const key: number | null = entity.getId();
    if (key === null) {
      throw new Error('Cannot delete entity without key');
    }
    await this.deleteByKey(key);
  }

  async deleteByKey(key: number): Promise<void> {
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates(QuickSearchDao.TABLENAME);
    predicates.equalTo(QuickSearchDao.PK_COLUMN, key);
    await this.store.delete(predicates);
  }

  async deleteAll(): Promise<void> {
    await this.store.executeSql('DELETE FROM "QUICK_SEARCH"');
  }

  async load(key: number): Promise<QuickSearch | null> {
    const rows: QuickSearch[] = await this.queryBy(
      'SELECT * FROM "QUICK_SEARCH" WHERE "_id" = ?', [key]);
    return rows.length > 0 ? rows[0] : null;
  }

  async loadAll(): Promise<QuickSearch[]> {
    return this.queryBy('SELECT * FROM "QUICK_SEARCH"', []);
  }

  async count(): Promise<number> {
    return this.countBy(null, []);
  }

  async insertInTx(entities: QuickSearch[]): Promise<void> {
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

  async updateInTx(entities: QuickSearch[]): Promise<void> {
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

  async deleteInTx(entities: QuickSearch[]): Promise<void> {
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
  toBucket(entity: QuickSearch): relationalStore.ValuesBucket {
    const v_Id: number | null = entity.getId();
    const v_Name: string | null = entity.getName();
    const v_Keyword: string | null = entity.getKeyword();
    const bucket: relationalStore.ValuesBucket = {
      '_id': v_Id !== null ? v_Id : null,
      'NAME': v_Name !== null ? v_Name : null,
      'MODE': entity.getMode(),
      'CATEGORY': entity.getCategory(),
      'KEYWORD': v_Keyword !== null ? v_Keyword : null,
      'ADVANCE_SEARCH': entity.getAdvanceSearch(),
      'MIN_RATING': entity.getMinRating(),
      'PAGE_FROM': entity.getPageFrom(),
      'PAGE_TO': entity.getPageTo(),
      'TIME': entity.getTime()
    };
    return bucket;
  }

  /** ResultSet 当前行 → 实体。 */
  fromResultSet(rs: relationalStore.ResultSet): QuickSearch {
    const entity: QuickSearch = new QuickSearch();
    entity.setId(readNullableLong(rs, '_id'));
    entity.setName(readNullableString(rs, 'NAME'));
    entity.setMode(readLong(rs, 'MODE'));
    entity.setCategory(readLong(rs, 'CATEGORY'));
    entity.setKeyword(readNullableString(rs, 'KEYWORD'));
    entity.setAdvanceSearch(readLong(rs, 'ADVANCE_SEARCH'));
    entity.setMinRating(readLong(rs, 'MIN_RATING'));
    entity.setPageFrom(readLong(rs, 'PAGE_FROM'));
    entity.setPageTo(readLong(rs, 'PAGE_TO'));
    entity.setTime(readLong(rs, 'TIME'));
    return entity;
  }

  async queryBy(sql: string, args: relationalStore.ValueType[]): Promise<QuickSearch[]> {
    const rs: relationalStore.ResultSet = await this.store.querySql(sql, args);
    const out: QuickSearch[] = [];
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
    let sql: string = 'SELECT COUNT(*) AS C FROM "QUICK_SEARCH"';
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
