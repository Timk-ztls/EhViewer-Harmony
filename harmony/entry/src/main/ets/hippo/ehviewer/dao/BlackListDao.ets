/*
 * 对位上游：app/src/main/java/com/hippo/ehviewer/dao/BlackListDao.java（GreenDAO 生成 DAO）
 *
 * 表：Black_List（DDL 逐字来自上游 createTable，见 CREATE_TABLE_SQL / CREATE_INDEX_SQL）
 *
 * 平台对位（D-012 RDB 异步化）：
 *   - GreenDAO 的 AbstractDao 基类在 ArkTS 不存在 → 手写等价方法集（insert/insertOrReplace/save/
 *     update/delete/deleteByKey/deleteAll/load/loadAll/count/insertInTx/deleteInTx/updateInTx/queryBuilder）。
 *   - 全部方法返回 Promise：`@ohos.data.relationalStore` 没有同步 API（DEVIATIONS D-012），
 *     调用方一律 `await`。
 *   - 无反射：实体 ↔ 列的映射是显式 toBucket()/fromResultSet()，列名常量集中在 Properties。
 *   - QueryBuilder：上游 `dao.queryBuilder().orderAsc(BlackListDao.Properties.Add_time).list()`
 *     的调用形状用 Column + SqlExpr 复刻（Column 定义在 database/MSQLiteBuilder.ets），
 *     SQL 文本与 GreenDAO 生成的一致（`SELECT * FROM "T" WHERE ... ORDER BY "C" ASC LIMIT n OFFSET m`）。
 */

import relationalStore from '@ohos.data.relationalStore';
import { Column, SqlExpr } from '../../database/MSQLiteBuilder';
import { BlackList } from './BlackList';

/** 对位 GreenDAO 的 `BlackListDao.Properties`（列名全大写，逐字取自建表语句）。 */
export class BlackListDaoProperties {
  readonly Id: Column = new Column('_id');
  readonly Badgayname: Column = new Column('BADGAYNAME');
  readonly Reason: Column = new Column('REASON');
  readonly Angrywith: Column = new Column('ANGRYWITH');
  readonly Add_time: Column = new Column('ADD_TIME');
  readonly Mode: Column = new Column('MODE');
}

/** 对位 GreenDAO QueryBuilder 的常用子集（只实现上游实际用到的：where/orderAsc/orderDesc/limit/offset/list）。 */
export class BlackListQueryBuilder {
  private readonly dao: BlackListDao;
  private whereExpr: SqlExpr | null = null;
  private orderCol: Column | null = null;
  private orderAscending: boolean = true;
  private limitValue: number = 0;
  private hasLimit: boolean = false;
  private offsetValue: number = 0;

  constructor(dao: BlackListDao) {
    this.dao = dao;
  }

  where(expr: SqlExpr): BlackListQueryBuilder {
    this.whereExpr = this.whereExpr === null ? expr : this.whereExpr.and(expr);
    return this;
  }

  orderAsc(column: Column): BlackListQueryBuilder {
    this.orderCol = column;
    this.orderAscending = true;
    return this;
  }

  orderDesc(column: Column): BlackListQueryBuilder {
    this.orderCol = column;
    this.orderAscending = false;
    return this;
  }

  limit(limit: number): BlackListQueryBuilder {
    this.limitValue = limit;
    this.hasLimit = true;
    return this;
  }

  offset(offset: number): BlackListQueryBuilder {
    this.offsetValue = offset;
    return this;
  }

  async list(): Promise<BlackList[]> {
    return this.dao.queryBy(this.sql(), this.args());
  }

  /** 对位 listLazy()：懒加载在 ArkTS 无对应，等价为一次性 list（调用方只做遍历）。 */
  async listLazy(): Promise<BlackList[]> {
    return this.list();
  }

  async count(): Promise<number> {
    return this.dao.countBy(this.whereExpr, this.args());
  }

  sql(): string {
    let sql: string = `SELECT * FROM "${BlackListDao.TABLENAME}"`;
    if (this.whereExpr !== null) {
      sql += ` WHERE ${this.whereExpr.sql}`;
    }
    if (this.orderCol !== null) {
      sql += ` ORDER BY "${this.orderCol.columnName}" ${this.orderAscending ? 'ASC' : 'DESC'}`;
    }
    if (this.hasLimit) {
      sql += ` LIMIT ${this.limitValue}`;
      if (this.offsetValue > 0) {
        sql += ` OFFSET ${this.offsetValue}`;
      }
    } else if (this.offsetValue > 0) {
      sql += ` LIMIT -1 OFFSET ${this.offsetValue}`;
    }
    return sql;
  }

