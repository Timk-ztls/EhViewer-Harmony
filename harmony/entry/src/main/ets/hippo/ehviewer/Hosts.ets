/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0162   上游: com/hippo/ehviewer/Hosts.java（326 行）
 * 目标   : harmony/entry/src/main/ets/hippo/ehviewer/Hosts.ets
 *
 * 上游是"自定义 DNS 映射表"：库里存 `HOST → IP`，`EhHosts`（okhttp Dns 实现）查它。
 * 本文件分两块：
 *  A. **纯逻辑**（本提交的重心，最好测）：`isValidHost` / `isValidIp` / `parseV4` / `parseV6` /
 *     `toInetAddress` —— 两个 IP 解析器是从 `org.xbill.DNS.Address` 抄来的**严格解析器**，
 *     规则密集（见断言），换成 `inet_aton` 风格的宽松解析会接受 `1.2.3`、`0x7f.0.0.1` 这类非法值。
 *  B. **CRUD**：`get/getList/contains/put/delete/getAll` —— 表结构 `HOSTS(HOST, IP)` 与上游一致，
 *     通过注入的 `HostsStoreLike` 访问（鸿蒙侧用 `relationalStore` 实现，VERSION_1 建表逻辑照上游）。
 *
 * 平台差异：
 *  1. `InetAddress` → `Uint8Array`（4 或 16 字节）。ArkTS 有 `@ohos.net.connection` 的
 *     `getAddressesByName`，但**没有 `InetAddress.getByAddress(host, bytes)`** —— 所以本文件
 *     返回"字节 + 宿主名校验结果"，由调用方（DNS 层）自己组装。
 *  2. `SQLiteOpenHelper/MSQLiteBuilder` → `HostsStoreLike` 注入（建表 SQL 逐字保留，供实现者参考）。
 *  3. `android.util.Pair` → `HostIpPair`。
 *  4. `Character.digit(c, 16)` → 手写十六进制字符判定（`parseV6` 用）。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';

/** 上游 `Pair<String, String>`（host, ip） */
export class HostIpPair {
  host: string;
  ip: string;

  constructor(host: string, ip: string) {
    this.host = host;
    this.ip = ip;
  }
}

/** 表结构与 CRUD 的注入契约（对应上游 `SQLiteDatabase` 的这几条语句） */
export interface HostsStoreLike {
  /** `SELECT * FROM HOSTS WHERE HOST = ?` —— 返回所有匹配行的 IP */
  queryIps(host: string): Promise<string[]>;

  /** `SELECT * FROM HOSTS` —— 返回 (host, ip) */
  queryAll(): Promise<HostIpPair[]>;

  /** 是否已存在该 host（上游 `contains`） */
  contains(host: string): Promise<boolean>;

  /** `UPDATE ... WHERE HOST = ?` / `INSERT INTO HOSTS` */
  upsert(host: string, ip: string): Promise<void>;

  /** `DELETE FROM HOSTS WHERE HOST = ?` */
  deleteByHost(host: string): Promise<void>;
}

/** RDB 结果集最小执行面（与 `relationalStore.ResultSet` 方法一致，便于测试替身） */
export interface HostsResultSetLike {
  goToNextRow(): boolean;
  getColumnIndex(name: string): number;
  isColumnNull(index: number): boolean;
  getString(index: number): string;
  close(): void;
}

/** RDB 存储最小执行面（与 `relationalStore.RdbStore` 方法一致） */
export interface HostsDbLike {
  querySql(sql: string, bindArgs?: Array<string | number>): Promise<HostsResultSetLike>;
  executeSql(sql: string, args?: Array<string | number>): Promise<void>;
}

/**
 * `HostsStoreLike` 的 RDB 持久实现（表 `HOSTS(HOST, IP)`）。
 *
 * 特点：
 *  1. 幂等建表（`ensureTable()` / 懒执行去重），首次读写自动确保表存在。
 *  2. 读取时对 `HOST`/`IP` 列执行 `isColumnNull()` 判空，跳过 NULL 脏行。
 *  3. 写操作（`upsert`/`deleteByHost`）串行排队执行，防止并发 `contains` + `INSERT` 竞态产生重复行。
 */
export class RdbHostsStore implements HostsStoreLike {
  private readonly db: HostsDbLike;
  private tableEnsured: boolean = false;
  private ensurePromise: Promise<void> | null = null;
  private writeChain: Promise<void> = Promise.resolve();

  constructor(db: HostsDbLike) {
    this.db = db;
  }

