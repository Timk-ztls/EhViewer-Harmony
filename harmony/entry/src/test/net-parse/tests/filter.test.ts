// EhFilter 测试（构造数据）
//
// 重点验证「返回值语义容易搞反」这件事：filterXxx 返回 **true = 保留**。
// 以及四条易错规则：标题 contains/小写、上传者 equals/**区分大小写**、
// 标签 namespace 只在两侧都有时比较、命名空间匹配要求 tag 含 ':'。

import { EhFilter, FilterLike, FilterStore } from '../EhFilter';
import { GalleryInfo } from './GalleryInfo';

let pass = 0;
let fail = 0;
const failures: string[] = [];

function eq(name: string, actual: unknown, expected: unknown): void {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a === e) {
    pass++;
  } else {
    fail++;
    failures.push(`${name}\n    actual  = ${a}\n    expected= ${e}`);
  }
}

function ok(name: string, cond: boolean): void {
  if (cond) {
    pass++;
  } else {
    fail++;
    failures.push(name);
  }
}

class FakeFilter implements FilterLike {
  private _mode: number;
  private _text: string;
  private _enable: boolean = true;
  private _id: number;

  constructor(id: number, mode: number, text: string) {
    this._id = id;
    this._mode = mode;
    this._text = text;
  }

  getMode(): number {
    return this._mode;
  }

  getText(): string {
    return this._text;
  }

  setText(text: string): void {
    this._text = text;
  }

  isEnable(): boolean {
    return this._enable;
  }

  setEnable(enable: boolean): void {
    this._enable = enable;
  }

  getId(): number {
    return this._id;
  }
}

class FakeStore implements FilterStore {
  all: FilterLike[] = [];
  added: FilterLike[] = [];
  deleted: FilterLike[] = [];
  triggered: FilterLike[] = [];

  getAllFilter(): FilterLike[] {
    return this.all;
  }

  addFilter(f: FilterLike): void {
    this.added.push(f);
  }

  deleteFilter(f: FilterLike): void {
    this.deleted.push(f);
  }

  triggerFilter(f: FilterLike): void {
    this.triggered.push(f);
  }
}

function gi(title: string, uploader: string, tags: string[] | null): GalleryInfo {
  const g = new GalleryInfo();
  g.title = title;
  g.uploader = uploader;
  g.simpleTags = tags;
  return g;
}

// ---------- 加载与四类分桶 ----------
{
  const store = new FakeStore();
  store.all = [
    new FakeFilter(1, EhFilter.MODE_TITLE, 'Yaoi'),
    new FakeFilter(2, EhFilter.MODE_UPLOADER, 'SomeUploader'),
    new FakeFilter(3, EhFilter.MODE_TAG, 'Female:Yaoi'),
    new FakeFilter(4, EhFilter.MODE_TAG_NAMESPACE, 'Scat'),
    new FakeFilter(5, 99, 'unknown-mode')
  ];
  const f = new EhFilter(store);
  eq('标题桶 1 条', f.getTitleFilterList().length, 1);
  eq('上传者桶 1 条', f.getUploaderFilterList().length, 1);
  eq('标签桶 1 条', f.getTagFilterList().length, 1);
  eq('命名空间桶 1 条', f.getTagNamespaceFilterList().length, 1);
  eq('标题文本已转小写', f.getTitleFilterList()[0].getText(), 'yaoi');
  eq('标签文本已转小写', f.getTagFilterList()[0].getText(), 'female:yaoi');
  eq('上传者文本**不**转小写', f.getUploaderFilterList()[0].getText(), 'SomeUploader');
  eq('未知 mode 被丢弃', f.getTitleFilterList().length + f.getUploaderFilterList().length +
    f.getTagFilterList().length + f.getTagNamespaceFilterList().length, 4);
}

// ---------- filterTitle：true = 保留 ----------
{
  const store = new FakeStore();
  store.all = [new FakeFilter(1, EhFilter.MODE_TITLE, 'Yaoi')];
  const f = new EhFilter(store);
  eq('标题命中 → 过滤掉（false）', f.filterTitle(gi('Some YAOI thing', 'u', null)), false);
  eq('标题不命中 → 保留（true）', f.filterTitle(gi('Normal', 'u', null)), true);
  eq('info 为 null → false', f.filterTitle(null), false);

  // disable 后不再过滤
  f.getTitleFilterList()[0].setEnable(false);
  eq('过滤器 disabled → 保留', f.filterTitle(gi('Some YAOI thing', 'u', null)), true);
}

