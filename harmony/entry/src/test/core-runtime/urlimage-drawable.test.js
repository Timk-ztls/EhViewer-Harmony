// URLImageGetter 编排契约 + DrawableManager 失败语义
global.Observed = (target) => target;
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out10');
const { URLImageGetter } = require(path.join(OUT, 'text', 'URLImageGetter.js'));

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};

(async () => {
  // ── 顺序：先建 unikery，再 load（load 内部会回调 unikery）──
  const order = [];
  const getter = new URLImageGetter(() => {
    const u = { load: (url) => order.push('load:' + url) };
    order.push('create');
    return u;
  });
  const d = getter.getDrawable('https://e/x.png');
  eq(order, ['create', 'load:https://e/x.png'], 'getDrawable：先 createUnikery 再 load（顺序不能反）');
  eq(typeof d.load, 'function', '返回值是 unikery（可继续 load）');

  // ── 每次调用都新建实例（上游每次 new UnikeryDrawable）──
  const made = [];
  const g2 = new URLImageGetter(() => { const u = { load: () => {} }; made.push(u); return u; });
  const a = g2.getDrawable('u1');
  const b = g2.getDrawable('u2');
  eq(a !== b, true, '两次 getDrawable 返回不同实例（每次新建，对应上游 new UnikeryDrawable）');
  eq(made.length, 2, '…createUnikery 被调用 2 次');

  // ── source 为空串也照传（不判空，与上游一致）──
  const got = [];
  const g3 = new URLImageGetter(() => ({ load: (u) => got.push(u) }));
  g3.getDrawable('');
  eq(got, [''], '空 source 也传下去（上游不判空，判空会改变失败路径）');

  // ── DrawableManager：resMgr 为 null → null（不崩）──
  const { DrawableManager } = require(path.join(OUT, 'util', 'DrawableManager.js'));
  eq(await DrawableManager.getVectorDrawable(null, 1), null, 'DrawableManager: resMgr=null → null（上游 Drawable? 语义）');

  console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
  process.exit(fail === 0 ? 0 : 1);
})();