  args(): relationalStore.ValueType[] {
    const out: relationalStore.ValueType[] = [];
    if (this.whereExpr !== null) {
      for (const a of this.whereExpr.args) {
        out.push(a);
      }
    }
    return out;
  }
}

export class BlackListDao {
  public static readonly TABLENAME: string = 'Black_List';
  public static readonly PK_COLUMN: string = '_id';
  /** 上游 BlackListDao.createTable 的 DDL，逐字保留（constraint = IF NOT EXISTS）。 */
  public static readonly CREATE_TABLE_SQL: string =
    'CREATE TABLE IF NOT EXISTS "Black_List" ("_id" INTEGER PRIMARY KEY AUTOINCREMENT ,"BADGAYNAME" TEXT,"REASON" TEXT,"ANGRYWITH" TEXT,"ADD_TIME" TEXT,"MODE" INTEGER);';
  /** 上游 BlackListDao.createTable 里紧随其后的索引（列：BADGAYNAME）。 */
  public static readonly CREATE_INDEX_SQL: string =
    'CREATE INDEX IF NOT EXISTS IDX_Black_List_BADGAYNAME ON Black_List ("BADGAYNAME");';
  public static readonly DROP_TABLE_SQL: string = 'DROP TABLE IF EXISTS "Black_List"';
  public static readonly Properties: BlackListDaoProperties = new BlackListDaoProperties();

  private readonly store: relationalStore.RdbStore;

  constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  /** 对位上游静态 createTable(db, ifNotExists)。 */
  static async createTable(store: relationalStore.RdbStore, ifNotExists: boolean): Promise<void> {
    const sql: string = ifNotExists
      ? BlackListDao.CREATE_TABLE_SQL
      : BlackListDao.CREATE_TABLE_SQL.replace('IF NOT EXISTS ', '');
    await store.executeSql(sql);
    const idx: string = ifNotExists
      ? BlackListDao.CREATE_INDEX_SQL
      : BlackListDao.CREATE_INDEX_SQL.replace('IF NOT EXISTS ', '');
    await store.executeSql(idx);
  }

  /** 对位上游静态 dropTable(db, ifExists)。 */
  static async dropTable(store: relationalStore.RdbStore, ifExists: boolean): Promise<void> {
    await store.executeSql(ifExists ? BlackListDao.DROP_TABLE_SQL : `DROP TABLE "Black_List"`);
  }

  /** 对位上游 dao.queryBuilder()。 */
  queryBuilder(): BlackListQueryBuilder {
    return new BlackListQueryBuilder(this);
  }

  /** 对位 AbstractDao.insert：返回 rowId。 */
  async insert(entity: BlackList): Promise<number> {
    return this.store.insert(BlackListDao.TABLENAME, this.toBucket(entity));
  }

