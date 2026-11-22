// AppHelper（compareVersion / isWifiProxy / checkVpn / copyPlainText / mailto）+ UrlOpener 决策
global.Observed = (target) => target;
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out11');
const { AppHelper, MailtoRequest } = require(path.join(OUT, 'util', 'AppHelper.js'));
const { UrlOpener, UrlOpenDecision } = require(path.join(OUT, 'ehviewer', 'UrlOpener.js'));

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};
const throws = (fn, label) => {
  let threw = false;
  try { fn(); } catch (e) { threw = true; }
  eq(threw, true, label);
};

// ══ compareVersion ══
eq(AppHelper.compareVersion('2.0.2.6', '2.0.2.6'), 0, '相同版本 → 0');
eq(AppHelper.compareVersion('2.0.2.6', '2.0.2.7'), -1, '低位小 → -1');
eq(AppHelper.compareVersion('2.0.3.0', '2.0.2.9'), 1, '高位大 → 1（不是字符串比较）');
eq(AppHelper.compareVersion('1.10', '1.9'), 1, '**1.10 > 1.9**（数值比较，不是字典序）');
eq(AppHelper.compareVersion('1.9', '1.10'), -1, '…反向');
// 缺段补 0
eq(AppHelper.compareVersion('1.0', '1'), 0, '1.0 == 1（缺段补 0）');
eq(AppHelper.compareVersion('1', '1.0.0.0'), 0, '1 == 1.0.0.0');
eq(AppHelper.compareVersion('1.0.1', '1'), 1, '1.0.1 > 1');
eq(AppHelper.compareVersion('2', '1.9.9.9.9'), 1, '**段数少但数值大 → 1**（先比完公共段）');
// 非数字 → 抛（上游 toInt() 的 NumberFormatException）
throws(() => AppHelper.compareVersion('1.2-beta', '1.2'), '**"1.2-beta" 抛错**（上游 toInt() 会抛，不静默当 0）');
throws(() => AppHelper.compareVersion('1.2', ''), '**空串段抛错**（"1.2".split 后第二段为 ""）');
eq(AppHelper.compareVersion('0', '0'), 0, "'0' vs '0' → 0");
eq(AppHelper.compareVersion('-1', '0'), -1, "负数段照常比较（-1 < 0）");

// ══ isWifiProxy（名字带 WiFi，实际只看 HTTP 代理系统属性）══
eq(AppHelper.isWifiProxy('127.0.0.1', '8080'), true, 'host + port 都有效 → true');
eq(AppHelper.isWifiProxy(null, '8080'), false, 'host=null → false');
eq(AppHelper.isWifiProxy('', '8080'), false, '**host="" → false**（TextUtils.isEmpty 而非仅判 null）');
eq(AppHelper.isWifiProxy('127.0.0.1', null), false, '**port=null → "-1" → false**');
eq(AppHelper.isWifiProxy('127.0.0.1', '-1'), false, 'port="-1" → false');
eq(AppHelper.isWifiProxy('127.0.0.1', '0'), true, 'port="0" → true（0 不是 -1）');
throws(() => AppHelper.isWifiProxy('127.0.0.1', 'abc'), '**port="abc" 抛错**（上游 toInt() 会抛）');

// ══ checkVpn：返回取反 ══
eq(AppHelper.checkVpn(true), false, '**checkVpn(VPN 网络) → false**（上游 return !result）');
eq(AppHelper.checkVpn(false), true, 'checkVpn(非 VPN) → true');

// ══ copyPlainText：无 null/空串判断 ══
{
  const calls = [];
  const clip = { setText: () => {}, setPrimaryClipText: (t) => calls.push(t), hasText: () => false, getText: () => null };
  AppHelper.copyPlainText('hello', clip);
  eq(calls, ['hello'], 'copyPlainText 写入原文');
  AppHelper.copyPlainText('', clip);
  eq(calls[1], '', '**空串也照写**（上游没有 isEmpty 判断，与 ClipboardUtil.copyText 不同）');
  AppHelper.copyPlainText(null, clip);
  eq(calls[2], 'null', '**null 写成字面量 "null"**（ClipData.newPlainText(null, null) 的表现）');
}

// ══ mailto 请求构造 ══
{
  const r = new MailtoRequest('a@b.c', '主题', null);
  eq(r.getUri(), 'mailto:a@b.c', 'uri = mailto:<address>');
  eq([r.hasSubject(), r.hasText()], [true, false], 'subject 有、text 无');
  const r2 = AppHelper.buildMailtoRequest('x@y.z', null, '正文');
  eq([r2.hasSubject(), r2.hasText()], [false, true], 'subject=null 时不放该 extra');
  eq(r2.getUri(), 'mailto:x@y.z', '…uri 不受影响');
}

// ══ UrlOpener 决策 ══
{
  eq(UrlOpener.decide(null, true), UrlOpenDecision.NONE, 'url=null → NONE');
  eq(UrlOpener.decide('', true), UrlOpenDecision.NONE, '**url="" → NONE**（最前面短路，连解析都不做）');
  // 非 EH URL → 外部
  eq(UrlOpener.decide('https://example.com/x', true), UrlOpenDecision.EXTERNAL,
    '非 EH URL → EXTERNAL（即使 ehUrl=true）');
  eq(UrlOpener.decide('https://example.com/x', false), UrlOpenDecision.EXTERNAL, 'ehUrl=false → EXTERNAL');
}

// 用真实解析器验证"EH URL 在 ehUrl=true 时走应用内"
{
  const cases = [
    ['https://e-hentai.org/g/123/abcdef1234/', 'DETAIL'],
    ['https://exhentai.org/g/123/abcdef1234/', 'DETAIL'],
  ];
  for (const [u, kind] of cases) {
    const d = UrlOpener.decide(u, true);
    eq(d, UrlOpenDecision.IN_APP, `EH 详情 URL（${kind}）→ IN_APP`);
    eq(UrlOpener.decide(u, false), UrlOpenDecision.EXTERNAL, `…同 URL + ehUrl=false → EXTERNAL`);
  }
}

// ══ openUrl 编排：注入两个动作，断言只走一条 ══
{
  const calls = [];
  const openInApp = (t) => calls.push('app:' + t.kind);
  const openExternal = (u, pkg) => calls.push('ext:' + u + ':' + pkg);

  eq(UrlOpener.openUrl(null, true, 'com.x', openInApp, openExternal), UrlOpenDecision.NONE,
    'openUrl(null) → NONE');
  eq(calls.length, 0, '…两个动作都没调用');

  const d1 = UrlOpener.openUrl('https://e-hentai.org/g/123/abcdef1234/', true, 'com.x',
    openInApp, openExternal);
  eq(d1, UrlOpenDecision.IN_APP, 'EH URL → IN_APP');
  eq(calls.length, 1, '**只调用一个动作**（不是两边都开）');
  eq(calls[0].startsWith('app:'), true, '…调用的是应用内，实际=' + calls[0]);

  calls.length = 0;
  const d2 = UrlOpener.openUrl('https://example.com/', true, 'com.x', openInApp, openExternal);
  eq(d2, UrlOpenDecision.EXTERNAL, '非 EH URL → EXTERNAL');
  eq(calls, ['ext:https://example.com/:com.x'], '…调用外部且带 packageName（对应 Browser.EXTRA_APPLICATION_ID）');
}

console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
process.exit(fail === 0 ? 0 : 1);
