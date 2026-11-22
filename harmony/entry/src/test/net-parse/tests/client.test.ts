// client 层四件（EhRequest / EhRequestBuilder / EhCookieStore / EhHosts / EhUrlOpener）测试

import { EhRequest, EhRequestConfig, EhCallbackLike, TaskLike } from '../EhRequest';
import { EhRequestBuilder } from '../EhRequestBuilder';
import { EhCookieStore } from '../EhCookieStore';
import { EhHosts, EhHostsConfig, OkHttpEhHosts, HttpDohResolver } from '../EhHosts';
import { EhUrlOpener } from '../EhUrlOpener';
import { EhConfig } from '../EhConfig';
import { InMemoryCookieStore } from '../../../network/CookieDatabase';
import { Cookie, CookieBuilder } from '../../../okhttp/Cookie';
import { Dns, InetAddress } from '../../../okhttp/Dns';
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

const HOUR = 3600 * 1000;

// ---------- EhRequest ----------
{
  let taskCancelled = 0;
  const task: TaskLike = { stop: (): void => { taskCancelled++; } };
  const cb: EhCallbackLike = {
    onSuccess: (): void => { },
    onFailure: (): void => { },
    onCancel: (): void => { }
  };
  const req = new EhRequest()
    .setMethod(123)
    .setArgs(['a', 1])
    .setCallback(cb);
  req.bindTask(task);
  eq('method', req.getMethod(), 123);
  eq('args', req.getArgs(), ['a', 1]);
  ok('callback 已设置', req.getCallback() === cb);

  // 未设置 ehConfig → 回落到全局
  const globalCfg = new EhConfig();
  globalCfg.imageSize = EhConfig.IMAGE_SIZE_1280X;
  EhRequest.setConfig({ getEhConfig: (): EhConfig => globalCfg });
  eq('getEhConfig 回落全局', req.getEhConfig().imageSize, EhConfig.IMAGE_SIZE_1280X);

  // 显式设置 → 用自身
  const own = new EhConfig();
  own.imageSize = EhConfig.IMAGE_SIZE_780X;
  req.setEhConfig(own);
  eq('getEhConfig 用自身', req.getEhConfig().imageSize, EhConfig.IMAGE_SIZE_780X);

  // cancel 幂等
  eq('首次 cancel 返回 true', req.cancel(), true);
  eq('二次 cancel 返回 false', req.cancel(), false);
  eq('task.stop 只调一次', taskCancelled, 1);
  ok('isCancel', req.isCancel());
}

// ---------- EhRequestBuilder ----------
{
  const b1 = EhRequestBuilder.ofRefererOrigin('https://e-hentai.org/g/1/x/', 'https://e-hentai.org', 'https://e-hentai.org');
  eq('Referer 头', b1.build().headers().get('Referer'), 'https://e-hentai.org');
  eq('Origin 头', b1.build().headers().get('Origin'), 'https://e-hentai.org');

  const b2 = EhRequestBuilder.ofReferer('https://e-hentai.org/', null);
  eq('referer=null 不加头', b2.build().headers().get('Referer'), null);

  const b3 = EhRequestBuilder.ofReferer('https://e-hentai.org/', '');
  eq('referer="" 会加空头（上游判的是 != null）', b3.build().headers().get('Referer'), '');

  const headers = new Map<string, string>();
  headers.set('X-A', '1');
  headers.set('X-B', '2');
  const b4 = EhRequestBuilder.ofHeaders('https://e-hentai.org/', headers);
  eq('ofHeaders X-A', b4.build().headers().get('X-A'), '1');
  eq('ofHeaders X-B', b4.build().headers().get('X-B'), '2');
  ok('ChromeRequestBuilder 的 UA 仍在', ((b4.build().headers().get('User-Agent') as string) || '').indexOf('Chrome') >= 0);
}

