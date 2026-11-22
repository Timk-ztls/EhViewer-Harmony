// signOut / clearDownloadPathCache 的运行时应断言
global.Observed = (target) => target;
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out9');
const { PreferenceActions } = require(path.join(OUT, 'PreferenceActions.js'));

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};

(async () => {
  // 1) RESTART_DELAY_MILLIS = 1500（上游 Thread.sleep(1500)）
  eq(PreferenceActions.RESTART_DELAY_MILLIS, 1500, 'RESTART_DELAY_MILLIS = 1500（上游 Thread.sleep(1500)）');

  // 2) signOut 的顺序：先 signOut，等 1500ms，再 restart
  const order = [];
  const t0 = Date.now();
  await PreferenceActions.signOut(async () => { order.push('signOut'); },
    () => { order.push('restart@' + (Date.now() - t0 >= 1400 ? 'after1500' : 'tooEarly')); });
  eq(order[0], 'signOut', '先执行 signOutFn');
  eq(order[1], 'restart@after1500', '再等 1500ms 之后才 restart（顺序与延迟都对）');

  // 3) signOutFn 同步实现也能用（上游 EhUtils.signOut 是同步的）
  const order2 = [];
  await PreferenceActions.signOut(() => { order2.push('sync-signOut'); }, () => { order2.push('restart'); });
  eq(order2, ['sync-signOut', 'restart'], 'signOutFn 为同步函数时也按序执行');

  // 4) signOutFn 抛错 → 不应重启（登出失败还重启会让用户以为登出成功）
  let restarted = false;
  let threw = false;
  try {
    await PreferenceActions.signOut(async () => { throw new Error('cookie clear failed'); },
      () => { restarted = true; });
  } catch (e) { threw = true; }
  eq(threw, true, 'signOutFn 抛错 → 异常向上传播（不吞）');
  eq(restarted, false, '…且**不会**重启（避免"登出失败却重启，用户以为成功了"）');

  // 5) clearDownloadPathCache：注入的清除动作被 await
  let cleared = false;
  await PreferenceActions.clearDownloadPathCache(async () => { cleared = true; });
  eq(cleared, true, 'clearDownloadPathCache 会 await 注入的清除动作');

  console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
  process.exit(fail === 0 ? 0 : 1);
})();
