/*
 * RdbCookieStore 单测（W-022）
 *
 * 覆盖 Lead 指定的判据⑥：「open() 后 getAllCookies() 返回 DB 里的行」，外加三条硬要求：
 *   ① fire-and-forget 必须 catch（写失败只计数 + warn，不影响内存态）
 *   ② "未加载" ≠ "没有 cookie"（isLoaded() 观测面）
 *   ③ 过期/坏行在加载时过滤，并**从表里删掉**（对齐上游 getCookie 判过期即删）
 */

import { RdbCookieStore, CookieDbLike, CookieResultSetLike } from '../../../network/RdbCookieStore';
import { Cookie } from '../../../okhttp/Cookie';
import { CookieTable } from '../../../network/CookieDatabase';

declare const process: { exitCode: number };

let pass = 0;
const fails: string[] = [];
function eq(name: string, got: unknown, want: unknown): void {
  const g = JSON.stringify(got);
  const w = JSON.stringify(want);
  if (g === w) { pass++; } else { fails.push(`${name}: got ${g} want ${w}`); }
}
function ok(name: string, cond: boolean): void {
  if (cond) { pass++; } else { fails.push(name); }
}

/** 一行假数据（列名 → 值，允许模拟 SQL NULL）。 */
interface Row {
  id: number;
  name: string | null;
  value: string | null;
  expiresAt: number | null;
  domain: string | null;
  path: string | null;
  secure: number | null;
  httpOnly: number | null;
  persistent: number | null;
  hostOnly: number | null;
}

class FakeResultSet implements CookieResultSetLike {
  private readonly rows: Row[];
  private _i: number = -1;
  closed: boolean = false;

  constructor(rows: Row[]) {
    this.rows = rows;
  }

  goToNextRow(): boolean {
    this._i++;
    return this._i < this.rows.length;
  }

  getColumnIndex(name: string): number {
    return FakeResultSet.COLUMNS.indexOf(name);
  }

  private rawAt(index: number): unknown {
    const r = this.rows[this._i];
    return [r.id, r.name, r.value, r.expiresAt, r.domain, r.path, r.secure, r.httpOnly,
      r.persistent, r.hostOnly][index];
  }

  isColumnNull(index: number): boolean {
    const v = this.rawAt(index);
    return v === null || v === undefined;
  }

  getString(index: number): string {
    if (this.isColumnNull(index)) {
      throw new Error('14800013: column is null');
    }
    return this.rawAt(index) as string;
  }

  getLong(index: number): number {
    if (this.isColumnNull(index)) {
      throw new Error('14800013: column is null');
    }
    return this.rawAt(index) as number;
  }

  close(): void {
    this.closed = true;
  }

  static readonly COLUMNS: string[] = [
    CookieTable.COLUMN_ID, CookieTable.COLUMN_NAME, CookieTable.COLUMN_VALUE,
    CookieTable.COLUMN_EXPIRES_AT, CookieTable.COLUMN_DOMAIN, CookieTable.COLUMN_PATH,
    CookieTable.COLUMN_SECURE, CookieTable.COLUMN_HTTP_ONLY, CookieTable.COLUMN_PERSISTENT,
    CookieTable.COLUMN_HOST_ONLY
  ];
}

class FakeDb implements CookieDbLike {
  rows: Row[] = [];
  executed: string[] = [];
  events: string[] = [];
  failNext: boolean = false;
  queries: string[] = [];
  delayByOp: (sql: string) => number = () => 0;

  async querySql(sql: string): Promise<CookieResultSetLike> {
    this.queries.push(sql);
    return new FakeResultSet(this.rows);
  }

  async executeSql(sql: string, args: (string | number)[]): Promise<void> {
    this.events.push('start:' + sql.split(' ')[0]);
    const delay: number = this.delayByOp(sql);
    if (delay > 0) {
      await new Promise<void>((r) => setTimeout(r, delay));
    }
    this.executed.push(sql);
    this.events.push('end:' + sql.split(' ')[0]);
    if (this.failNext) {
      this.failNext = false;
      throw new Error('sql failed');
    }
  }
}

const FUTURE: number = Date.now() + 86400000;
const PAST: number = Date.now() - 1000;

