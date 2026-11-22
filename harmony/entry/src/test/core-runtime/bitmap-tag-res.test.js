// BitmapUtils 采样率 / TagTranslationUtil / ResourcesUtils 断言
global.Observed = (target) => target;
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out10');

const { BitmapUtils, SampleSizeHolder } = require(path.join(OUT, 'util', 'BitmapUtils.js'));
const { ResourcesUtils } = require(path.join(OUT, 'lib', 'yorozuya', 'ResourcesUtils.js'));
const { TagTranslationUtil } = require(path.join(OUT, 'ehviewer', 'util', 'TagTranslationUtil.js'));

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};

(async () => {
  const mkIsp = (calls) => ({
    obtain: () => calls.push('obtain'), open: () => ({ s: 1 }),
    close: () => calls.push('close'), release: () => calls.push('release'),
  });
  const HUGEMEM = () => 1024 * 1024 * 1024;

  // ── 采样率：四个 scale 取最大 ──
  const run = async (w, h, maxW, maxH, px, checkMem, mem) => {
    const holder = new SampleSizeHolder();
    const calls = [];
    const r = await BitmapUtils.decodeStream(mkIsp(calls), maxW, maxH, px, checkMem, true, holder,
      () => ({ outWidth: w, outHeight: h }), async () => null, mem || HUGEMEM);
    return { sample: holder.value, result: r, calls };
  };

  let r = await run(1000, 1000, 0, 0, -1, false);
  eq(r.sample, 1, '无限制 → inSampleSize=1');
  eq(r.result, null, 'justCalc=true → 返回 null（不解码）');

  r = await run(1000, 500, 100, 0, -1, false);
  eq(r.sample, 16, '宽超限 1000/100=10 → nextPowerOf2(10)=16');

  r = await run(500, 1000, 0, 100, -1, false);
  eq(r.sample, 16, '高超限 1000/100=10 → nextPowerOf2(10)=16');

  r = await run(1000, 1000, 0, 0, 250000, false);
  eq(r.sample, 2, '像素数 1e6 > 250000 → ceil(sqrt(4))=2');

  r = await run(1000, 1000, 200, 0, 100000, false);
  eq(r.sample, 8, '多路限制取**最大**：宽 1000/200=5、像素 ceil(sqrt(1e6/1e5))=4 → max=5 → nextPowerOf2=8');

  // ── 内存不足 ──
  r = await run(1000, 1000, 0, 0, -1, true, () => 1024 * 1024);  // 可用 1MB < 5MB 阈值
  eq(r.sample, -1, '可用内存 < 5MB → sampleSize=-1、返回 null');
  eq(r.result, null, '…结果为 null');

  // ── 尺寸非法 ──
  r = await run(0, 500, 0, 0, -1, false);
  eq(r.sample, -1, '宽=0 → sampleSize=-1');
  r = await run(500, -1, 0, 0, -1, false);
  eq(r.sample, -1, '高=-1 → sampleSize=-1');

  // ── finally 一定 close+release（上游 finally）──
  r = await run(1000, 1000, 0, 0, -1, false);
  eq(r.calls.indexOf('release') >= 0, true, 'finally 里调用 release()');
  eq(r.calls.filter((c) => c === 'close').length >= 1, true, '…且调用过 close()');

  // ── ResourcesUtils：类型校验 + 抛错 ──
  eq(ResourcesUtils.TYPE_FIRST_INT, 0x10, 'TYPE_FIRST_INT = 0x10');
  eq(ResourcesUtils.TYPE_LAST_INT, 0x1f, 'TYPE_LAST_INT = 0x1f');
  eq(ResourcesUtils.TYPE_DIMENSION, 0x05, 'TYPE_DIMENSION = 0x05');

  eq(ResourcesUtils.getAttrColor(() => ({ type: 0x10, data: 0xff00ff }), 1), 0xff00ff,
    'getAttrColor: int 段内 → 返回 data');
  const throwsWith = (fn, sub) => { try { fn(); return false; } catch (e) { return String(e.message).indexOf(sub) >= 0; } };
  eq(throwsWith(() => ResourcesUtils.getAttrColor(() => ({ type: 0x03, data: 1 }), 0x7f020001), '#0x7f020001'),
    true, 'getAttrColor: 类型非法 → 抛错且消息含 #0x + attrId');
  eq(throwsWith(() => ResourcesUtils.getAttrColor(() => ({ type: 0x03, data: 1 }), 0x7f020001), 'type #0x3'),
    true, '…且消息含 type #0x3（十六进制）');
  eq(ResourcesUtils.getAttrBoolean(() => ({ type: 0x12, data: 0 }), 1), false, 'getAttrBoolean: data=0 → false');
  eq(ResourcesUtils.getAttrBoolean(() => ({ type: 0x12, data: 7 }), 1), true, 'getAttrBoolean: data!=0 → true');
  eq(ResourcesUtils.getAttrDimensionPixelOffset(() => ({ type: 0x05, data: 100 }), (d) => d * 2, 1), 200,
    'getAttrDimensionPixelOffset: 类型对 → 走 convert');
  eq(throwsWith(() => ResourcesUtils.getAttrDimensionPixelOffset(() => ({ type: 0x10, data: 1 }), (d) => d, 1),
    'is not valid'), true, 'getAttrDimensionPixelOffset: 类型不是 DIMENSION → 抛错');
  eq(ResourcesUtils.getFloat(() => ({ type: 0x04, data: 1.5 }), 1), 1.5, 'getFloat 直接取 data');

  // ── TagTranslationUtil（用假 EhTagDatabase）──
  const mkDb = (map) => ({
    getTranslation: (k) => (k in map ? map[k] : null),
  });
  // 用真实 EhTagDatabase 的静态方法需要其内部表 → 这里只测"非 2 段"与 fallback 分支
  eq(TagTranslationUtil.getTagCN(['a'], null), 'a', '单段 tags + 无数据库 → "a"');
  eq(TagTranslationUtil.getTagCN(['a', 'b'], null), 'a:b', '两段 + 无数据库 → "a:b"');
  eq(TagTranslationUtil.getTagCN(['a', 'b', 'c'], null), 'a:b:c', '三段 → 用 : 拼接');
  eq(TagTranslationUtil.getTagCNBody(['a', 'b', 'c'], null), 'c',
    'getTagCNBody 三段 → 只剩最后一个（上游 StringBuffer 每次重置，A 类照搬）');
  eq(TagTranslationUtil.getTagCN1('female:solefemale', null), 'female:solefemale', 'getTagCN(String) 走 split');

  console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
  process.exit(fail === 0 ? 0 : 1);
})();