  /** 幂等建表：`CREATE TABLE IF NOT EXISTS HOSTS (HOST TEXT, IP TEXT)` */
  async ensureTable(): Promise<void> {
    if (this.tableEnsured) {
      return;
    }
    if (this.ensurePromise !== null) {
      return this.ensurePromise;
    }
    const task: Promise<void> = this.db.executeSql(Hosts.buildCreateTableSql(), []).then(() => {
      this.tableEnsured = true;
    });
    this.ensurePromise = task;
    try {
      await task;
    } finally {
      if (this.ensurePromise === task) {
        this.ensurePromise = null;
      }
    }
  }

  private runSerializedWrite(op: () => Promise<void>): Promise<void> {
    const next: Promise<void> = this.writeChain.then(op, op);
    this.writeChain = next.catch((e: Object): void => {
      // Keep write chain alive after an individual failure; caller receives rejection via `next`.
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.debug(0x0000, 'Hosts', 'serialized write failed (propagated to caller): %{public}s', msg);
    });
    return next;
  }

  private async containsInternal(host: string): Promise<boolean> {
    const rs: HostsResultSetLike = await this.db.querySql(
      `SELECT * FROM ${Hosts.TABLE_HOSTS} WHERE ${Hosts.COLUMN_HOST} = ?;`, [host]);
    try {
      return rs.goToNextRow();
    } finally {
      rs.close();
    }
  }

  async queryIps(host: string): Promise<string[]> {
    await this.ensureTable();
    const rs: HostsResultSetLike = await this.db.querySql(
      `SELECT * FROM ${Hosts.TABLE_HOSTS} WHERE ${Hosts.COLUMN_HOST} = ?;`, [host]);
    const ips: string[] = [];
    try {
      const iIp: number = rs.getColumnIndex(Hosts.COLUMN_IP);
      if (iIp < 0) {
        return ips;
      }
      while (rs.goToNextRow()) {
        if (rs.isColumnNull(iIp)) {
          continue;
        }
        const ip: string = rs.getString(iIp);
        if (ip !== null && ip !== undefined) {
          ips.push(ip);
        }
      }
      return ips;
    } finally {
      rs.close();
    }
  }

  async queryAll(): Promise<HostIpPair[]> {
    await this.ensureTable();
    const rs: HostsResultSetLike = await this.db.querySql(`SELECT * FROM ${Hosts.TABLE_HOSTS};`, []);
    const rows: HostIpPair[] = [];
    try {
      const iHost: number = rs.getColumnIndex(Hosts.COLUMN_HOST);
      const iIp: number = rs.getColumnIndex(Hosts.COLUMN_IP);
      if (iHost < 0 || iIp < 0) {
        return rows;
      }
      while (rs.goToNextRow()) {
        if (rs.isColumnNull(iHost) || rs.isColumnNull(iIp)) {
          continue;
        }
        const host: string = rs.getString(iHost);
        const ip: string = rs.getString(iIp);
        if (host !== null && host !== undefined && ip !== null && ip !== undefined) {
          rows.push(new HostIpPair(host, ip));
        }
      }
      return rows;
    } finally {
      rs.close();
    }
  }

  async contains(host: string): Promise<boolean> {
    await this.ensureTable();
    return this.containsInternal(host);
  }

  async upsert(host: string, ip: string): Promise<void> {
    await this.runSerializedWrite(async () => {
      await this.ensureTable();
      if (await this.containsInternal(host)) {
        await this.db.executeSql(
          `UPDATE ${Hosts.TABLE_HOSTS} SET ${Hosts.COLUMN_IP} = ? WHERE ${Hosts.COLUMN_HOST} = ?`,
          [ip, host]);
      } else {
        await this.db.executeSql(
          `INSERT INTO ${Hosts.TABLE_HOSTS} (${Hosts.COLUMN_HOST}, ${Hosts.COLUMN_IP}) VALUES (?, ?)`,
          [host, ip]);
      }
    });
  }

  async deleteByHost(host: string): Promise<void> {
    await this.runSerializedWrite(async () => {
      await this.ensureTable();
      await this.db.executeSql(
        `DELETE FROM ${Hosts.TABLE_HOSTS} WHERE ${Hosts.COLUMN_HOST} = ?`, [host]);
    });
  }
}

export class Hosts {

  /** 上游 `TABLE_HOSTS` / `COLUMN_HOST` / `COLUMN_IP` / `VERSION_1` */
  static readonly TABLE_HOSTS: string = 'HOSTS';
  static readonly COLUMN_HOST: string = 'HOST';
  static readonly COLUMN_IP: string = 'IP';
  static readonly VERSION_1: number = 1;

