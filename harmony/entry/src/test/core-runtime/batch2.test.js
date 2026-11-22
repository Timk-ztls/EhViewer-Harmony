// FavouriteStatusRouter + ShakeDetector 断言
global.Observed = (target) => target;
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out11');
const { FavouriteStatusRouter } = require(path.join(OUT, 'ehviewer', 'FavouriteStatusRouter.js'));
const { ShakeDetector } = require(path.join(OUT, 'ehviewer', 'widget', 'ShakeDetector.js'));

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};

// ── FavouriteStatusRouter ──
const r = new FavouriteStatusRouter();
const info = (gid) => ({ gid, favoriteSlot: -1 });

// saveDataMap / restoreDataMap：一次性消费
const map1 = new Map([[123, info(123)], [456, info(456)]]);
const id1 = r.saveDataMap(map1);
eq(typeof id1 === 'number' && id1 >= 0, true, 'saveDataMap 返回 id，实际=' + id1);
eq(r.restoreDataMap(id1) === map1, true, 'restoreDataMap(id) 取回同一张表');
eq(r.restoreDataMap(id1), null, '**再取一次 → null**（一次性消费，上游 remove 语义）');
eq(r.restoreDataMap(9999), null, '不存在的 id → null');

// 两次 saveDataMap 得到不同 id
const a = r.saveDataMap(new Map());
const b = r.saveDataMap(new Map());
eq(a !== b, true, '两次 saveDataMap 得到不同 id（' + a + ' vs ' + b + '）');

// modifyFavourites：改写所有已登记表 + 通知所有 listener
const t1 = new Map([[1, info(1)], [2, info(2)]]);
const t2 = new Map([[1, info(1)]]);
r.saveDataMap(t1);
r.saveDataMap(t2);
const calls = [];
const l1 = { onModifyFavourites: (gid, slot) => calls.push('L1:' + gid + ':' + slot) };
const l2 = { onModifyFavourites: (gid, slot) => calls.push('L2:' + gid + ':' + slot) };
r.addListener(l1);
r.addListener(l2);
r.modifyFavourites(1, 3);
eq([t1.get(1).favoriteSlot, t2.get(1).favoriteSlot], [3, 3], 'modifyFavourites 改写**所有**已登记表里的该 gid');
eq(calls, ['L1:1:3', 'L2:1:3'], '…并按注册顺序通知所有 listener');
eq(t1.get(2).favoriteSlot, -1, '…其它 gid 不受影响');
eq(calls.indexOf('L1:2:3'), -1, '不存在的 gid 只发通知不该有的调用（仅按 gid 命中）');

// 先改数据再通知（listener 里读到的已是新值）
let seenSlot = null;
r.addListener({ onModifyFavourites: (gid) => { seenSlot = t1.get(gid) ? t1.get(gid).favoriteSlot : null; } });
r.modifyFavourites(2, 7);
eq(seenSlot, 7, '**先改数据再通知** —— listener 读到的已是新值');

// removeListener：只移除第一个匹配项
calls.length = 0;
r.removeListener(l1);
r.modifyFavourites(1, 5);
eq(calls.indexOf('L1:1:5'), -1, 'removeListener 后不再收到回调');
eq(calls.indexOf('L2:1:5') >= 0, true, '…其它 listener 仍收到');

// 重复注册不去重（上游 ArrayList.add 语义）
const r2 = new FavouriteStatusRouter();
let n = 0;
const dup = { onModifyFavourites: () => { n++; } };
r2.addListener(dup);
r2.addListener(dup);
eq(r2.getListenerCount(), 2, '**同一 listener 注册两次 → 计数 2**（不去重，照搬）');
r2.modifyFavourites(1, 1);
eq(n, 2, '…因此会收到两次回调');
r2.removeListener(dup);
eq(r2.getListenerCount(), 1, 'removeListener 只移除第一个匹配项');

