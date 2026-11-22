/*
 * 对位上游：app/src/main/java/com/hippo/ehviewer/dao/GalleryTagsDao.java（GreenDAO 生成 DAO）
 *
 * 表：Gallery_Tags —— CREATE_TABLE_SQL 逐字取自上游 createTable（列名/类型/约束未改一字），
 * 因此可以直接读写既有 Android App 的 ehviewer.db（继承旧数据的前提）。
 *
 * 平台对位（D-012 RDB 异步化）：GreenDAO 的 AbstractDao 基类不存在 → 手写等价方法集；
 * 所有方法返回 Promise（relationalStore 无同步 API），调用方 await。无反射：映射显式写死。
 */

import relationalStore from '@ohos.data.relationalStore';
import { Column, SqlExpr } from '../../database/MSQLiteBuilder';
import { GalleryTags } from './GalleryTags';

/** 对位 GreenDAO 的 GalleryTagsDao.Properties。 */
export class GalleryTagsDaoProperties {
  readonly Gid: Column = new Column('GID');
  readonly Rows: Column = new Column('ROWS');
  readonly Artist: Column = new Column('ARTIST');
  readonly Cosplayer: Column = new Column('COSPLAYER');
  readonly Character: Column = new Column('CHARACTER');
  readonly Female: Column = new Column('FEMALE');
  readonly Group: Column = new Column('GROUP');
  readonly Language: Column = new Column('LANGUAGE');
  readonly Male: Column = new Column('MALE');
  readonly Misc: Column = new Column('MISC');
  readonly Mixed: Column = new Column('MIXED');
  readonly Other: Column = new Column('OTHER');
  readonly Parody: Column = new Column('PARODY');
  readonly Reclass: Column = new Column('RECLASS');
  readonly Create_time: Column = new Column('CREATE_TIME');
  readonly Update_time: Column = new Column('UPDATE_TIME');
  readonly Location: Column = new Column('LOCATION');
}

/** 对位 GreenDAO QueryBuilder 的常用子集（where/orderAsc/orderDesc/limit/offset/list/count）。 */
export class GalleryTagsDaoQueryBuilder {
  private readonly dao: GalleryTagsDao;
  private whereExpr: SqlExpr | null = null;
  private orderCol: Column | null = null;
  private orderAscending: boolean = true;
  private limitValue: number = 0;
  private hasLimit: boolean = false;
  private offsetValue: number = 0;

  constructor(dao: GalleryTagsDao) {
    this.dao = dao;
  }

  where(expr: SqlExpr): GalleryTagsDaoQueryBuilder {
    this.whereExpr = this.whereExpr === null ? expr : this.whereExpr.and(expr);
    return this;
  }

  orderAsc(column: Column): GalleryTagsDaoQueryBuilder {
    this.orderCol = column;
    this.orderAscending = true;
    return this;
  }

  orderDesc(column: Column): GalleryTagsDaoQueryBuilder {
    this.orderCol = column;
    this.orderAscending = false;
    return this;
  }

  limit(limit: number): GalleryTagsDaoQueryBuilder {
    this.limitValue = limit;
    this.hasLimit = true;
    return this;
  }

  offset(offset: number): GalleryTagsDaoQueryBuilder {
    this.offsetValue = offset;
    return this;
  }

  async list(): Promise<GalleryTags[]> {
    return this.dao.queryBy(this.sql(), this.args());
  }

  async listLazy(): Promise<GalleryTags[]> {
    return this.list();
  }

  async count(): Promise<number> {
    return this.dao.countBy(this.whereExpr, this.args());
  }

