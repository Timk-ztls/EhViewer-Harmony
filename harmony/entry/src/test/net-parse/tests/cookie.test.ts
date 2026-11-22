// CookieRepository / CookieSet / CookieDatabase 的 P4 验收测试（登录态持久化）
//
// 「重启」如何模拟：`InMemoryCookieStore` 是**独立的行存储实例**，
// 用同一个 store 新建第二个 `CookieRepository` 就等价于「进程重启后数据库文件还在」——
// 不需要真机，也不需要 relationalStore。
//
// 覆盖：
//   1) 持久化 cookie 写库 → 新 repository 仍能取到（P4 核心）
//   2) 非持久化 cookie 不入库 → 重启后消失
//   3) 过期 cookie → 取值时被剔除并出库
//   4) 同名同域同路径的覆盖：add 返回旧值；库里是 update 而不是两行
//   5) 「新不持久 + 旧持久」→ 库里旧行被删（addCookie 的第三分支）
//   6) getCookies 排序：path 长的在前（RFC 6265 §5.4）
//   7) domainMatch：example.com / www.example.com / IP 不参与后缀匹配
//   8) getCookieHeader 拼接格式
//   9) clear / close

import { CookieRepository } from '../../../network/CookieRepository';
import { CookieSet } from '../../../network/CookieSet';
import { InMemoryCookieStore, CookieTable } from '../../../network/CookieDatabase';
import { Cookie, CookieBuilder } from '../../../okhttp/Cookie';
import { HttpUrl } from '../../../okhttp/HttpUrl';

let pass = 0;
let fail = 0;
const failures: string[] = [];

function eq(name: string, actual: unknown, expected: unknown): void {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a === e) {
    pass++;
  } else {
    fail++;
    failures.push(`${name}\n    actual  = ${a}\n    expected= ${e}`);
  }
}

function ok(name: string, cond: boolean): void {
  if (cond) {
    pass++;
  } else {
    fail++;
    failures.push(name);
  }
}

const HOUR: number = 3600 * 1000;

function persist(name: string, value: string, domain: string, path: string, expiresInMs: number): Cookie {
  return new CookieBuilder()
    .name(name).value(value).domain(domain).path(path)
    .expiresAt(Date.now() + expiresInMs)
    .build();
}

function session(name: string, value: string, domain: string, path: string): Cookie {
  // 不设 expiresAt → CookieBuilder 的 persistent 保持 false（会话 cookie）
  return new CookieBuilder()
    .name(name).value(value).domain(domain).path(path)
    .build();
}

const URL_E: HttpUrl = HttpUrl.parse('https://e-hentai.org/') as HttpUrl;
const URL_WWW: HttpUrl = HttpUrl.parse('https://www.e-hentai.org/') as HttpUrl;
const URL_IP: HttpUrl = HttpUrl.parse('https://127.0.0.1/') as HttpUrl;

// ---------- 1. P4：重启后 cookie 还在 ----------
{
  const store = new InMemoryCookieStore();
  const repo1 = new CookieRepository(store);
  repo1.addCookie(persist('ipb_member_id', '12345', 'e-hentai.org', '/', 24 * HOUR));
  repo1.addCookie(persist('ipb_pass_hash', 'abc', 'e-hentai.org', '/', 24 * HOUR));

  ok('P4：持久化 cookie 已入库（2 行）', store.rowCount() === 2);

  // 模拟重启：同一个 store，新的 repository 实例
  const repo2 = new CookieRepository(store);
  const cookies = repo2.getCookies(URL_E);
  eq('P4：重启后取到 2 个 cookie', cookies.length, 2);
  eq('P4：重启后 ipb_member_id 仍在', repo2.getCookieHeader(URL_E),
    'ipb_member_id=12345; ipb_pass_hash=abc');
  ok('P4：contains 能查到', repo2.contains(URL_E, 'ipb_member_id'));
}

// ---------- 2. 非持久化不入库 ----------
{
  const store = new InMemoryCookieStore();
  const repo = new CookieRepository(store);
  // persistent 由 Cookie 的「expiresAt 是否有限」决定：这里造一个 hostOnly 的会话 cookie
  const sessionCookie = session('sessionid', 'xyz', 'e-hentai.org', '/');
  repo.addCookie(sessionCookie);
  const repo2 = new CookieRepository(store);
  eq('非持久化 cookie 重启后消失', repo2.getCookies(URL_E).length, 0);
}

// ---------- 3. 过期剔除 ----------
{
  const store = new InMemoryCookieStore();
  const repo = new CookieRepository(store);
  repo.addCookie(persist('old', 'v', 'e-hentai.org', '/', -1000)); // 已过期
  eq('过期 cookie 取不到', repo.getCookies(URL_E).length, 0);
  eq('过期持久化 cookie 出库', store.rowCount(), 0);
}

// ---------- 4. 同名覆盖走 update ----------
{
  const store = new InMemoryCookieStore();
  const repo = new CookieRepository(store);
  repo.addCookie(persist('k', 'v1', 'e-hentai.org', '/', HOUR));
  repo.addCookie(persist('k', 'v2', 'e-hentai.org', '/', HOUR));
  eq('覆盖后库里仍是 1 行', store.rowCount(), 1);
  eq('覆盖后取到新值', repo.getCookieHeader(URL_E), 'k=v2');

  // CookieSet.add 的返回值语义
  const set = new CookieSet();
  const c1 = persist('a', '1', 'd', '/', HOUR);
  const c2 = persist('a', '2', 'd', '/', HOUR);
  eq('CookieSet.add 首次返回 null', set.add(c1), null);
  ok('CookieSet.add 第二次返回旧 cookie', set.add(c2) === c1);
  ok('CookieSet.remove 返回被删的', set.remove(c2) === c2);
  eq('CookieSet.remove 不存在返回 null', set.remove(c2), null);
}

