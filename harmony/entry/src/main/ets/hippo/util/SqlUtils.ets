/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0501   上游: com/hippo/util/SqlUtils.java（106 行）
 * 目标   : harmony/entry/src/main/ets/hippo/util/SqlUtils.ets
 *
 * 平台差异：
 *  1. `SQLiteDatabase` → `relationalStore.RdbStore`（@ohos.data.relationalStore）。
 *     `db.execSQL(sql)` → `store.executeSql(sql)`；`db.rawQuery(sql, null)` → `store.querySql(sql)`。
 *  2. `Cursor` → `relationalStore.ResultSet`。取值方法名对应关系：
 *       `getColumnIndex`  → `getColumnIndex(name)`
 *       `getInt`          → `getLong(idx)`（**ResultSet 只有 getLong，没有 getInt** → `| 0` 截成 int32）
 *       `getLong`         → `getLong(idx)`
 *       `getFloat`        → `getDouble(idx)`
 *       `getString`       → `getString(idx)`
 *  3. **`exeSQLSafely` 的空 catch 是有意的**（上游注释 `// Ignore`）：用于"列可能已存在"这类
 *     可忽略错误。按陷阱 82（日志位置判据），这里是**低频迁移路径**且"失败即已达成目的"，
 *     但仍按 D-0xx 口径加 `hilog.debug` —— 不加 warn/error（不是异常），只为事后可查。
 *  4. `sqlEscapeString` 逐字符处理 `'` → `''`（上游是手写循环，不是 `String.replace`）。
 *     照搬循环：`replace("'", "''")` 结果相同，但上游**只处理单引号**，其它字符原样保留。
 */

import relationalStore from '@ohos.data.relationalStore';
import hilog from '@ohos.hilog';

export class SqlUtils {

  /** 对应上游 `exeSQLSafely`：失败吞掉（用于"列/表可能已存在"） */
  static async exeSQLSafely(db: relationalStore.RdbStore, sql: string): Promise<void> {
    try {
      await db.executeSql(sql);
    } catch (e) {
      // Ignore —— 上游语义；仅 debug 级留痕，不影响流程
      hilog.debug(0x0001, 'SqlUtils', 'exeSQLSafely ignored: %{public}s', `${(e as Error).message}`);
    }
  }

  /** 对应上游 `dropTable` */
  static async dropTable(db: relationalStore.RdbStore, tableName: string): Promise<void> {
    await SqlUtils.exeSQLSafely(db, 'DROP TABLE IF EXISTS ' + tableName);
  }

  /**
   * 对应上游 `dropAllTable`：列出 `sqlite_master` 里所有表，**排除 `android_metadata` 与
   * `sqlite_sequence`**（前者是 Android 专有，后者是自增序列表）。
   * 鸿蒙的 `relationalStore` 不建 `android_metadata`，但**保留该排除条件**（照搬，无害且更安全）。
   */
  static async dropAllTable(db: relationalStore.RdbStore): Promise<void> {
    const tables: string[] = [];
    const rs: relationalStore.ResultSet = await db.querySql("SELECT * FROM sqlite_master WHERE type='table';");
    try {
      let has: boolean = rs.goToFirstRow();
      while (has) {
        // 上游取 `cursor.getString(1)` —— 即第二列（name）
        const tableName: string = rs.getString(1);
        if (tableName !== 'android_metadata' && tableName !== 'sqlite_sequence') {
          tables.push(tableName);
        }
        has = rs.goToNextRow();
      }
    } finally {
      rs.close();
    }
    for (let i = 0; i < tables.length; i++) {
      await SqlUtils.dropTable(db, tables[i]);
    }
  }

  /** 对应上游 `sqlEscapeString`：`'` → `''`，其余原样 */
  static sqlEscapeString(value: string): string {
    let sb: string = '';
    const length: number = value.length;
    for (let i = 0; i < length; i++) {
      const c: string = value.charAt(i);
      if (c === "'") {
        sb += "'";
      }
      sb += c;
    }
    return sb;
  }

  /** 对应上游 `getBoolean`：列不存在或取值异常 → `defValue` */
  static getBoolean(cursor: relationalStore.ResultSet, column: string, defValue: boolean): boolean {
    try {
      const index: number = cursor.getColumnIndex(column);
      if (index !== -1) {
        return cursor.getLong(index) !== 0;
      }
    } catch (e) {
      // Ignore
    }
    return defValue;
  }

  /** 对应上游 `getInt`（ResultSet 只有 getLong → 截 int32） */
  static getInt(cursor: relationalStore.ResultSet, column: string, defValue: number): number {
    try {
      const index: number = cursor.getColumnIndex(column);
      if (index !== -1) {
        return cursor.getLong(index) | 0;
      }
    } catch (e) {
      // Ignore
    }
    return defValue;
  }

  /** 对应上游 `getLong`（ArkTS 无 long → number；安全整数范围内精确） */
  static getLong(cursor: relationalStore.ResultSet, column: string, defValue: number): number {
    try {
      const index: number = cursor.getColumnIndex(column);
      if (index !== -1) {
        return cursor.getLong(index);
      }
    } catch (e) {
      // Ignore
    }
    return defValue;
  }

  /** 对应上游 `getFloat`（`getDouble` → number） */
  static getFloat(cursor: relationalStore.ResultSet, column: string, defValue: number): number {
    try {
      const index: number = cursor.getColumnIndex(column);
      if (index !== -1) {
        return cursor.getDouble(index);
      }
    } catch (e) {
      // Ignore
    }
    return defValue;
  }

  /** 对应上游 `getString`；**列存在但值为 NULL 时 ResultSet 会返回 ''**，与 Cursor.getString 一致 */
  static getString(cursor: relationalStore.ResultSet, column: string, defValue: string | null): string | null {
    try {
      const index: number = cursor.getColumnIndex(column);
      if (index !== -1) {
        return cursor.getString(index);
      }
    } catch (e) {
      // Ignore
    }
    return defValue;
  }
}