  /** 上游建表语句（供 HostsStoreLike 实现者参考，逐字保留字段名） */
  static buildCreateTableSql(): string {
    return 'CREATE TABLE IF NOT EXISTS ' + Hosts.TABLE_HOSTS + ' ('
      + Hosts.COLUMN_HOST + ' TEXT, ' + Hosts.COLUMN_IP + ' TEXT)';
  }

  private store: HostsStoreLike;

  constructor(store: HostsStoreLike) {
    this.store = store;
  }

  /** 对应上游 `get(host)`：无效 host 或未配置 → null；否则返回首个可解析的 IP 字节 */
  async get(host: string): Promise<Uint8Array | null> {
    if (!Hosts.isValidHost(host)) {
      return null;
    }
    const ips: string[] = await this.store.queryIps(host);
    if (ips.length === 0) {
      return null;
    }
    return Hosts.toInetAddress(host, ips[0]);
  }

  /** 对应上游 `getList(host)`：**跳过无法解析的行**，返回可解析的全部地址 */
  async getList(host: string): Promise<Uint8Array[] | null> {
    if (!Hosts.isValidHost(host)) {
      return null;
    }
    const ips: string[] = await this.store.queryIps(host);
    const list: Uint8Array[] = [];
    for (let i = 0; i < ips.length; i++) {
      const addr: Uint8Array | null = Hosts.toInetAddress(host, ips[i]);
      if (addr !== null) {
        list.push(addr);
      }
    }
    return list;
  }

  /** 对应上游 `put(host, ip)`：**任一侧非法 → 不改库、返回 false** */
  async put(host: string, ip: string): Promise<boolean> {
    if (!Hosts.isValidHost(host) || !Hosts.isValidIp(ip)) {
      return false;
    }
    await this.store.upsert(host, ip);
    return true;
  }

  /** 对应上游 `delete(host)` */
  async delete(host: string): Promise<void> {
    await this.store.deleteByHost(host);
  }

  /** 对应上游 `getAll()`：**跳过 IP 无法解析的行**（上游 `continue`） */
  async getAll(): Promise<HostIpPair[]> {
    const rows: HostIpPair[] = await this.store.queryAll();
    const result: HostIpPair[] = [];
    for (let i = 0; i < rows.length; i++) {
      const r: HostIpPair = rows[i];
      const addr: Uint8Array | null = Hosts.toInetAddress(r.host, r.ip);
      if (addr === null) {
        continue;
      }
      result.push(r);
    }
    return result;
  }

  /**
   * 对应上游 `toInetAddress(host, ip)`：host 非法 / ip 为 null / 两个解析器都失败 → null。
   * **返回字节数组**（4 或 16），对应 `InetAddress.getByAddress(host, bytes)` 的 bytes 部分。
   */
  static toInetAddress(host: string, ip: string | null): Uint8Array | null {
    if (!Hosts.isValidHost(host)) {
      return null;
    }
    if (ip === null) {
      return null;
    }
    let bytes: Uint8Array | null = Hosts.parseV4(ip);
    if (bytes === null) {
      bytes = Hosts.parseV6(ip);
    }
    return bytes;
  }

  /**
   * 对应上游 `isValidHost(host)`：长度 ≤ 253；每段 1~63；**只允许小写字母、数字、`-`、`.`**。
   * ⚠️ 上游**不接受大写**（判断是 `ch<'a'||ch>'z'` 且 `ch<'0'||ch>'9'`）—— 照搬，
   * 断言 `Hosts.isValidHost('EXAMPLE.COM') === false`。要支持大写得先转小写（改动上游行为）。
   */
  static isValidHost(host: string | null): boolean {
    if (host === null) {
      return false;
    }
    if (host.length > 253) {
      return false;
    }
    let labelLength: number = 0;
    for (let i = 0; i < host.length; i++) {
      const ch: string = host.charAt(i);
      if (ch === '.') {
        if (labelLength < 1 || labelLength > 63) {
          return false;
        }
        labelLength = 0;
      } else {
        labelLength++;
      }
      const isLower: boolean = ch >= 'a' && ch <= 'z';
      const isDigit: boolean = ch >= '0' && ch <= '9';
      if (!isLower && !isDigit && ch !== '-' && ch !== '.') {
        return false;
      }
    }
    if (labelLength < 1 || labelLength > 63) {
      return false;
    }
    return true;
  }

