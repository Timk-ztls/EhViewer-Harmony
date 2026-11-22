// SqlUtils / JsoupUtils / GifHandler 断言
global.Observed = (target) => target;
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out9');
const u = path.join(OUT, 'util');
const { SqlUtils } = require(path.join(u, 'SqlUtils.js'));
const { JsoupUtils } = require(path.join(u, 'JsoupUtils.js'));
const { GifHandler } = require(path.join(u, 'GifHandler.js'));

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};

(async () => {
  // ── SqlUtils.sqlEscapeString ──
  eq(SqlUtils.sqlEscapeString("abc"), 'abc', "无单引号原样返回");
  eq(SqlUtils.sqlEscapeString("a'b"), "a''b", "单引号 → 两个单引号");
  eq(SqlUtils.sqlEscapeString("'"), "''", "单个单引号 → 两个");
  eq(SqlUtils.sqlEscapeString("''"), "''''", "两个 → 四个（逐字符翻倍）");
  eq(SqlUtils.sqlEscapeString('a"b'), 'a"b', '双引号不转义（上游只处理单引号）');
  eq(SqlUtils.sqlEscapeString('a\\b;--'), 'a\\b;--', '反斜杠/分号/注释符都不处理（上游只处理单引号）');
  eq(SqlUtils.sqlEscapeString('中文'), '中文', '非 ASCII 原样');

  // ── SqlUtils 类型化 getter（用假 ResultSet）──
  const mkRs = (cols) => ({
    getColumnIndex: (name) => (name in cols ? Object.keys(cols).indexOf(name) : -1),
    getLong: (i) => cols[Object.keys(cols)[i]],
    getDouble: (i) => cols[Object.keys(cols)[i]],
    getString: (i) => String(cols[Object.keys(cols)[i]]),
    goToFirstRow: () => true, goToNextRow: () => false, close: () => {},
  });
  const rs = mkRs({ a: 5, b: 0, c: 7000000000, d: 1.5, e: 'txt' });
  eq(SqlUtils.getInt(rs, 'a', -1), 5, 'getInt 取到列值');
  eq(SqlUtils.getInt(rs, 'missing', -1), -1, 'getInt 列不存在 → defValue');
  eq(SqlUtils.getBoolean(rs, 'a', false), true, 'getBoolean: 5 != 0 → true');
  eq(SqlUtils.getBoolean(rs, 'b', true), false, 'getBoolean: 0 → false');
  eq(SqlUtils.getBoolean(rs, 'missing', true), true, 'getBoolean 列不存在 → defValue');
  eq(SqlUtils.getLong(rs, 'c', 0), 7000000000, 'getLong 保留大整数（无 |0 截断）');
  eq(SqlUtils.getInt(rs, 'c', 0) !== 7000000000, true, 'getInt 对大数截断（|0）——与 getLong 的差异');
  eq(SqlUtils.getFloat(rs, 'd', 0), 1.5, 'getFloat 用 getDouble');
  eq(SqlUtils.getString(rs, 'e', null), 'txt', 'getString 取到值');
  eq(SqlUtils.getString(rs, 'missing', null), null, 'getString 列不存在 → null');

  // getter 遇到抛错的 ResultSet → defValue（不崩）
  const badRs = { getColumnIndex: () => { throw new Error('boom'); } };
  eq(SqlUtils.getInt(badRs, 'a', 42), 42, 'getInt：ResultSet 抛错 → defValue（不崩）');

  // ── dropAllTable：排除 android_metadata / sqlite_sequence ──
  const executed = [];
  const fakeDb = {
    querySql: async () => {
      const names = ['DOWNLOADS', 'android_metadata', 'sqlite_sequence', 'HISTORY'];
      let i = -1;
      return {
        goToFirstRow: () => { i = 0; return true; },
        goToNextRow: () => { i++; return i < names.length; },
        getString: () => names[i],
        close: () => {},
      };
    },
    executeSql: async (sql) => { executed.push(sql); },
  };
  await SqlUtils.dropAllTable(fakeDb);
  eq(executed, ['DROP TABLE IF EXISTS DOWNLOADS', 'DROP TABLE IF EXISTS HISTORY'],
    'dropAllTable 只删业务表（排除 android_metadata / sqlite_sequence）');

  // exeSQLSafely 吞异常
  const dbErr = { executeSql: async () => { throw new Error('table exists'); } };
  let threw = false;
  try { await SqlUtils.exeSQLSafely(dbErr, 'ALTER TABLE X ADD COLUMN Y'); } catch (e) { threw = true; }
  eq(threw, false, 'exeSQLSafely 吞掉异常（上游 // Ignore 语义）');

  // ── JsoupUtils：空集合 → null ──
  const mkEl = (classes) => ({
    getElementsByClass: (n) => (classes[n] || []),
    getElementsByTag: (n) => (classes['#' + n] || []),
  });
  const el = mkEl({ hit: [1, 2], empty: [], '#div': [3] });
  eq(JsoupUtils.getElementByClass(el, 'hit') !== null, true, 'getElementByClass 有元素 → 返回第一个');
  eq(JsoupUtils.getElementByClass(el, 'empty'), null, 'getElementByClass 空集合 → null（上游语义）');
  eq(JsoupUtils.getElementByClass(el, 'none'), null, 'getElementByClass 无匹配 → null');
  eq(JsoupUtils.getElementsByClass(el, 'hit').length, 2, 'getElementsByClass 返回全部');
  eq(JsoupUtils.getElementsByClass(el, 'empty'), null, 'getElementsByClass 空 → null（不是空数组）');
  eq(JsoupUtils.getElementByTag(el, 'div') !== null, true, 'getElementByTag 有元素 → 第一个');
  eq(JsoupUtils.getElementByTag(el, 'span'), null, 'getElementByTag 无 → null');
  eq(JsoupUtils.getElementByClassFromDoc(el, 'hit') !== null, true, 'doc 版 getElementByClass');

  // ── GifHandler：帧推进 / 回绕 / 失败语义 ──
  const written = [];
  const mkDecoder = (frames, w, h) => ({
    getFrameCount: () => frames,
    getWidth: () => w,
    getHeight: () => h,
    decodeFrame: (i) => new Uint8ClampedArray([i, 0, 0, 255]),
    release: () => { written.push('released'); },
  });
  const target = { writePixels: (rgba, w2, h2) => written.push([rgba[0], w2, h2]) };

  const h3 = new GifHandler(mkDecoder(3, 10, 20));
  eq([h3.getWidth(), h3.getHeight()], [10, 20], 'GifHandler 尺寸来自解码器');
  eq([h3.updateFrame(target), h3.updateFrame(target), h3.updateFrame(target), h3.updateFrame(target)],
    [0, 1, 2, 0], 'updateFrame 逐帧推进并在末帧后**回绕到 0**（GIF 循环）');
  eq(written[0], [0, 10, 20], '…每次写入都带正确宽高');

  const hNull = new GifHandler(null);
  eq([hNull.getWidth(), hNull.getHeight(), hNull.updateFrame(target)], [0, 0, -1],
    '解码器打开失败 → 尺寸 0、updateFrame 返回 -1（上游 native 返回 0 同义）');

  const hZero = new GifHandler(mkDecoder(0, 1, 1));
  eq(hZero.updateFrame(target), -1, '零帧解码器 → updateFrame 返回 -1（不除零）');

  written.length = 0;
  h3.release();
  eq(written.indexOf('released') >= 0, true, 'release() 释放解码器（上游无此方法，属 B 类修复）');
  eq(h3.updateFrame(target), -1, 'release 后 updateFrame → -1（不再访问已释放句柄）');

  console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
  process.exit(fail === 0 ? 0 : 1);
})();