  /** 对位 AbstractDao.insertOrReplace（主键冲突时替换）。 */
  async insertOrReplace(entity: BlackList): Promise<number> {
    return this.store.insert(BlackListDao.TABLENAME, this.toBucket(entity),
      relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  /** 对位 AbstractDao.save：有主键则 update，否则 insert。 */
  async save(entity: BlackList): Promise<void> {
    if (entity.id !== null) {
      await this.update(entity);
    } else {
      const rowId: number = await this.insert(entity);
      entity.id = rowId;
    }
  }

  /** 对位 AbstractDao.update（按主键）。 */
  async update(entity: BlackList): Promise<void> {
    if (entity.id === null) {
      throw new Error('Cannot update entity without key - was it inserted before?');
    }
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates(BlackListDao.TABLENAME);
    predicates.equalTo(BlackListDao.PK_COLUMN, entity.id);
    await this.store.update(this.toBucket(entity), predicates);
  }

  /** 对位 AbstractDao.delete（按实体主键）。 */
  async delete(entity: BlackList): Promise<void> {
    if (entity.id === null) {
      throw new Error('Cannot delete entity without key');
    }
    await this.deleteByKey(entity.id);
  }

  /** 对位 AbstractDao.deleteByKey。 */
  async deleteByKey(key: number): Promise<void> {
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates(BlackListDao.TABLENAME);
    predicates.equalTo(BlackListDao.PK_COLUMN, key);
    await this.store.delete(predicates);
  }

  /** 对位 AbstractDao.deleteAll。 */
  async deleteAll(): Promise<void> {
    await this.store.executeSql(`DELETE FROM "${BlackListDao.TABLENAME}"`);
  }

  /** 对位 AbstractDao.load（按主键，未找到返回 null）。 */
  async load(key: number): Promise<BlackList | null> {
    const rows: BlackList[] = await this.queryBy(
      `SELECT * FROM "${BlackListDao.TABLENAME}" WHERE "${BlackListDao.PK_COLUMN}" = ?`, [key]);
    return rows.length > 0 ? rows[0] : null;
  }

  /** 对位 AbstractDao.loadAll。 */
  async loadAll(): Promise<BlackList[]> {
    return this.queryBy(`SELECT * FROM "${BlackListDao.TABLENAME}"`, []);
  }

  /** 对位 AbstractDao.count。 */
  async count(): Promise<number> {
    return this.countBy(null, []);
  }

  /** 对位 AbstractDao.insertInTx。 */
  async insertInTx(entities: BlackList[]): Promise<void> {
    this.store.beginTransaction();
    try {
      for (const e of entities) {
        await this.insert(e);
      }
      this.store.commit();
    } catch (e) {
      this.store.rollBack();
      throw e as Error;
    }
  }

  /** 对位 AbstractDao.updateInTx。 */
  async updateInTx(entities: BlackList[]): Promise<void> {
    this.store.beginTransaction();
    try {
      for (const e of entities) {
        await this.update(e);
      }
      this.store.commit();
    } catch (e) {
      this.store.rollBack();
      throw e as Error;
    }
  }

  /** 对位 AbstractDao.deleteInTx。 */
  async deleteInTx(entities: BlackList[]): Promise<void> {
    this.store.beginTransaction();
    try {
      for (const e of entities) {
        await this.delete(e);
      }
      this.store.commit();
    } catch (e) {
      this.store.rollBack();
      throw e as Error;
    }
  }

  // ---------------------------------------------------------------- 内部映射

  /**
   * 实体 → ValuesBucket（列名逐字对齐 DDL）。
   * 可空列先落局部变量再收窄：ArkTS 的类型收窄只对局部变量生效，getter 调两次不会收窄
   * （否则得到 `string | null | undefined`，ValueType 不收 undefined）。
   * 主键 `_id` 必须显式进 bucket：漏了它 insertOrReplace 就无法按主键替换，
   * `save()` 的主键回写语义也会丢（check-columns.ps1 断言的就是这条）。
   */
  toBucket(entity: BlackList): relationalStore.ValuesBucket {
    const v_Id: number | null = entity.getId();
    const v_Badgayname: string | null = entity.getBadgayname();
    const v_Reason: string | null = entity.getReason();
    const v_Angrywith: string | null = entity.getAngrywith();
    const v_Add_time: string | null = entity.getAdd_time();
    const v_Mode: number | null = entity.getMode();
    const bucket: relationalStore.ValuesBucket = {
      '_id': v_Id !== null ? v_Id : null,
      'BADGAYNAME': v_Badgayname !== null ? v_Badgayname : null,
      'REASON': v_Reason !== null ? v_Reason : null,
      'ANGRYWITH': v_Angrywith !== null ? v_Angrywith : null,
      'ADD_TIME': v_Add_time !== null ? v_Add_time : null,
      'MODE': v_Mode !== null ? v_Mode : null
    };
    return bucket;
  }

  /** ResultSet 当前行 → 实体。 */
  fromResultSet(rs: relationalStore.ResultSet): BlackList {
    const entity: BlackList = new BlackList();
    entity.id = readNullableLong(rs, '_id');
    entity.badgayname = readNullableString(rs, 'BADGAYNAME');
    entity.reason = readNullableString(rs, 'REASON');
    entity.angrywith = readNullableString(rs, 'ANGRYWITH');
    entity.add_time = readNullableString(rs, 'ADD_TIME');
    entity.mode = readNullableLong(rs, 'MODE');
    return entity;
  }

  /** 供 QueryBuilder 用的 SQL 直查。 */
  async queryBy(sql: string, args: relationalStore.ValueType[]): Promise<BlackList[]> {
    const rs: relationalStore.ResultSet = await this.store.querySql(sql, args);
    const out: BlackList[] = [];
    try {
      while (rs.goToNextRow()) {
        out.push(this.fromResultSet(rs));
      }
    } finally {
      rs.close();
    }
    return out;
  }

  /** 计数（对位 QueryBuilder.count()）。 */
  async countBy(whereExpr: SqlExpr | null, args: relationalStore.ValueType[]): Promise<number> {
    let sql: string = `SELECT COUNT(*) AS C FROM "${BlackListDao.TABLENAME}"`;
    if (whereExpr !== null) {
      sql += ` WHERE ${whereExpr.sql}`;
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

/** 读可空 INTEGER 列（ArkTS 无装箱类型，用 undefined 表达 NULL）。 */
function readNullableLong(rs: relationalStore.ResultSet, column: string): number | null {
  const idx: number = rs.getColumnIndex(column);
  if (idx < 0 || rs.isColumnNull(idx)) {
    return null;
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