  /** 对应上游 `isValidIp(ip)` */
  static isValidIp(ip: string | null): boolean {
    return ip !== null && (Hosts.parseV4(ip) !== null || Hosts.parseV6(ip) !== null);
  }

  /**
   * 对应上游 `parseV4`（抄自 `org.xbill.DNS.Address.parseV4`）：
   * 每段 ≤3 位、**不允许前导 0**（除非就是 0）、值 ≤255、**必须 4 段**、不允许连续点。
   */
  static parseV4(s: string): Uint8Array | null {
    const values: Uint8Array = new Uint8Array(4);
    let currentOctet: number = 0;
    let currentValue: number = 0;
    let numDigits: number = 0;
    const length: number = s.length;

    for (let i = 0; i < length; i++) {
      const c: string = s.charAt(i);
      if (c >= '0' && c <= '9') {
        // Can't have more than 3 digits per octet.
        if (numDigits === 3) {
          return null;
        }
        // Octets shouldn't start with 0, unless they are 0.
        if (numDigits > 0 && currentValue === 0) {
          return null;
        }
        numDigits++;
        currentValue = currentValue * 10 + (c.charCodeAt(0) - 48);
        // 255 is the maximum value for an octet.
        if (currentValue > 255) {
          return null;
        }
      } else if (c === '.') {
        // Can't have more than 3 dots.
        if (currentOctet === 3) {
          return null;
        }
        // Two consecutive dots are bad.
        if (numDigits === 0) {
          return null;
        }
        values[currentOctet++] = currentValue & 0xFF;
        currentValue = 0;
        numDigits = 0;
      } else {
        return null;
      }
    }
    // Must have 4 octets.
    if (currentOctet !== 3) {
      return null;
    }
    // The fourth octet can't be empty.
    if (numDigits === 0) {
      return null;
    }
    values[currentOctet] = currentValue & 0xFF;
    return values;
  }

  /**
   * 对应上游 `parseV6`（抄自 `org.xbill.DNS.Address.parseV6`）：
   * 支持 `::` 压缩、**末段可内嵌 IPv4**（此时前面最多 6 段）。
   */
  static parseV6(s: string): Uint8Array | null {
    let range: number = -1;
    const data: Uint8Array = new Uint8Array(16);

    const tokens: string[] = s.split(':');
    let first: number = 0;
    let last: number = tokens.length - 1;

    if (tokens[0].length === 0) {
      // :: 开头合法；单个 : 开头非法
      if (last - first > 0 && tokens[1].length === 0) {
        first++;
      } else {
        return null;
      }
    }
    if (tokens[last].length === 0) {
      // :: 结尾合法；单个 : 结尾非法
      if (last - first > 0 && tokens[last - 1].length === 0) {
        last--;
      } else {
        return null;
      }
    }
    if (last - first + 1 > 8) {
      return null;
    }

    let j: number = 0;
    for (let i = first; i <= last; i++) {
      if (tokens[i].length === 0) {
        if (range >= 0) {
          return null; // 两个 `::` 非法
        }
        range = j;
        continue;
      }
      if (tokens[i].indexOf('.') >= 0) {
        // An IPv4 address must be the last component
        if (i < last) {
          return null;
        }
        // There can't have been more than 6 components.
        if (i > 6) {
          return null;
        }
        const v4addr: Uint8Array | null = Hosts.parseV4(tokens[i]);
        if (v4addr === null) {
          return null;
        }
        for (let k = 0; k < 4; k++) {
          data[j++] = v4addr[k];
        }
        break;
      }
      // 十六进制校验（上游 Character.digit(c,16) < 0）
      for (let k = 0; k < tokens[i].length; k++) {
        if (!Hosts.isHexDigit(tokens[i].charAt(k))) {
          return null;
        }
      }
      const x: number = parseInt(tokens[i], 16);
      if (isNaN(x) || x > 0xFFFF || x < 0) {
        return null;
      }
      data[j++] = (x >>> 8) & 0xFF;
      data[j++] = x & 0xFF;
    }

    if (j < 16 && range < 0) {
      return null;
    }
    if (range >= 0) {
      const empty: number = 16 - j;
      // 等价 System.arraycopy(data, range, data, range+empty, j-range) —— 先搬后清零
      for (let k = j - 1; k >= range; k--) {
        data[k + empty] = data[k];
      }
      for (let i = range; i < range + empty; i++) {
        data[i] = 0;
      }
    }
    return data;
  }

  /** `Character.digit(c, 16) >= 0` */
  private static isHexDigit(c: string): boolean {
    return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
  }
}