// ---------- filterUploader：equals + 区分大小写 ----------
{
  const store = new FakeStore();
  store.all = [new FakeFilter(1, EhFilter.MODE_UPLOADER, 'SomeUploader')];
  const f = new EhFilter(store);
  eq('上传者全等 → 过滤', f.filterUploader(gi('t', 'SomeUploader', null)), false);
  eq('上传者大小写不同 → 保留（上游区分大小写）', f.filterUploader(gi('t', 'someuploader', null)), true);
  eq('上传者包含但不等 → 保留', f.filterUploader(gi('t', 'SomeUploaderX', null)), true);
}

// ---------- filterTag：namespace 两侧都有才比较 ----------
{
  const store = new FakeStore();
  store.all = [new FakeFilter(1, EhFilter.MODE_TAG, 'female:yaoi')];
  const f = new EhFilter(store);
  eq('同 namespace + 同 name → 过滤', f.filterTag(gi('t', 'u', ['female:yaoi'])), false);
  eq('namespace 不同 → 保留', f.filterTag(gi('t', 'u', ['male:yaoi'])), true);

  // 过滤器只有 name（无 namespace）→ 任一 namespace 的同名 tag 都命中
  const store2 = new FakeStore();
  store2.all = [new FakeFilter(1, EhFilter.MODE_TAG, 'yaoi')];
  const f2 = new EhFilter(store2);
  eq('过滤器无 namespace → male:yaoi 也命中', f2.filterTag(gi('t', 'u', ['male:yaoi'])), false);

  // tag 无 namespace 而过滤器有 → 不比较 namespace，只比 name
  const store3 = new FakeStore();
  store3.all = [new FakeFilter(1, EhFilter.MODE_TAG, 'female:yaoi')];
  const f3 = new EhFilter(store3);
  eq('tag 无 namespace、过滤器有 → 仍按 name 命中', f3.filterTag(gi('t', 'u', ['yaoi'])), false);
  eq('tag 为 null → 保留', f3.filterTag(gi('t', 'u', null)), true);

  // matchTag 纯函数边界
  eq('matchTag(tag, null)', EhFilter.matchTag('a:b', null), false);
  eq('matchTag(null, filter)', EhFilter.matchTag(null, 'a'), false);
}

// ---------- filterTagNamespace ----------
{
  const store = new FakeStore();
  store.all = [new FakeFilter(1, EhFilter.MODE_TAG_NAMESPACE, 'Scat')];
  const f = new EhFilter(store);
  eq('命名空间命中（已小写化）→ 过滤', f.filterTagNamespace(gi('t', 'u', ['scat:anything'])), false);
  eq('命名空间不同 → 保留', f.filterTagNamespace(gi('t', 'u', ['female:x'])), true);
  eq('tag 无冒号 → 不匹配（保留）', f.filterTagNamespace(gi('t', 'u', ['scat'])), true);
  eq('matchTagNamespace 无冒号', EhFilter.matchTagNamespace('scat', 'scat'), false);
  eq('matchTagNamespace 有冒号', EhFilter.matchTagNamespace('scat:x', 'scat'), true);
}

// ---------- needTags ----------
{
  const store = new FakeStore();
  const f0 = new EhFilter(store);
  eq('无标签过滤器 → needTags false', f0.needTags(), false);

  const store2 = new FakeStore();
  store2.all = [new FakeFilter(1, EhFilter.MODE_TITLE, 'x')];
  eq('只有标题过滤器 → needTags false', new EhFilter(store2).needTags(), false);

  const store3 = new FakeStore();
  store3.all = [new FakeFilter(1, EhFilter.MODE_TAG_NAMESPACE, 'x')];
  eq('有命名空间过滤器 → needTags true', new EhFilter(store3).needTags(), true);
}

// ---------- add / delete / trigger ----------
{
  const store = new FakeStore();
  const f = new EhFilter(store);
  const nf = new FakeFilter(9, EhFilter.MODE_TITLE, 'ABC');
  f.addFilter(nf, store);
  eq('addFilter 写库一次', store.added.length, 1);
  ok('addFilter 置 enable', nf.isEnable());
  eq('addFilter 后文本小写', nf.getText(), 'abc');
  eq('addFilter 内存表 +1', f.getTitleFilterList().length, 1);

  f.triggerFilter(nf, store);
  eq('triggerFilter 调库', store.triggered.length, 1);

  f.deleteFilter(nf, store);
  eq('deleteFilter 调库', store.deleted.length, 1);
  eq('deleteFilter 内存表 -1', f.getTitleFilterList().length, 0);
}

console.log(`\n=== 结果：${pass} passed, ${fail} failed ===`);
if (fail > 0) {
  for (const f of failures) {
    console.log('  FAIL ' + f);
  }
  throw new Error('EhFilter 断言失败：' + fail);
}
