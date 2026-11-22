// EhTagDatabase 测试（构造二进制样本）
//
// 二进制格式：4 字节大端长度 + UTF-8 正文；正文每行 `english\rBase64(chinese)`，行间 '\n'
// 必测：字节级二分查找（getTranslation）、prefix↔namespace 还原、suggest 上限 40、involve 双通道

import { EhTagDatabase, TagEntry } from '../EhTagDatabase';

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

// ---------- 构造二进制样本 ----------
const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

/** 最小 base64（只处理 ASCII 输入，够测试用）。 */
function b64(s: string): string {
  let out = '';
  for (let i = 0; i < s.length; i += 3) {
    const c1 = s.charCodeAt(i);
    const c2 = i + 1 < s.length ? s.charCodeAt(i + 1) : NaN;
    const c3 = i + 2 < s.length ? s.charCodeAt(i + 2) : NaN;
    const n = (c1 << 16) | ((isNaN(c2) ? 0 : c2) << 8) | (isNaN(c3) ? 0 : c3);
    out += B64[(n >> 18) & 63] + B64[(n >> 12) & 63];
    out += isNaN(c2) ? '=' : B64[(n >> 6) & 63];
    out += isNaN(c3) ? '=' : B64[n & 63];
  }
  return out;
}

function utf8(s: string): Uint8Array {
  const out: number[] = [];
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c < 0x80) {
      out.push(c);
    } else if (c < 0x800) {
      out.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f));
    } else {
      out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
    }
  }
  return new Uint8Array(out);
}

/** 组装数据库二进制：长度头 + 正文。 */
function buildDb(lines: string[]): ArrayBuffer {
  const text = lines.join('\n');
  const body = utf8(text);
  const out = new Uint8Array(4 + body.length);
  const len = body.length;
  out[0] = (len >>> 24) & 0xff;
  out[1] = (len >>> 16) & 0xff;
  out[2] = (len >>> 8) & 0xff;
  out[3] = len & 0xff;
  out.set(body, 4);
  return out.buffer as ArrayBuffer;
}

// 注意 1：行必须按 **文件里的 english 原文**（短前缀形式）升序 —— 上游二分直接比字节
// 注意 2：文件里用短前缀（f:），parseTag 才把它还原成 namespace:name（female:）
const LINES: string[] = [
  `f:yaoi\r${b64('yaoi-cn')}`,
  `l:chinese\r${b64('chinese-cn')}`,
  `m:male\r${b64('male-cn')}`,
  `r:other\r${b64('other-cn')}`
];

// ---------- 1. 解析与 prefix→namespace 还原 ----------
{
  const db = new EhTagDatabase('test.db', buildDb(LINES));
  eq('name', db.getName(), 'test.db');
  eq('tagList 4 条', db.getTagList().length, 4);
  eq('female:yaoi 的 english 已还原 namespace', db.getTagList()[0].english, 'female:yaoi');
  eq('chinese 已 base64 解码', db.getTagList()[0].chinese, 'yaoi-cn');
  eq('reclass:other', db.getTagList()[3].english, 'reclass:other');

  // 无 '\r' 的行 → chinese = "null"
  const db2 = new EhTagDatabase('t2', buildDb(['a:b']));
  eq('缺 \\r 行 → chinese "null"', db2.getTagList()[0].chinese, 'null');
}

// ---------- 2. getTranslation（字节级二分） ----------
{
  const db = new EhTagDatabase('test.db', buildDb(LINES));
  eq('命中第一条（key 用短前缀）', db.getTranslation('f:yaoi'), 'yaoi-cn');
  eq('命中最后一条', db.getTranslation('r:other'), 'other-cn');
  eq('命中中间', db.getTranslation('l:chinese'), 'chinese-cn');
  eq('不命中 → null', db.getTranslation('f:nope'), null);
  eq('前缀不同 → null', db.getTranslation('a:yaoi'), null);
  eq('空串 → null', db.getTranslation(''), null);

  // 单条库（边界：只有一行，无后续 '\n'）
  const single = new EhTagDatabase('s', buildDb(['f:only\r' + b64('only-cn')]));
  eq('单行库命中', single.getTranslation('f:only'), 'only-cn');
  eq('单行库不命中', single.getTranslation('f:other'), null);
}