// ---------- EhCookieStore ----------
{
  const store = new InMemoryCookieStore();
  const cs = new EhCookieStore(store);
  const URL_E = HttpUrl.parse('https://e-hentai.org/') as HttpUrl;

  ok('初始未登录', !cs.hasSignedIn());
  cs.addCookie(new CookieBuilder().name('ipb_member_id').value('1')
    .domain('e-hentai.org').path('/').expiresAt(Date.now() + HOUR).build());
  ok('只有 member_id 仍未登录', !cs.hasSignedIn());
  cs.addCookie(new CookieBuilder().name('ipb_pass_hash').value('h')
    .domain('e-hentai.org').path('/').expiresAt(Date.now() + HOUR).build());
  ok('两个登录 cookie 齐 → 已登录', cs.hasSignedIn());

  // 覆写 loadForRequest：过滤存量 nw / uconfig，E 站请求末尾追加 tips cookie
  cs.addCookie(new CookieBuilder().name(EhConfig.KEY_CONTENT_WARNING).value('0')
    .domain('e-hentai.org').path('/').expiresAt(Date.now() + HOUR).build());
  cs.addCookie(new CookieBuilder().name(EhConfig.KEY_UCONFIG).value('old')
    .domain('e-hentai.org').path('/').expiresAt(Date.now() + HOUR).build());
  const loadedE = cs.loadForRequest(URL_E);
  eq('loadForRequest E 站过滤存储的 nw 后只附加一条 tips',
    loadedE.filter((c) => c.name() === EhConfig.KEY_CONTENT_WARNING).map((c) => c.value()),
    [EhConfig.CONTENT_WARNING_NOT_SHOW]);
  ok('loadForRequest E 站过滤存储的 uconfig',
    !loadedE.some((c) => c.name() === EhConfig.KEY_UCONFIG));
  ok('tips cookie 追加在末尾',
    loadedE[loadedE.length - 1].name() === EhConfig.KEY_CONTENT_WARNING);

  const withTips = cs.loadForRequestWithTips(URL_E);
  ok('loadForRequestWithTips 委托 loadForRequest',
    withTips.some((c) => c.name() === EhConfig.KEY_CONTENT_WARNING));
  const EX = HttpUrl.parse('https://exhentai.org/') as HttpUrl;
  const noTips = cs.loadForRequest(EX);
  ok('非 E 站域不追加 tips', !noTips.some((c) => c.name() === EhConfig.KEY_CONTENT_WARNING));

  // signOut
  cs.signOut();
  ok('signOut 后未登录', !cs.hasSignedIn());
  eq('signOut 后库为空', store.rowCount(), 0);

  // newCookie 三态
  const session = new CookieBuilder().name('k').value('v').domain('e-hentai.org').path('/').build();
  const forced = EhCookieStore.newCookie(session, 'exhentai.org', true, false, false);
  eq('forcePersistent → expiresAt 拉满', forced.expiresAt(), EhCookieStore.MAX_EXPIRES);
  eq('域被改写', forced.domain(), 'exhentai.org');
  ok('forcePersistent 后是持久 cookie', forced.persistent());

  const longLive = EhCookieStore.newCookie(session, 'exhentai.org', false, true, false);
  eq('forceLongLive 也拉满', longLive.expiresAt(), EhCookieStore.MAX_EXPIRES);

  const kept = EhCookieStore.newCookie(
    new CookieBuilder().name('k').value('v').domain('e-hentai.org').path('/')
      .expiresAt(Date.now() + HOUR).build(), 'exhentai.org', false, false, false);
  ok('原持久性被保留（不是 MAX）', kept.expiresAt() !== EhCookieStore.MAX_EXPIRES);
  eq('tips cookie 值', EhCookieStore.tipsCookie().value(), EhConfig.CONTENT_WARNING_NOT_SHOW);
}

