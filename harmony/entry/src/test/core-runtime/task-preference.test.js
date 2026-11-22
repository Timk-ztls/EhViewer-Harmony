// TaskPreference 纯逻辑断言：进度归一化 + task id 生命周期
global.Observed = (target) => target;
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out9');
const base = path.join(OUT, '..');
const { TaskPreference } = require(path.join(OUT, 'TaskPreference.js'));
const { EhApplication } = require(path.join(base, 'EhApplication.js'));

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};

// ── normalizeProgress（上游 onProgressUpdate 的数值语义）──
const p1 = TaskPreference.normalizeProgress(5, 10);
eq([p1.indeterminate, p1.max, p1.progress], [false, 10, 5], '正常：5/10 → indeterminate=false, max=10, progress=5');

const p2 = TaskPreference.normalizeProgress(-3, 10);
eq([p2.indeterminate, p2.max, p2.progress], [false, 10, 0], 'current<0 → clamp 到 0（上游 if (current < 0) current = 0）');

const p3 = TaskPreference.normalizeProgress(99, 10);
eq([p3.indeterminate, p3.max, p3.progress], [false, 10, 10], 'current>total → clamp 到 total（上游 if (current > total)）');

const p4 = TaskPreference.normalizeProgress(5, 0);
eq(p4.indeterminate, true, 'total=0 → indeterminate=true（上游 total<=0 分支）');

const p5 = TaskPreference.normalizeProgress(5, -1);
eq(p5.indeterminate, true, 'total<0 → indeterminate=true');

const p6 = TaskPreference.normalizeProgress(0, 0);
eq(p6.indeterminate, true, '0/0 → indeterminate=true（不除零、不崩）');

// ── startTask / restoreTask / finishTask（对应 putGlobalStuff + SavedState.asyncTaskId）──
EhApplication.initialize();
const task = { name: 'demo-task' };
const id = TaskPreference.startTask(task);
eq(id >= 0, true, 'startTask 返回有效 id');
eq(TaskPreference.restoreTask(id) === task, true, 'restoreTask(id) 找回同一个实例（对应 onRestoreInstanceState）');

TaskPreference.finishTask(task);
eq(TaskPreference.restoreTask(id), null, 'finishTask 后 restoreTask → null（对应 removeGlobalStuff）');

eq(TaskPreference.restoreTask(-1), null, 'restoreTask(-1) → null（INVALID_ID）');

async function main() {
// ── run：执行 → onPostExecute → 清理 ──
const calls = [];
const runner = {
  doInBackground: async () => { calls.push('bg'); return 'R'; },
  onProgress: () => {},
  onPostExecute: (o) => { calls.push('post:' + o); },
  onCancelled: () => { calls.push('cancel'); },
};
await new Promise((resolve) => {
  TaskPreference.run(runner, () => { calls.push('done'); resolve(); });
});
eq(calls, ['bg', 'post:R', 'done'], 'run：doInBackground → onPostExecute → onDone（顺序正确）');

// ── run：抛错走 onCancelled，且照样清理 ──
const calls2 = [];
const runner2 = {
  doInBackground: async () => { throw new Error('boom'); },
  onProgress: () => {},
  onPostExecute: () => { calls2.push('post'); },
  onCancelled: () => { calls2.push('cancel'); },
};
await new Promise((resolve) => {
  TaskPreference.run(runner2, () => { calls2.push('done'); resolve(); });
});
eq(calls2, ['cancel', 'done'], 'run：doInBackground 抛错 → onCancelled（不调 onPostExecute），仍执行 onDone');

console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
process.exit(fail === 0 ? 0 : 1);
}

main();
