// ClipboardUtil 编码链路怪癖 + PVLock 计数信号量语义
global.Observed = (target) => target;
const path = require('path');
const zlib = require('zlib');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out11');
const { ClipboardUtil, ClipboardUrlTarget } = require(path.join(OUT, 'ehviewer', 'util', 'ClipboardUtil.js'));
const { PVLock } = require(path.join(OUT, 'lib', 'yorozuya', 'thread', 'PVLock.js'));

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};

// 真实 gzip + Base64.DEFAULT（76 列换行）—— 与 GZIPUtils 同一实现口径
const compress = async (s) => zlib.gzipSync(Buffer.from(s, 'utf8')).toString('base64')
  .replace(/(.{76})/g, '$1\n');
const uncompress = async (s) => {
  if (s === null) return null;
  try { return zlib.gunzipSync(Buffer.from(s.replace(/\s/g, ''), 'base64')).toString('utf8'); }
  catch (e) { return null; }
};
const parseJson = (s) => {
  try {
    const o = JSON.parse(s);
    const m = new Map();
    Object.keys(o).forEach((k) => m.set(k, o[k]));
    return m;
  } catch (e) { return null; }
};
const mkClip = () => {
  const st = { text: null, primary: null, has: false, reads: 0 };
  return {
    st,
    setText: (t) => { st.text = t; },
    setPrimaryClipText: (t) => { st.primary = t; st.has = t !== '' && t !== null && t !== 'null'; },
    hasText: () => { st.reads++; return st.has; },
    getText: () => (st.has ? st.primary : null),
  };
};

// ── 不变式：defaultInfo 与 REDUCED_KEYS 必须对应（否则 putAll 会覆盖真实数据）──
eq(ClipboardUtil.findDefaultInfoViolations(), ['defaultInfo 有未删除键: simpleTags'], '唯一违规就是已知的 simpleTags（上游缺陷，照搬；列出它 = 记录我们已知）');
eq(ClipboardUtil.REDUCED_KEYS.length, 10, 'reduceString 删 10 个字段');

// ── reduceJson：只留真实数据 ──
{
  const info = new Map([
    ['gid', 12345], ['token', 'abc'], ['title', 'T'], ['titleJpn', 'TJ'],
    ['favoriteName', 'F'], ['favoriteSlot', 3], ['pages', 20], ['rated', true],
    ['simpleTags', 'x'], ['thumbWidth', 10], ['thumbHeight', 20],
    ['spanSize', 2], ['spanIndex', 1], ['spanGroupIndex', 0], ['time', 111],
  ]);
  const reduced = ClipboardUtil.reduceJson(info);
  eq(reduced.has('gid'), true, 'reduceJson 保留 gid');
  eq(reduced.has('title'), true, '…保留 title');
  const removed = ['favoriteName', 'favoriteSlot', 'pages', 'rated', 'simpleTags',
    'thumbWidth', 'thumbHeight', 'spanSize', 'spanIndex', 'spanGroupIndex', 'time']
    .filter((k) => !reduced.has(k));
  eq(removed.length, 10, '**10 个字段被删**（REDUCED_KEYS 里已含 time，不重复计）');
  eq(reduced.size, 5, '剩 5 个字段（gid/token/title/titleJpn/simpleTags）');
}

// ── expandJson：补回默认值 + time（**不覆盖已有值**）──
{
  const partial = new Map([['gid', 1], ['favoriteSlot', 7]]);   // favoriteSlot 是"已有值"
  const out = ClipboardUtil.expandJson(partial, 999);
  eq(out.get('favoriteSlot'), 7, '**putAll 不覆盖已存在的键**（favoriteSlot=7 保留，不是 -2）');
  eq(out.get('pages'), 0, '缺失的 pages → 默认 0');
  eq(out.get('rated'), false, '缺失的 rated → 默认 false');
  eq(out.get('favoriteName'), null, '缺失的 favoriteName → 默认 null');
  eq(out.get('time'), 999, 'time 被设为 now');
}