  sql(): string {
    let sql: string = 'SELECT * FROM "Gallery_Tags"';
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

export class GalleryTagsDao {
  public static readonly TABLENAME: string = 'Gallery_Tags';
  public static readonly PK_COLUMN: string = 'GID';
  /** 上游 GalleryTagsDao.createTable 的 DDL，逐字保留。 */
  public static readonly CREATE_TABLE_SQL: string =
    'CREATE TABLE IF NOT EXISTS "Gallery_Tags" ("GID" INTEGER PRIMARY KEY NOT NULL ,"ROWS" TEXT,"ARTIST" TEXT,"COSPLAYER" TEXT,"CHARACTER" TEXT,"FEMALE" TEXT,"GROUP" TEXT,"LANGUAGE" TEXT,"MALE" TEXT,"MISC" TEXT,"MIXED" TEXT,"OTHER" TEXT,"PARODY" TEXT,"RECLASS" TEXT,"CREATE_TIME" INTEGER,"UPDATE_TIME" INTEGER,"LOCATION" TEXT);';
  public static readonly DROP_TABLE_SQL: string = 'DROP TABLE IF EXISTS "Gallery_Tags"';
  public static readonly Properties: GalleryTagsDaoProperties = new GalleryTagsDaoProperties();

  private readonly store: relationalStore.RdbStore;

  constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  /** 对位上游静态 createTable(db, ifNotExists)。 */
  static async createTable(store: relationalStore.RdbStore, ifNotExists: boolean): Promise<void> {
    const sql: string = ifNotExists
      ? GalleryTagsDao.CREATE_TABLE_SQL
      : GalleryTagsDao.CREATE_TABLE_SQL.replace('IF NOT EXISTS ', '');
    await store.executeSql(sql);

  }

  /** 对位上游静态 dropTable(db, ifExists)。 */
  static async dropTable(store: relationalStore.RdbStore, ifExists: boolean): Promise<void> {
    await store.executeSql(ifExists ? GalleryTagsDao.DROP_TABLE_SQL : 'DROP TABLE "Gallery_Tags"');
  }

  queryBuilder(): GalleryTagsDaoQueryBuilder {
    return new GalleryTagsDaoQueryBuilder(this);
  }

  async insert(entity: GalleryTags): Promise<number> {
    return this.store.insert(GalleryTagsDao.TABLENAME, this.toBucket(entity));
  }

  async insertOrReplace(entity: GalleryTags): Promise<number> {
    return this.store.insert(GalleryTagsDao.TABLENAME, this.toBucket(entity),
      relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  async save(entity: GalleryTags): Promise<void> {
    const exists: GalleryTags | null = await this.load(entity.getGid());
    if (exists !== null) {
      await this.update(entity);
    } else {
      await this.insert(entity);
    }
  }

  async update(entity: GalleryTags): Promise<void> {
    const key: number | null = entity.getGid();
    if (key === null) {
      throw new Error('Cannot update entity without key - was it inserted before?');
    }
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates(GalleryTagsDao.TABLENAME);
    predicates.equalTo(GalleryTagsDao.PK_COLUMN, key);
    await this.store.update(this.toBucket(entity), predicates);
  }

  async delete(entity: GalleryTags): Promise<void> {
    const key: number | null = entity.getGid();
    if (key === null) {
      throw new Error('Cannot delete entity without key');
    }
    await this.deleteByKey(key);
  }

  async deleteByKey(key: number): Promise<void> {
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates(GalleryTagsDao.TABLENAME);
    predicates.equalTo(GalleryTagsDao.PK_COLUMN, key);
    await this.store.delete(predicates);
  }

  async deleteAll(): Promise<void> {
    await this.store.executeSql('DELETE FROM "Gallery_Tags"');
  }

  async load(key: number): Promise<GalleryTags | null> {
    const rows: GalleryTags[] = await this.queryBy(
      'SELECT * FROM "Gallery_Tags" WHERE "GID" = ?', [key]);
    return rows.length > 0 ? rows[0] : null;
  }

  async loadAll(): Promise<GalleryTags[]> {
    return this.queryBy('SELECT * FROM "Gallery_Tags"', []);
  }

  async count(): Promise<number> {
    return this.countBy(null, []);
  }

  async insertInTx(entities: GalleryTags[]): Promise<void> {
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

  async updateInTx(entities: GalleryTags[]): Promise<void> {
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

  async deleteInTx(entities: GalleryTags[]): Promise<void> {
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
  toBucket(entity: GalleryTags): relationalStore.ValuesBucket {
    const v_Rows: string | null = entity.getRows();
    const v_Artist: string | null = entity.getArtist();
    const v_Cosplayer: string | null = entity.getCosplayer();
    const v_Character: string | null = entity.getCharacter();
    const v_Female: string | null = entity.getFemale();
    const v_Group: string | null = entity.getGroup();
    const v_Language: string | null = entity.getLanguage();
    const v_Male: string | null = entity.getMale();
    const v_Misc: string | null = entity.getMisc();
    const v_Mixed: string | null = entity.getMixed();
    const v_Other: string | null = entity.getOther();
    const v_Parody: string | null = entity.getParody();
    const v_Reclass: string | null = entity.getReclass();
    const v_Create_time: Date | null = entity.getCreate_time();
    const v_Update_time: Date | null = entity.getUpdate_time();
    const v_Location: string | null = entity.getLocation();
    const bucket: relationalStore.ValuesBucket = {
      'GID': entity.getGid(),
      'ROWS': v_Rows !== null ? v_Rows : null,
      'ARTIST': v_Artist !== null ? v_Artist : null,
      'COSPLAYER': v_Cosplayer !== null ? v_Cosplayer : null,
      'CHARACTER': v_Character !== null ? v_Character : null,
      'FEMALE': v_Female !== null ? v_Female : null,
      'GROUP': v_Group !== null ? v_Group : null,
      'LANGUAGE': v_Language !== null ? v_Language : null,
      'MALE': v_Male !== null ? v_Male : null,
      'MISC': v_Misc !== null ? v_Misc : null,
      'MIXED': v_Mixed !== null ? v_Mixed : null,
      'OTHER': v_Other !== null ? v_Other : null,
      'PARODY': v_Parody !== null ? v_Parody : null,
      'RECLASS': v_Reclass !== null ? v_Reclass : null,
      'CREATE_TIME': v_Create_time !== null ? v_Create_time.getTime() : null,
      'UPDATE_TIME': v_Update_time !== null ? v_Update_time.getTime() : null,
      'LOCATION': v_Location !== null ? v_Location : null
    };
    return bucket;
  }

  /** ResultSet 当前行 → 实体。 */
  fromResultSet(rs: relationalStore.ResultSet): GalleryTags {
    const entity: GalleryTags = new GalleryTags();
    entity.setGid(readLong(rs, 'GID'));
    entity.setRows(readNullableString(rs, 'ROWS'));
    entity.setArtist(readNullableString(rs, 'ARTIST'));
    entity.setCosplayer(readNullableString(rs, 'COSPLAYER'));
    entity.setCharacter(readNullableString(rs, 'CHARACTER'));
    entity.setFemale(readNullableString(rs, 'FEMALE'));
    entity.setGroup(readNullableString(rs, 'GROUP'));
    entity.setLanguage(readNullableString(rs, 'LANGUAGE'));
    entity.setMale(readNullableString(rs, 'MALE'));
    entity.setMisc(readNullableString(rs, 'MISC'));
    entity.setMixed(readNullableString(rs, 'MIXED'));
    entity.setOther(readNullableString(rs, 'OTHER'));
    entity.setParody(readNullableString(rs, 'PARODY'));
    entity.setReclass(readNullableString(rs, 'RECLASS'));
    entity.setCreate_time(readNullableDate(rs, 'CREATE_TIME'));
    entity.setUpdate_time(readNullableDate(rs, 'UPDATE_TIME'));
    entity.setLocation(readNullableString(rs, 'LOCATION'));
    return entity;
  }

  async queryBy(sql: string, args: relationalStore.ValueType[]): Promise<GalleryTags[]> {
    const rs: relationalStore.ResultSet = await this.store.querySql(sql, args);
    const out: GalleryTags[] = [];
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
    let sql: string = 'SELECT COUNT(*) AS C FROM "Gallery_Tags"';
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