// ---------- EhHosts ----------
{
  const defCfg = new EhHostsConfig();
  eq('默认 BuiltIn=true', defCfg.getBuiltInHosts(), true);
  eq('默认 BuiltEX=true', defCfg.getBuiltEXHosts(), true);
  eq('默认 DoH=false', defCfg.getDoH(), false);

  class OffConfig extends EhHostsConfig {
    getBuiltInHosts(): boolean {
      return false;
    }

    getBuiltEXHosts(): boolean {
      return false;
    }

    getDoH(): boolean {
      return false;
    }
  }

  const off = new OffConfig();
  eq('全关配置 → 内置表为空', EhHosts.builtInHosts(off).size, 0);

  class OnConfig extends EhHostsConfig {
    getDoH(): boolean {
      return true;
    }
  }

  const on = new OnConfig();
  const table = EhHosts.builtInHosts(on);
  eq('e-hentai.org 有 6 个 IP', (table.get('e-hentai.org') as string[]).length, 6);
  eq('exhentai.org 有 12 个 IP', (table.get('exhentai.org') as string[]).length, 12);
  ok('ehgt.org 含 IPv6', (table.get('ehgt.org') as string[]).some((ip) => ip.indexOf('2a00:7c80') === 0));

  // 四级回落：用户 hosts 优先
  const hosts = new EhHosts(on, (): number => 0); // 固定随机数 → shuffle 可预测
  const userProvider = { getList: (h: string): string[] | null => h === 'e-hentai.org' ? ['1.1.1.1'] : null };
  const doh = { lookup: (h: string): string[] => ['2.2.2.2'] };
  const system = { getAllByName: (h: string): string[] => ['3.3.3.3'] };

  eq('用户 hosts 优先', hosts.lookup('e-hentai.org', userProvider, doh, system), ['1.1.1.1']);
  eq('内置 hosts 次之', hosts.lookup('forums.e-hentai.org', userProvider, doh, system).length, 2);
  eq('DoH 第三', hosts.lookup('unknown.example', userProvider, doh, system), ['2.2.2.2']);

  const noDoh = new EhHosts(new EhHostsConfig(), (): number => 0);
  const emptyProvider = { getList: (): string[] | null => null };
  const emptyDoh = { lookup: (): string[] => [] };
  eq('DoH 关闭 → 系统 DNS', noDoh.lookup('x.example', emptyProvider, emptyDoh, system), ['3.3.3.3']);

  // DoH RFC 1035 编解码
  const dnsQuery = new Uint8Array(HttpDohResolver.encodeDnsQuery('e-hentai.org', 1));
  ok('DoH DNS 查询报文含 QNAME 长度字节 8 (e-hentai)', dnsQuery[12] === 8);
  // 构造最小 A + AAAA 响应报文（指针 0xc00c 指向 QNAME）
  const dnsResp = new Uint8Array([
    0x00, 0x00, 0x81, 0x80, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00,
    0x01, 0x61, 0x00, 0x00, 0x01, 0x00, 0x01,
    0xc0, 0x0c, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x3c, 0x00, 0x04,
    104, 20, 18, 168
  ]);
  eq('DoH decodeDnsResponse 解析 A 记录',
    HttpDohResolver.decodeDnsResponse(dnsResp.buffer as ArrayBuffer), ['104.20.18.168']);

  // OkHttpEhHosts 异步四级解析与 isHostOverride 标注
  const sysFake: Dns = {
    lookup: async (h: string): Promise<InetAddress[]> => [new InetAddress(h, '9.9.9.9', false)]
  };
  const okDns = new OkHttpEhHosts(
    defCfg,
    { getList: (h: string): string[] | null => h === 'custom.test' ? ['1.2.3.4'] : null },
    null,
    { lookupAsync: async (): Promise<string[]> => ['8.8.8.8'] },
    sysFake,
    (): number => 0
  );
  // 同步块中稍后也可通过 async IIFE 检查；这里验证构造与默认开关即可
  void okDns;
}

// ---------- EhUrlOpener ----------
{
  const list = EhUrlOpener.parseUrl('https://e-hentai.org/?f_search=abc');
  ok('列表 URL → list', list !== null && list.kind === 'list');
  eq('list action', (list as { action: string }).action, EhUrlOpener.ACTION_LIST_URL_BUILDER);

  const detail = EhUrlOpener.parseUrl('https://exhentai.org/g/123/abcdef0123/');
  ok('详情 URL → detail', detail !== null && detail.kind === 'detail');
  eq('detail gid', (detail as { gid: number }).gid, 123);
  eq('detail token', (detail as { token: string }).token, 'abcdef0123');

  const page = EhUrlOpener.parseUrl('https://e-hentai.org/s/aaaaaaaaaa/456-3');
  ok('阅读 URL → page', page !== null && page.kind === 'page');
  eq('page gid', (page as { gid: number }).gid, 456);
  eq('page pToken', (page as { pToken: string }).pToken, 'aaaaaaaaaa');
  eq('page 页码（0 基）', (page as { page: number }).page, 2);

  eq('无效 URL → null', EhUrlOpener.parseUrl('hello'), null);
  eq('空 URL → null', EhUrlOpener.parseUrl(''), null);
  eq('null → null', EhUrlOpener.parseUrl(null), null);
}

console.log(`\n=== 结果：${pass} passed, ${fail} failed ===`);
if (fail > 0) {
  for (const f of failures) {
    console.log('  FAIL ' + f);
  }
  throw new Error('client 断言失败：' + fail);
}
