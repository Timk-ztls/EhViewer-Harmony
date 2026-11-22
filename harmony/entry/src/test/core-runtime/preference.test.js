// ArkTS 的 @Observed 装饰器在 Node 里没有实现 → 必须在任何 require 之前打桩
global.Observed = (target) => target;

// CleanRedundancy / VersionPreference 的运行时断言（纯逻辑，注入 fake）
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out5');
const { CleanRedundancyPreference } = require(path.join(OUT, 'CleanRedundancyPreference.js'));
const { VersionPreference } = require(path.join(OUT, 'VersionPreference.js'));

// ArkTS 的 @Observed 装饰器在 Node 里没有实现 → 打一个 no-op 桩（只为让模块可加载）
global.Observed = (target) => target;

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};

// fake UniFile：只有 getName/delete/listFiles
const mkFile = (name, log) => ({
  getName: () => name,
  delete: () => { log.push('delete:' + name); return true; },
});

(async () => {
  // ── cleanFile 单文件判定（上游 ClearTask.clearFile 的四种分支）──
  const log = [];
  const containsNone = () => false;
  const containsAll = () => true;

  eq(CleanRedundancyPreference.clearFile(mkFile('123-abc', log), containsNone), true, 'gid 不在下载列表 → 删除');
  eq(log, ['delete:123-abc'], '…且真的调了 delete()');

  log.length = 0;
  eq(CleanRedundancyPreference.clearFile(mkFile('123-abc', log), containsAll), false, 'gid 仍在下载列表 → 不删');
  eq(log, [], '…且没有调用 delete()');

  log.length = 0;
  eq(CleanRedundancyPreference.clearFile(mkFile('notanumber-x', log), containsNone), false, '名字前缀不是数字 → 不删');
  eq(log, [], '…没有 delete()');

  log.length = 0;
  eq(CleanRedundancyPreference.clearFile(mkFile('456', log), containsNone), true, '没有 "-" 的纯数字名 → 按整名解析');
  eq(log, ['delete:456'], '…删除');

  log.length = 0;
  eq(CleanRedundancyPreference.clearFile({ getName: () => undefined, delete: () => true }, containsNone), false, 'getName 为 undefined → 不删（C-13 空值防护）');

  // ── cleanRedundancy 整体流程 + 进度回调 ──
  const files = [mkFile('1-a', log), mkFile('2-b', log), mkFile('junk', log)];
  const dirFake = { listFiles: async () => files };
  log.length = 0;
  const progress = [];
  const r = await CleanRedundancyPreference.cleanRedundancy(
    (gid) => gid === 2,                      // 只有 gid=2 仍在下载
    (done, total) => progress.push([done, total]),
    dirFake);
  eq(r.total, 3, 'cleanRedundancy: total = 文件数');
  eq(r.count, 1, 'cleanRedundancy: 只删了 gid=1（gid=2 仍在、junk 解析失败）');
  eq(r.noDirectory, false, 'cleanRedundancy: 目录正常');
  eq(log, ['delete:1-a'], 'cleanRedundancy: 只对 gid=1 调了 delete');
  eq(progress, [[1, 3], [2, 3], [3, 3]], 'cleanRedundancy: 每个文件一次进度回调 (i+1,total)');

  // ── 目录取不到的两个分支（上游都是 publishProgress(0,0) 并返回 0）──
  const rNullDir = await CleanRedundancyPreference.cleanRedundancy(containsNone, undefined, null);
  eq(rNullDir.count, 0, 'downloadLocation 为 null → count=0');
  eq(rNullDir.noDirectory, true, '…且标记 noDirectory');

  const rNullList = await CleanRedundancyPreference.cleanRedundancy(containsNone, undefined,
    { listFiles: async () => null });
  eq(rNullList.count, 0, 'listFiles 为 null → count=0');
  eq(rNullList.noDirectory, true, '…且标记 noDirectory');

  // ── VersionPreference：有版本号 / 回退 ──
  const v = VersionPreference.getVersionName();
  eq(typeof v === 'string' && v.length > 0, true, 'getVersionName 返回非空字符串（真机取到版本或回退 unknown）');
  eq(VersionPreference.FALLBACK, 'unknown', 'FALLBACK 常量 = unknown（对应上游 R.string.error_unknown）');

  console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
  process.exit(fail === 0 ? 0 : 1);
})();