// ── copy：**setText 用 trim、setPrimaryClip 用原文**（上游怪癖）──
(async () => {
  {
    const clip = mkClip();
    const info = new Map([['gid', 1], ['title', 'T']]);
    const ok = await ClipboardUtil.copy(info, clip, async (s) => '  ' + s + '  ');
    eq(ok, true, 'copy 成功 → true');
    eq(clip.st.text, '{"gid":1,"title":"T"}', '**setText 收到 trim 后的文本**');
    eq(clip.st.primary, '  {"gid":1,"title":"T"}  ', '**setPrimaryClip 收到未 trim 的原文**');
    eq(clip.st.text !== clip.st.primary, true, '…两者确实不同（这正是上游的写法，不能统一）');
  }
  // 空内容 → false 且不写
  {
    const clip = mkClip();
    const ok = await ClipboardUtil.copy(new Map([['gid', 1]]), clip, async () => '');
    eq(ok, false, "压缩结果为空串 → false（上游 !TextUtils.isEmpty 判断）");
    eq(clip.st.primary, '', '…没有写入内容');
    eq(clip.st.text, null, '…但 clearClipboard 仍执行了 setText(null)');
  }
  // copyText 不 trim
  {
    const clip = mkClip();
    eq(ClipboardUtil.copyText('  abc  ', clip), true, 'copyText 非空 → true');
    eq(clip.st.primary, '  abc  ', '**copyText 不 trim**（上游也没 trim）');
    eq(ClipboardUtil.copyText('', mkClip()), false, 'copyText 空串 → false');
    eq(ClipboardUtil.copyText(null, mkClip()), false, 'copyText null → false');
  }

  // ── 端到端往返（copy → 剪贴板 → getGalleryInfoFromClip）──
  {
    const clip = mkClip();
    const info = new Map([['gid', 42], ['token', 'deadbeef'], ['title', 'Hello'],
      ['favoriteName', 'X'], ['pages', 99], ['rated', true]]);
    await ClipboardUtil.copy(info, clip, compress);
    // 模拟"外部把 primary 设为剪贴板内容"：copy 后 primary 已是未 trim 的压缩串
    clip.st.has = true;
    const back = await ClipboardUtil.getGalleryInfoFromClip(clip, uncompress, parseJson, () => 777);
    eq(back !== null, true, '往返：解出对象');
    eq(back.get('gid'), 42, '…gid 保留');
    eq(back.get('token'), 'deadbeef', '…token 保留');
    eq(back.get('title'), 'Hello', '…title 保留');
    eq(back.get('pages'), 0, '**…pages 被压掉，还原成默认 0**（不是 99）');
    eq(back.get('rated'), false, '…rated 还原成默认 false');
    eq(back.get('favoriteName'), null, '…favoriteName 还原成默认 null');
    eq(back.get('time'), 777, '…time 设为 now（**原始 time 丢失**，这是压缩换来的代价）');
    eq(clip.st.text, null, '读完调用了 setText(null)');
    eq(clip.st.has, true, '**但主剪贴其实没被清掉**（上游 clearClipboard 把现有内容原样重设，等于空操作）');
  }

  // 解压失败：剪贴板仍被清空（顺序照搬）
  {
    const clip = mkClip();
    clip.st.primary = 'not-gzip'; clip.st.has = true;
    const r = await ClipboardUtil.getGalleryInfoFromClip(clip, uncompress, parseJson, () => 1);
    eq(r, null, '解压失败 → null');
    eq(clip.st.text, null, '…setText(null) 已调用（先 uncompress 再 clearClipboard 的顺序照搬）');
  }

  // getClipContent：无内容返回空串
  {
    const clip = mkClip();
    eq(ClipboardUtil.getClipContent(clip), '', '无内容 → ""（不是 null）');
    clip.st.primary = 'x'; clip.st.has = true;
    eq(ClipboardUtil.getClipContent(clip), 'x', '有内容 → 原文');
  }

  // ── javaTrim：只裁 <= U+0020 ──
  eq(ClipboardUtil.javaTrim('  a b  '), 'a b', 'javaTrim 裁首尾空格、保留中间');
  eq(ClipboardUtil.javaTrim('\t\n x \r'), 'x', 'javaTrim 裁制表/换行');
  eq(ClipboardUtil.javaTrim('\u00A0x\u00A0'), '\u00A0x\u00A0', '**javaTrim 不裁 U+00A0**（Java trim 语义，与 JS trim 不同）');

  // ── parseClipboardUrl：先详情、后阅读 ──
  {
    const d = ClipboardUtil.parseClipboardUrl('https://e-hentai.org/g/123/abcdef1234/');
    eq(d !== null && d.target === ClipboardUrlTarget.DETAIL, true, '详情页 URL → DETAIL');
    eq(d.gid, 123, '…gid=123');
    eq(d.token, 'abcdef1234', '…token');
    const p = ClipboardUtil.parseClipboardUrl('https://e-hentai.org/s/abcdef1234/123-5');
    eq(p !== null, true, '阅读页 URL 能解析（实际=' + JSON.stringify(p) + '）');
    eq(ClipboardUtil.parseClipboardUrl('not a url'), null, '非 URL → null');
    eq(ClipboardUtil.parseClipboardUrl(null), null, 'null → null');
  }

  // ── PVLock ──
  {
    // 初始配额 2：前两次 p() 立即完成
    const lock = new PVLock(2);
    eq(lock.getCount(), 2, 'new PVLock(2) → count=2');
    await lock.p();
    eq(lock.getCount(), 1, '第一次 p() 后 count=1');
    await lock.p();
    eq(lock.getCount(), 0, '第二次 p() 后 count=0');
    eq(lock.getWaiterCount(), 0, '…都立即完成，无等待者');

    // 第三次 p() 必须等 v()
    let thirdDone = false;
    const third = lock.p().then(() => { thirdDone = true; });
    await new Promise((r) => setTimeout(r, 10));
    eq(thirdDone, false, '**配额耗尽后 p() 挂起**（对应上游 wait()）');
    eq(lock.getWaiterCount(), 1, '…队列里有 1 个等待者');
    lock.v();
    await third;
    eq(thirdDone, true, 'v() 后挂起的 p() 完成');
    eq(lock.getCount(), 0, '…**移交语义：计数器仍为 0**（不是先 ++ 再 --）');

    // 多余配额累积
    const lock2 = new PVLock(0);
    lock2.v(); lock2.v(); lock2.v();
    eq(lock2.getCount(), 3, 'v() 有多余配额时累积 → count=3');
    await lock2.p();
    eq(lock2.getCount(), 2, '…之后 p() 立即消耗一个');

    // FIFO 顺序
    const lock3 = new PVLock(0);
    const order = [];
    const p1 = lock3.p().then(() => order.push(1));
    const p2 = lock3.p().then(() => order.push(2));
    const p3 = lock3.p().then(() => order.push(3));
    eq(lock3.getWaiterCount(), 3, '三个等待者入队');
    lock3.v(); await new Promise((r) => setTimeout(r, 5));
    eq(order, [1], 'v() 唤醒**第一个**（FIFO）');
    lock3.v(); await new Promise((r) => setTimeout(r, 5));
    eq(order, [1, 2], '再 v() 唤醒第二个');
    lock3.v(); await Promise.all([p1, p2, p3]);
    eq(order, [1, 2, 3], '三个都按 FIFO 完成');

    // new PVLock(0) → 第一次 p() 必须等
    const lock4 = new PVLock(0);
    let done = false;
    lock4.p().then(() => { done = true; });
    await new Promise((r) => setTimeout(r, 5));
    eq(done, false, 'new PVLock(0) 的第一次 p() 必挂起');
    lock4.v();
    await new Promise((r) => setTimeout(r, 5));
    eq(done, true, '…v() 后完成');
  }

  console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
  process.exit(fail === 0 ? 0 : 1);
})();