// ---------- 5. 新的不持久 + 旧的持久 → 库里删旧行 ----------
{
  const store = new InMemoryCookieStore();
  const repo = new CookieRepository(store);
  repo.addCookie(persist('k', 'persisted', 'e-hentai.org', '/', HOUR));
  eq('先有 1 行', store.rowCount(), 1);
  // 用「已过期」的 cookie 覆盖同名 → 走 remove 分支，且旧的是持久化 → 出库
  repo.addCookie(persist('k', 'expired', 'e-hentai.org', '/', -1000));
  eq('旧持久行被删', store.rowCount(), 0);
}

// ---------- 6. 排序：path 长的在前 ----------
{
  const store = new InMemoryCookieStore();
  const repo = new CookieRepository(store);
  repo.addCookie(persist('a', 'root', 'e-hentai.org', '/', HOUR));
  repo.addCookie(persist('b', 'deep', 'e-hentai.org', '/g/', HOUR));
  repo.addCookie(persist('c', 'deeper', 'e-hentai.org', '/g/abc/', HOUR));
  const order = repo.getCookies(HttpUrl.parse('https://e-hentai.org/g/abc/1') as HttpUrl).map((c) => c.name());
  eq('getCookies 按 path 降序', order, ['c', 'b', 'a']);
}

// ---------- 7. domainMatch ----------
{
  ok('domainMatch 完全相等', CookieRepository.domainMatch(URL_E, 'e-hentai.org'));
  ok('domainMatch 后缀匹配', CookieRepository.domainMatch(URL_WWW, 'e-hentai.org'));
  ok('domainMatch 不同域不匹配', !CookieRepository.domainMatch(URL_WWW, 'exhentai.org'));
  // IP 地址不参与后缀匹配（上游 verifyAsIpAddress 用整串匹配，127.0.0.1 是 IP）
  ok('domainMatch IP 不做后缀匹配',
    !CookieRepository.domainMatch(HttpUrl.parse('https://127.0.0.1/') as HttpUrl, '0.0.1'));
  ok('domainMatch 含非数字的「像 IP」串仍按主机名处理',
    CookieRepository.domainMatch(HttpUrl.parse('https://127.0.0.1.x/') as HttpUrl, '0.0.1.x'));
  ok('domainMatch 尾串但无点分隔不匹配', !CookieRepository.domainMatch(URL_WWW, 'hentai.org.evil'));
}

// ---------- 8. 头拼接 ----------
{
  const store = new InMemoryCookieStore();
  const repo = new CookieRepository(store);
  repo.addCookie(persist('a', '1', 'e-hentai.org', '/zzz/', HOUR));
  repo.addCookie(persist('b', '2', 'e-hentai.org', '/', HOUR));
  eq('cookie 头顺序（path 长的先）',
    repo.getCookieHeader(HttpUrl.parse('https://e-hentai.org/zzz/1') as HttpUrl), 'a=1; b=2');
}

// ---------- 9. clear / close / 表结构 ----------
{
  const store = new InMemoryCookieStore();
  const repo = new CookieRepository(store);
  repo.addCookie(persist('k', 'v', 'e-hentai.org', '/', HOUR));
  repo.clear();
  eq('clear 后取不到', repo.getCookies(URL_E).length, 0);
  eq('clear 后库为空', store.rowCount(), 0);

  repo.close();
  ok('close 传递给 backend', store.isClosed());

  const ddl = CookieTable.createTableSql();
  ok('建表 SQL 含表名', ddl.indexOf('OK_HTTP_3_COOKIE') >= 0);
  ok('建表 SQL 含 10 列',
    ddl.indexOf(CookieTable.COLUMN_ID) >= 0 && ddl.indexOf(CookieTable.COLUMN_HOST_ONLY) >= 0 &&
    (ddl.match(/,/g) || []).length === 12);
  ok('建表 SQL 含 UNIQUE (NAME, DOMAIN, PATH)',
    ddl.indexOf(`UNIQUE (${CookieTable.COLUMN_NAME}, ${CookieTable.COLUMN_DOMAIN}, ${CookieTable.COLUMN_PATH})`) >= 0);
  ok('坏行判定：domain 为 null → 无效',
    !CookieTable.isValidRow('n', null, '/', true, Date.now() + HOUR, Date.now()));
  ok('坏行判定：name 为空 → 无效',
    !CookieTable.isValidRow('', 'd', '/', true, Date.now() + HOUR, Date.now()));
  ok('坏行判定：domain 为空 → 无效',
    !CookieTable.isValidRow('n', '', '/', true, Date.now() + HOUR, Date.now()));
  ok('坏行判定：非持久化 → 无效',
    !CookieTable.isValidRow('n', 'd', '/', false, Date.now() + HOUR, Date.now()));
  ok('好行判定：有效',
    CookieTable.isValidRow('n', 'd', '/', true, Date.now() + HOUR, Date.now()));
}

// ---------- 汇总 ----------
console.log(`\n=== 结果：${pass} passed, ${fail} failed ===`);
if (fail > 0) {
  for (const f of failures) {
    console.log('  FAIL ' + f);
  }
  throw new Error('cookie 断言失败：' + fail);
}