// 回调里 removeListener 不破坏遍历（B 类修复：上游会 CME）
const r3 = new FavouriteStatusRouter();
const hits = [];
const selfRemoving = { onModifyFavourites: () => { hits.push('self'); r3.removeListener(selfRemoving); } };
const other = { onModifyFavourites: () => hits.push('other') };
r3.addListener(selfRemoving);
r3.addListener(other);
r3.modifyFavourites(1, 1);
eq(hits, ['self', 'other'], '回调里 removeListener：本次遍历仍走完（上游 Java 这里会抛 CME）');
eq(r3.getListenerCount(), 1, '…且自我注销已生效');

// ── ShakeDetector ──
// 注意：初始 shakeTimestamp=0，若时钟从 0 起算，第一次摇动会因 "0+500 > 0" 被当成「太近」而忽略。
// 上游用 System.currentTimeMillis()（真实纪元毫秒），永远远大于 500，所以测试基址也要取大值。
let clock = 1000000;
const shakes = [];
const det = new ShakeDetector(() => clock);
det.setOnShakeListener({ onShake: (c) => shakes.push(c) });

// 静止：gForce ≈ 1 → 不触发
eq(det.onSensorChanged(0, 0, 9.80665), false, '静止（gForce=1）→ 不触发');
// 轻晃：1.5 倍重力 → 不触发（阈值 2.7）
eq(det.onSensorChanged(0, 0, 9.80665 * 1.5), false, 'gForce=1.5 → 不触发（阈值 2.7）');
// 刚超过阈值
eq(det.onSensorChanged(0, 0, 9.80665 * 2.8), true, 'gForce=2.8 → 触发');
eq(shakes, [1], '…count=1');
// 500ms 内再摇 → 忽略
clock = 1000000 + 100;
eq(det.onSensorChanged(0, 0, 9.80665 * 2.8), false, '100ms 后再摇 → 忽略（slop 500ms）');
clock = 1000000 + 499;
eq(det.onSensorChanged(0, 0, 9.80665 * 2.8), false, '499ms → 仍忽略');
clock = 1000000 + 501;
eq(det.onSensorChanged(0, 0, 9.80665 * 2.8), true, '501ms > 500ms → 触发');
eq(shakes, [1, 2], '…count=2');

// 3s 没摇 → 计数复位
clock = 1000000 + 501 + 3001;
eq(det.onSensorChanged(0, 0, 9.80665 * 2.8), true, '3s 之后 → 触发');
eq(shakes[shakes.length - 1], 1, '…**计数复位为 1**（超过 3000ms）');

// 恰好在窗口边界：last+3000 < now 是严格小于
const det2 = new ShakeDetector(() => clock);
const s2 = [];
det2.setOnShakeListener({ onShake: (c) => s2.push(c) });
clock = 1000000;
det2.onSensorChanged(0, 0, 9.80665 * 3);
clock = 1000000 + 501;
det2.onSensorChanged(0, 0, 9.80665 * 3);
eq(s2, [1, 2], '边界前：count 累加到 2');
clock = 1000000 + 501 + 3000;   // 恰好等于 last+3000 → 条件 `last+3000 < now` 为 false → **不复位**
det2.onSensorChanged(0, 0, 9.80665 * 3);
eq(s2[s2.length - 1], 3, '**恰好在 last+3000 → 不复位**（严格小于，累加到 3）');

// listener 为 null → 不崩、不触发
const det3 = new ShakeDetector(() => clock);
eq(det3.onSensorChanged(0, 0, 100), false, 'listener=null → false（不崩）');

// 三轴都参与：x 方向也能触发
const det4 = new ShakeDetector(() => { clock += 1000; return clock; });
let xShake = 0;
det4.setOnShakeListener({ onShake: () => { xShake++; } });
eq(det4.onSensorChanged(9.80665 * 3, 0, 0), true, 'x 轴 3 倍重力 → 触发（三轴平方和）');
eq(xShake, 1, '…回调一次');

console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
process.exit(fail === 0 ? 0 : 1);