// ---------- 3. suggest（≤40，双通道命中） ----------
{
  const db = new EhTagDatabase('test.db', buildDb(LINES));
  const s1 = db.suggest('yaoi');
  eq('suggest(yaoi) 1 条', s1.length, 1);
  eq('suggest 返回 chinese', s1[0].chinese, 'yaoi-cn');
  eq('suggest 返回 english', s1[0].english, 'female:yaoi');

  const s2 = db.suggest('cn');
  eq('suggest(cn) 命中 4 条（chinese 都含 cn）', s2.length, 4);

  const s3 = db.suggest('zzz');
  eq('suggest 无命中', s3.length, 0);

  // 40 条上限
  const many: string[] = [];
  for (let i = 0; i < 60; i++) {
    many.push(`female:t${i < 10 ? '0' + i : i}\r${b64('cn')}`);
  }
  const bigDb = new EhTagDatabase('big', buildDb(many));
  eq('suggest 上限 40', bigDb.suggest('cn').length, 40);
}

// ---------- 4. namespace ↔ prefix ----------
{
  eq('namespaceToPrefix(female)', EhTagDatabase.namespaceToPrefix('female'), 'f:');
  eq('namespaceToPrefix(misc) = 空串', EhTagDatabase.namespaceToPrefix('misc'), '');
  eq('namespaceToPrefix(cosplayer)', EhTagDatabase.namespaceToPrefix('cosplayer'), 'cos:');
  // 传入已知短前缀（不带冒号）时原样返回前缀（上游语义）
  eq('namespaceToPrefix(f) → f', EhTagDatabase.namespaceToPrefix('f'), 'f');
  eq('namespaceToPrefix 未知 → null', EhTagDatabase.namespaceToPrefix('nope'), null);

  eq('prefixToNamespace(f:)', EhTagDatabase.prefixToNamespace('f:'), 'female');
  eq('prefixToNamespace("")', EhTagDatabase.prefixToNamespace(''), 'misc');
  eq('prefixToNamespace(未知)', EhTagDatabase.prefixToNamespace('zz:'), null);
  eq('表大小 14/14', EhTagDatabase.NAMESPACE_TO_PREFIX.size + EhTagDatabase.PREFIX_TO_NAMESPACE.size, 28);
}

// ---------- 5. TagEntry.involve ----------
{
  const t = new TagEntry('female:yaoi', 'yaoi-cn');
  ok('involve 命中 english', t.involve('yaoi'));
  ok('involve 命中 chinese', t.involve('cn'));
  ok('involve 不命中', !t.involve('zzz'));
}

// ---------- 6. 坏数据 ----------
{
  let threw = false;
  try {
    new EhTagDatabase('bad', new ArrayBuffer(2));
  } catch (e) {
    threw = (e as Error).message === 'tag database too short';
  }
  ok('长度头不足 4 字节 → 抛错', threw);

  let threw2 = false;
  const bad = new Uint8Array(8);
  bad[3] = 100; // 声明 100 字节但只有 4 字节正文
  try {
    new EhTagDatabase('bad2', bad.buffer as ArrayBuffer);
  } catch (e) {
    threw2 = (e as Error).message === 'tag database length mismatch';
  }
  ok('声明长度超过实际 → 抛错', threw2);
}

console.log(`\n=== 结果：${pass} passed, ${fail} failed ===`);
if (fail > 0) {
  for (const f of failures) {
    console.log('  FAIL ' + f);
  }
  throw new Error('EhTagDatabase 断言失败：' + fail);
}
