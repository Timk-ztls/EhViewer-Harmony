/*
 * 对位上游：app/src/main/java/com/hippo/database/MSQLiteBuilder.java
 *
 * 用途（上游不变）：以「版本 → 语句列表」的链式 API 声明式拼迁移脚本，交给 MSQLiteOpenHelper 执行。
 * 调用方：EhDB（core-runtime, S0150）与 SearchDatabase（ui-widget）。
 *
 * 平台对位：
 *   - 上游用 java.lang.Class 做「Java 类型 → SQLite 类型」查表（int.class / String.class ...）。
 *     ArkTS 没有 Class 对象，改为字符串类型令牌（SqlType.INT 等），映射表内容与上游逐条一致：
 *       boolean/byte/short/int/long → "INTEGER NOT NULL DEFAULT 0"
 *       float/double                → "REAL NOT NULL DEFAULT 0"
 *       String                      → "TEXT"
 *   - build(context, name, version) 返回 MSQLiteOpenHelper；鸿蒙侧打开 store 是异步的
 *     （relationalStore.getRdbStore 只有 Promise/callback），故 helper 的 open() 返回 Promise。
 *     上游是同步 getWritableDb()，这一点在 DEVIATIONS 候选 D-010「RDB 异步化」里登记。
 *   - 额外补充（本 port 新增，供 dao/ 层复用，不改变上游任何方法语义）：
 *       Column / SqlExpr —— GreenDAO QueryBuilder 的 where 片段等价物。
 *     放在本文件是因为它是本模块唯一的 SQL 片段构造器，且必须是最底层（dao/* 依赖它，反向不依赖），
 *     这样 DaoMaster→Dao→本文件 是单向依赖，不会出现 ArkTS ESM 循环。
 */

import common from '@ohos.app.ability.common';
import { MSQLiteOpenHelper } from './MSQLiteOpenHelper';

/** 上游用 Class 令牌表达的类型，这里改成字符串令牌（值取自 Java 侧同名类型）。 */
export class SqlType {
  static readonly BOOLEAN: string = 'boolean';
  static readonly BYTE: string = 'byte';
  static readonly SHORT: string = 'short';
  static readonly INT: string = 'int';
  static readonly LONG: string = 'long';
  static readonly FLOAT: string = 'float';
  static readonly DOUBLE: string = 'double';
  static readonly STRING: string = 'String';
}

/** 绑定参数值（对位 RDB 的 ValueType 子集）。 */
export type SqlArg = string | number | boolean | null;

/**
 * where 片段：SQL 文本 + 绑定参数。
 * 对位 GreenDAO 的 `Property.eq()/like()` 返回的 WhereCondition。
 */
export class SqlExpr {
  readonly sql: string;
  readonly args: SqlArg[];

  constructor(sql: string, args: SqlArg[]) {
    this.sql = sql;
    this.args = args;
  }

  /** AND 组合（对位 WhereCondition.and()）。 */
  and(other: SqlExpr): SqlExpr {
    const merged: SqlArg[] = [];
    for (const a of this.args) {
      merged.push(a);
    }
    for (const a of other.args) {
      merged.push(a);
    }
    return new SqlExpr(`(${this.sql}) AND (${other.sql})`, merged);
  }

  /** OR 组合（对位 WhereCondition.or()）。 */
  or(other: SqlExpr): SqlExpr {
    const merged: SqlArg[] = [];
    for (const a of this.args) {
      merged.push(a);
    }
    for (const a of other.args) {
      merged.push(a);
    }
    return new SqlExpr(`(${this.sql}) OR (${other.sql})`, merged);
  }

  static empty(): SqlExpr {
    return new SqlExpr('', []);
  }
}

/**
 * 列引用：对位 GreenDAO 的 Property（eq/like/in 等条件构造器）。
 * 列名必须是真实列名（全大写下划线，见各 Dao 的 CREATE_TABLE_SQL）。
 */
export class Column {
  readonly columnName: string;

  constructor(columnName: string) {
    this.columnName = columnName;
  }

  eq(value: SqlArg): SqlExpr {
    return new SqlExpr(`"${this.columnName}" = ?`, [value]);
  }

  notEq(value: SqlArg): SqlExpr {
    return new SqlExpr(`"${this.columnName}" <> ?`, [value]);
  }

  /** 对位 GreenDAO Property.like(String)：模糊匹配（调用方自己带 %）。 */
  like(value: string): SqlExpr {
    return new SqlExpr(`"${this.columnName}" LIKE ?`, [value]);
  }

  gt(value: SqlArg): SqlExpr {
    return new SqlExpr(`"${this.columnName}" > ?`, [value]);
  }

  lt(value: SqlArg): SqlExpr {
    return new SqlExpr(`"${this.columnName}" < ?`, [value]);
  }