function row(id: number, name: string, domain: string, path: string, expiresAt: number,
  persistent: number = 1): Row {
  return {
    id: id, name: name, value: 'v' + id, expiresAt: expiresAt, domain: domain, path: path,
    secure: 1, httpOnly: 0, persistent: persistent, hostOnly: 0
  };
}

async function main(): Promise<void> {
// ---------------------------------------------------------------- ① open() 载入 DB 行
{
  const db = new FakeDb();
  db.rows = [
    row(1, 'ipb_member_id', 'e-hentai.org', '/', FUTURE),
    row(2, 'ipb_pass_hash', 'e-hentai.org', '/', FUTURE),
    row(3, 'igneous', 'exhentai.org', '/', FUTURE)
  ];
  const store = new RdbCookieStore();
  eq('open 之前 isLoaded = false（"未加载" ≠ "没有 cookie"）', store.isLoaded(), false);
  eq('open 之前 getAllCookies 为空', store.getAllCookies().size, 0);

  await store.open(db);
  eq('open 之后 isLoaded = true', store.isLoaded(), true);
  const all = store.getAllCookies();
  eq('载入两个域', all.size, 2);
  eq('e-hentai.org 两条', (all.get('e-hentai.org') as Cookie[]).length, 2);
  eq('exhentai.org 一条', (all.get('exhentai.org') as Cookie[]).length, 1);
  eq('查询的是 OK_HTTP_3_COOKIE 表', db.queries.length, 1);
  ok('SQL 含表名', db.queries[0].indexOf(CookieTable.TABLE_COOKIE) >= 0);
  eq('没有过期行 → 不删表', db.executed.length, 0);
}

// ---------------------------------------------------------------- ③ 过期行：过滤 + 删表
{
  const db = new FakeDb();
  db.rows = [
    row(1, 'good', 'e-hentai.org', '/', FUTURE),
    row(2, 'expired', 'e-hentai.org', '/', PAST),
    row(3, 'notPersistent', 'e-hentai.org', '/', FUTURE, 0)
  ];
  const store = new RdbCookieStore();
  await store.open(db);
  await store.flush();
  const all = store.getAllCookies();
  eq('只剩一条有效', (all.get('e-hentai.org') as Cookie[]).length, 1);
  eq('留下的是 good', (all.get('e-hentai.org') as Cookie[])[0].name(), 'good');
  eq('过期/非持久行被删表（两条 DELETE）', db.executed.length, 2);
  ok('DELETE 带 _id 条件', db.executed[0].indexOf(CookieTable.COLUMN_ID) >= 0);
}

// ---------------------------------------------------------------- ③b SQL NULL 列 & 重复行去重
{
  const db = new FakeDb();
  db.rows = [
    { id: 10, name: null, value: null, expiresAt: FUTURE, domain: 'e-hentai.org', path: '/',
      secure: 0, httpOnly: 0, persistent: 1, hostOnly: 0 },
    { id: 11, name: 'dup', value: 'old', expiresAt: FUTURE, domain: 'e-hentai.org', path: '/',
      secure: 0, httpOnly: 0, persistent: 1, hostOnly: 0 },
    { id: 12, name: 'dup', value: 'new', expiresAt: FUTURE, domain: 'e-hentai.org', path: '/',
      secure: 0, httpOnly: 0, persistent: 1, hostOnly: 0 },
    { id: 13, name: 'nullval', value: null, expiresAt: FUTURE, domain: 'e-hentai.org', path: '/a',
      secure: null, httpOnly: null, persistent: 1, hostOnly: null }
  ];
  const store = new RdbCookieStore();
  await store.open(db);
  await store.flush();
  const list = store.getAllCookies().get('e-hentai.org') as Cookie[];
  eq('NULL 行与重复行清理后剩 2 条', list.length, 2);
  eq('重复行保留最新值', list.find((c) => c.name() === 'dup')?.value(), 'new');
  eq('可空 value 降级空串不抛 14800013', list.find((c) => c.name() === 'nullval')?.value(), '');
  eq('坏行 id=10 与旧重复行 id=11 都被删', db.executed.length, 2);
}

// ---------------------------------------------------------------- ② 未 open 就写：只计数、不崩
{
  const store = new RdbCookieStore();
  const c = new Cookie('a', 'b', FUTURE, 'e-hentai.org', '/', true, false, true, false);
  store.add(c);
  eq('未 open 也能写进内存（拦截器链需要它立即可读）', store.getAllCookies().size, 1);
  eq('未 open → 落库失败计数 +1', store.flushFailures(), 1);
}

// ---------------------------------------------------------------- add / update / remove / clear 的落库
{
  const db = new FakeDb();
  const store = new RdbCookieStore();
  await store.open(db);

  const c1 = new Cookie('a', 'b', FUTURE, 'e-hentai.org', '/', true, false, true, false);
  store.add(c1);
  await store.flush();
  ok('add → INSERT OR REPLACE', db.executed[0].indexOf('INSERT OR REPLACE') >= 0);
  eq('add 后内存可读', store.getAllCookies().size, 1);

  const c2 = new Cookie('a', 'b2', FUTURE, 'e-hentai.org', '/', true, false, true, false);
  store.update(c1, c2);
  await store.flush();
  ok('update → 先 DELETE 再 INSERT',
    db.executed[1].indexOf('DELETE') >= 0 && db.executed[2].indexOf('INSERT') >= 0);
  eq('update 后值变了', (store.getAllCookies().get('e-hentai.org') as Cookie[])[0].value(), 'b2');

  store.remove(c2);
  await store.flush();
  ok('remove → DELETE', db.executed[3].indexOf('DELETE') >= 0);
  eq('remove 后内存空', store.getAllCookies().size, 0);

  store.clear();
  await store.flush();
  ok('clear → DELETE 全表', db.executed[4].indexOf('DELETE') >= 0 &&
    db.executed[4].indexOf('WHERE') < 0);
  store.close();
  eq('close 后可观测', store.isClosed(), true);
}

// ---------------------------------------------------------------- writeChain 严格串行：慢 DELETE 不被快 INSERT 超车
{
  const db = new FakeDb();
  db.delayByOp = (sql: string): number => sql.indexOf('DELETE') >= 0 ? 15 : 1;
  const store = new RdbCookieStore();
  await store.open(db);
  const c1 = new Cookie('k', 'v1', FUTURE, 'e-hentai.org', '/', true, false, true, false);
  const c2 = new Cookie('k', 'v2', FUTURE, 'e-hentai.org', '/', true, false, true, false);
  store.update(c1, c2);
  await store.flush();
  eq('writeChain 保证 DELETE 完成后才开始 INSERT', db.events,
    ['start:DELETE', 'end:DELETE', 'start:INSERT', 'end:INSERT']);
}

// ---------------------------------------------------------------- 非持久化 cookie 不入库
{
  const db = new FakeDb();
  const store = new RdbCookieStore();
  await store.open(db);
  const sessionOnly = new Cookie('s', 'v', 0, 'e-hentai.org', '/', false, true, false, true);
  store.add(sessionOnly);
  await store.flush();
  eq('非持久化 → 不写内存', store.getAllCookies().size, 0);
  eq('非持久化 → 不落库', db.executed.length, 0);
}

// ---------------------------------------------------------------- ① fire-and-forget 失败被 catch
{
  const db = new FakeDb();
  const store = new RdbCookieStore();
  await store.open(db);
  db.failNext = true;
  const c = new Cookie('a', 'b', FUTURE, 'e-hentai.org', '/', true, false, true, false);
  store.add(c);
  await store.flush();
  eq('落库失败被 catch 并计数', store.flushFailures(), 1);
  eq('内存态不受影响（写失败≠读不到）', store.getAllCookies().size, 1);
}

}

main().then((): void => { printResult(); }).catch((e: Error): void => {
  console.log('harness error: ' + e.message);
  process.exitCode = 1;
});

function printResult(): void {
  console.log(`\n=== 结果：${pass} passed, ${fails.length} failed ===`);
  if (fails.length > 0) {
    for (const f of fails) {
      console.log('  FAIL ' + f);
    }
    throw new Error('RdbCookieStore 断言失败：' + fails.length);
  }
}
