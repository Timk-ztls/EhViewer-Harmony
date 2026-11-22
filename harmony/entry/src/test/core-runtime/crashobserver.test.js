// CrashObserver：去重器 + 两个回调归一 + 安装幂等
global.Observed = (target) => target;

// 打桩：@kit.AbilityKit 的 errorManager（记录 on 调用）
const path = require('path');
const d = process.env.TEMP;
const stubDir = path.join(d, 'tscheck', 'node_modules', '@kit.AbilityKit');
const fs = require('fs');
if (!fs.existsSync(stubDir)) fs.mkdirSync(stubDir, { recursive: true });
const onCalls = [];
fs.writeFileSync(path.join(stubDir, 'index.js'),
  'const calls = [];\n' +
  'global.__errorManagerOnCalls = calls;\n' +
  'module.exports = { errorManager: { on: (type, obs) => { calls.push([type, obs]); return calls.length; } } };\n');
global.__errorManagerOnCalls = onCalls;

const OUT = process.argv[2] || path.join(d, 'tscheck', 'out11');
const m = require(path.join(OUT, 'ehviewer', 'CrashObserver.js'));
const { CrashDeduper, AppErrorObserver, installCrashHandler, isCrashHandlerInstalled, CrashError } = m;

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};

// ── CrashDeduper ──
{
  let clock = 1000000;
  const ded = new CrashDeduper(1000, () => clock);
  eq(ded.shouldSave('boom'), true, '首次同消息 → 放行');
  clock += 999;
  eq(ded.shouldSave('boom'), false, '999ms 内同消息 → 判重跳过');
  clock += 1;   // 正好 1000ms
  eq(ded.shouldSave('boom'), true, '**正好 1000ms → 放行**（窗口是严格小于）');
  clock += 10;
  eq(ded.shouldSave('other'), true, '不同消息 → 立刻放行（互不影响）');
  clock += 10;
  eq(ded.shouldSave('boom'), true, '不同消息之后，前一条消息的窗口已重置（last-key 语义）');
  // 说明 last-key 语义：A,B,A 在窗口内会放行 A 两次
  clock = 2000000;
  const ded2 = new CrashDeduper(1000, () => clock);
  ded2.shouldSave('A');
  ded2.shouldSave('B');
  eq(ded2.shouldSave('A'), true, 'A,B,A 在同一窗口 → 第三个 A **放行**（只记住最后一条 key，上游同类去重也是这么简单）');
}

// ── AppErrorObserver：两个回调归一成一次 handleCrash ──
{
  let clock = 3000000;
  const got = [];
  const obs = new AppErrorObserver((t) => got.push(t.message), new CrashDeduper(1000, () => clock));
  // onUnhandledException（只有消息 + 栈文本）
  obs.onUnhandledException('TypeError: x is undefined\n  at a.b(c.ets:1)');
  eq(got.length, 1, 'onUnhandledException → 触发一次');
  eq(got[0].indexOf('TypeError') >= 0, true, '…消息里含异常文本');
  // onException（有 Error 对象）
  clock += 5000;
  const err = new Error('EACCES: permission denied');
  obs.onException(err);
  eq(got.length, 2, 'onException → 再触发一次（5s 后，不受窗口影响）');
  eq(got[1], 'EACCES: permission denied', '…取 Error.message');

  // **同一次崩溃两个回调都触发 → 去重只放行一次**
  clock = 4000000;
  const got2 = [];
  const obs2 = new AppErrorObserver((t) => got2.push(t.message), new CrashDeduper(1000, () => clock));
  obs2.onUnhandledException('boom');
  obs2.onException(new Error('boom'));   // 同一消息、同一时刻
  eq(got2.length, 1, '**同消息在窗口内被两个回调各触发一次 → 只落一份**（去重生效）');

  // 不同消息两个回调都触发 → 落两份
  clock = 5000000;
  const got3 = [];
  const obs3 = new AppErrorObserver((t) => got3.push(t.message), new CrashDeduper(1000, () => clock));
  obs3.onUnhandledException('crash-A');
  obs3.onException(new Error('crash-B'));
  eq(got3, ['crash-A', 'crash-B'], '不同消息 → 两份都落（不误杀）');

  // handleCrash 自己抛错不能递归崩
  let threw = false;
  const obs4 = new AppErrorObserver(() => { throw new Error('handler 内部错'); },
    new CrashDeduper(1000, () => clock));
  try { obs4.onUnhandledException('x'); } catch (e) { threw = true; }
  eq(threw, false, 'handleCrash 抛错被吞掉（避免崩溃处理自身递归崩）');
}

// ── installCrashHandler：幂等 + 通过 errorManager.on('error', observer) ──
{
  eq(isCrashHandlerInstalled(), false, '未安装时 isCrashHandlerInstalled = false');
  const id1 = installCrashHandler(() => {});
  eq(typeof id1 === 'number' && id1 > 0, true, 'installCrashHandler 返回 errorManager.on 的 id，实际=' + id1);
  eq(global.__errorManagerOnCalls.length, 1, '…调用 errorManager.on 一次');
  eq(global.__errorManagerOnCalls[0][0], 'error', "…事件类型是 'error'");
  const obs = global.__errorManagerOnCalls[0][1];
  eq(typeof obs.onUnhandledException === 'function', true, '…传入的 observer 有 onUnhandledException');
  eq(typeof obs.onException === 'function', true, '…也有 onException（两条路径都不能缺）');
  const id2 = installCrashHandler(() => {});
  eq(id2, id1, '重复安装 → 返回同一个 id');
  eq(global.__errorManagerOnCalls.length, 1, '…**不会重复注册**（errorManager.on 只被调一次）');
  eq(isCrashHandlerInstalled(), true, '安装后 isCrashHandlerInstalled = true');
}

console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
process.exit(fail === 0 ? 0 : 1);