  isNull(): SqlExpr {
    return new SqlExpr(`"${this.columnName}" IS NULL`, []);
  }

  /** 对位 Property.in(Collection)：参数个数决定占位符个数。 */
  in(values: SqlArg[]): SqlExpr {
    if (values.length === 0) {
      // SQL 语义：IN () 恒 false
      return new SqlExpr('0', []);
    }
    const holders: string[] = [];
    for (let i = 0; i < values.length; i++) {
      holders.push('?');
    }
    return new SqlExpr(`"${this.columnName}" IN (${holders.join(',')})`, values);
  }
}

export class MSQLiteBuilder {
  public static readonly COLUMN_ID: string = '_id';

  /**
   * 上游 JAVA_TYPE_TO_SQLITE_TYPE 的等价表（值逐字保留，含 "NOT NULL DEFAULT 0"）。
   * ArkTS 的 Map 字面量构造，键为 SqlType 的字符串令牌。
   */
  private static readonly TYPE_TO_SQLITE: Map<string, string> = new Map<string, string>([
    [SqlType.BOOLEAN, 'INTEGER NOT NULL DEFAULT 0'],
    [SqlType.BYTE, 'INTEGER NOT NULL DEFAULT 0'],
    [SqlType.SHORT, 'INTEGER NOT NULL DEFAULT 0'],
    [SqlType.INT, 'INTEGER NOT NULL DEFAULT 0'],
    [SqlType.LONG, 'INTEGER NOT NULL DEFAULT 0'],
    [SqlType.FLOAT, 'REAL NOT NULL DEFAULT 0'],
    [SqlType.DOUBLE, 'REAL NOT NULL DEFAULT 0'],
    [SqlType.STRING, 'TEXT']
  ]);

  private static javaTypeToSQLiteType(javaType: string): string {
    const type: string | undefined = MSQLiteBuilder.TYPE_TO_SQLITE.get(javaType);
    if (type === undefined) {
      throw new Error(`Unknown type: ${javaType}`);
    }
    return type;
  }

  private versionValue: number = 0;
  private statements: string[] | null = null;
  private readonly statementsMap: Map<number, string[]> = new Map<number, string[]>();

  /** 提升数据库版本（上游 version(int)）。 */
  version(version: number): MSQLiteBuilder {
    if (version <= this.versionValue) {
      throw new Error('New version must be bigger than current version. '
        + `current version: ${this.versionValue}, new version: ${version}.`);
    }
    this.versionValue = version;
    const list: string[] = [];
    this.statements = list;
    this.statementsMap.set(version, list);
    return this;
  }

  /** 建表，主键为 int 型 _id（上游 createTable(String)）。 */
  createTable(table: string): MSQLiteBuilder {
    return this.createTableTyped(table, MSQLiteBuilder.COLUMN_ID, SqlType.INT);
  }

  /** 建表（上游 createTable(String, String, Class)）。 */
  createTableTyped(table: string, column: string, javaType: string): MSQLiteBuilder {
    return this.statement(`CREATE TABLE ${table} (${column} ${MSQLiteBuilder.javaTypeToSQLiteType(javaType)} PRIMARY KEY);`);
  }

  /** 删表（上游 dropTable）。 */
  dropTable(table: string): MSQLiteBuilder {
    return this.statement(`DROP TABLE ${table};`);
  }

  /** 加列（上游 insertColumn）。 */
  insertColumn(table: string, column: string, javaType: string): MSQLiteBuilder {
    return this.statement(`ALTER TABLE ${table} ADD COLUMN ${column} ${MSQLiteBuilder.javaTypeToSQLiteType(javaType)};`);
  }

  /** 追加任意语句（上游 statement）。 */
  statement(statement: string): MSQLiteBuilder {
    if (this.versionValue === 0 || this.statements === null) {
      throw new Error('Call version() first!');
    }
    this.statements.push(statement);
    return this;
  }

  /** 构造 helper（上游 build(Context, String, int)）；鸿蒙侧打开是异步的，见 DEVIATIONS D-010。 */
  build(context: common.Context, name: string, version: number): MSQLiteOpenHelper {
    return new MSQLiteOpenHelper(context, name, version, this);
  }

  /** 取 (oldVersion, newVersion] 区间内的全部语句（上游 getStatements）。 */
  getStatements(oldVersion: number, newVersion: number): string[] {
    const result: string[] = [];
    for (let i = oldVersion + 1; i <= newVersion; ++i) {
      const list: string[] | undefined = this.statementsMap.get(i);
      if (list !== undefined) {
        for (const s of list) {
          result.push(s);
        }
      }
    }
    return result;
  }

  /** 声明版本（供 helper 判断升级区间时读取）。 */
  getVersion(): number {
    return this.versionValue;
  }
}
