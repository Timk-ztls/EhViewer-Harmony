// 三个 DialogBuilder 的声明式语义：初始值 / 输入读取 / IME 分支 / 列表点击顺序
global.Observed = (target) => target;
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out11');
const { CheckBoxDialogSpec, EditTextDialogSpec, ListCheckBoxDialogSpec } =
  require(path.join(OUT, 'app', 'DialogSpecs.js'));

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};

// ── S0002 CheckBoxDialogBuilder ──
{
  const s = new CheckBoxDialogSpec('确定删除？', '不再提示', true);
  eq(s.message, '确定删除？', 'message 透传');
  eq(s.checkText, '不再提示', 'checkText 透传');
  eq(s.isChecked(), true, '初始 checked=true → isChecked() 为 true');
  s.checked = false;                       // 等价用户点了复选框
  eq(s.isChecked(), false, '**用户取消勾选后可读回 false**（对应 mCheckBox.isChecked）');
  const s2 = new CheckBoxDialogSpec(null, null, false);
  eq([s2.message, s2.checkText, s2.isChecked()], [null, null, false], '三项都为 null/false 时不崩');
}

// ── S0003 EditTextDialogBuilder ──
{
  const s = new EditTextDialogSpec('abc', '请输入');
  eq([s.getText(), s.hint, s.error], ['abc', '请输入', null], "初始 text/hint/error('abc'/hint/null)");
  s.text = 'abcd';
  eq(s.getText(), 'abcd', '**用户输入后可读回新文本**');
  s.setError('不能为空');
  eq(s.error, '不能为空', 'setError 写入 error');
  s.setError(null);
  eq(s.error, null, 'setError(null) 清除 error');

  // null 文本 → 空串（上游 setText(null) 等价于清空，text.toString() 得 ""）
  const s2 = new EditTextDialogSpec(null, null);
  eq(s2.getText(), '', "text=null → getText() 返回 ''（对应 editText.setText(null)）");

  // 光标置尾
  eq(s.getSelectionEnd(), 4, '**光标置尾**：4 字符文本 → selectionEnd=4（不是 0）');
  eq(new EditTextDialogSpec('', null).getSelectionEnd(), 0, '空文本 → 0');

  // IME：event != null && ready 才触发确定
  const s3 = new EditTextDialogSpec('x', null);
  eq(s3.onEditorAction(true), false, '**未 create（ready=false）时 IME 事件不触发确定**');
  s3.markReady();
  eq(s3.onEditorAction(true), true, 'create 后 + event 非空 → **消费事件（=点确定）**');
  eq(s3.onEditorAction(false), false, 'create 后但 **event 为 null** → 不消费（交回框架默认）');
  // 与上游逐字一致的两个前置条件是 AND
  const s4 = new EditTextDialogSpec('y', null);
  eq([s4.onEditorAction(false), s4.ready], [false, false], '未 ready 且无 event → false');
}

// ── S0004 ListCheckBoxDialogBuilder ──
{
  const items = ['A', 'B', 'C'];
  const s = new ListCheckBoxDialogSpec(items, '记住选择', false);
  eq(s.items, items, 'items 透传');
  eq([s.checkText, s.isChecked()], ['记住选择', false], 'checkText / isChecked 初始值');
  eq(s.items.length, 3, '三项');

  // items == null → 抛错（上游 items!! 会 NPE）
  let threw = false;
  try { new ListCheckBoxDialogSpec(null, null, false); } catch (e) { threw = true; }
  eq(threw, true, 'items=null → 抛错（上游 items!! 的 NPE，提前暴露）');

  // 点击顺序：先 listener 再 dismiss；listener 里读到的 checked 是**点击瞬间**的值
  const seen = [];
  s.checked = true;
  s.markReady();
  const listener = {
    onItemClick: (pos) => { seen.push('listener:' + pos + ':checked=' + s.isChecked()); },
  };
  eq(s.onItemClick(1, listener), true, '点击合法项 → true');
  eq(seen, ['listener:1:checked=true'], '**listener 先被调用**，且此时 checked 仍为 true');
  eq(s.ready, false, '**回调之后才 dismiss**（ready 变 false）');

  // 越界不回调
  const seen2 = [];
  const s2 = new ListCheckBoxDialogSpec(['X'], null, false);
  s2.markReady();
  eq(s2.onItemClick(5, { onItemClick: (p) => seen2.push(p) }), false, '越界 position → false');
  eq(seen2.length, 0, '…不回调 listener');

  // listener 为 null 也不崩（上游 `listener?.onItemClick`）
  const s3 = new ListCheckBoxDialogSpec(['X'], null, false);
  s3.markReady();
  eq(s3.onItemClick(0, null), true, 'listener=null → 不崩，仍算消费');
  eq(s3.ready, false, '…仍会 dismiss');

  // 未 ready 时点击不崩（B 类修复：上游这里 mDialog!! 会 NPE）
  const s4 = new ListCheckBoxDialogSpec(['X'], null, false);
  let crashed = false;
  try { s4.onItemClick(0, null); } catch (e) { crashed = true; }
  eq(crashed, false, '**未 ready 时点击不崩**（上游 mDialog!! 会 NPE）');
}

console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
process.exit(fail === 0 ? 0 : 1);
