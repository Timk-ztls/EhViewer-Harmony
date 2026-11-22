/*
 * 审计 L-07 / L-08 / L-18 的回归断言
 *
 * 三条都是「代码看着对、数据从哪来断了」，所以断言点全在**接线与可诊断性**上：
 *   L-07：FilterStore 未注入时必须可诊断（warn 一次），注入后必须真的生效
 *   L-08：isPossible / getInstance 必须存在且语义与上游一致（不可用 → null，可用 → 懒加载 + 缓存）
 *   L-18：title/uploader 为空串时必须**跳过过滤**（上游 null 语义），不能被 `'' === ''` 误过滤
 */

import { EhFilter, FilterLike, FilterStore } from '../../../ehviewer/client/EhFilter';
import { TagDatabaseIo } from '../../../ehviewer/client/EhTagDatabase';
import { EhTagDatabase } from '../../../ehviewer/client/EhTagDatabase';
import { GalleryInfo } from '../../../ehviewer/client/data/GalleryInfo';

let pass = 0;
const fails: string[] = [];
function eq(name: string, got: unknown, want: unknown): void {
  const g = JSON.stringify(got);
  const w = JSON.stringify(want);
  if (g === w) { pass++; } else { fails.push(`${name}: got ${g} want ${w}`); }
}
function ok(name: string, cond: boolean): void {
  if (cond) { pass++; } else { fails.push(name); }
}

/** 最小过滤器：enable + text。 */
class FakeFilter implements FilterLike {
  private _text: string;
  private _enable: boolean;

  private readonly _mode: number;

  constructor(text: string, enable: boolean = true, mode: number = EhFilter.MODE_TITLE) {
    this._text = text;
    this._enable = enable;
    this._mode = mode;
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
    return 0;
  }

  getMode(): number {
    return this._mode;
  }
}

/** 只提供标题/上传者两类规则的 store。 */
class FakeFilterStore implements FilterStore {
  private readonly _title: FilterLike[];
  private readonly _uploader: FilterLike[];

  constructor(title: FilterLike[], uploader: FilterLike[]) {
    this._title = title;
    this._uploader = uploader;
  }

  getAllFilter(): FilterLike[] {
    return this._title.concat(this._uploader);
  }

  addFilter(filter: FilterLike): void { }

  deleteFilter(filter: FilterLike): void { }

  triggerFilter(filter: FilterLike): void { }
}

function makeInfo(title: string, uploader: string): GalleryInfo {
  const info = new GalleryInfo();
  info.title = title;
  info.uploader = uploader;
  return info;
}

// ---------------------------------------------------------------- L-18：空串跳过过滤
{
  // 过滤器文本是空串 → 上游在 title/uploader 为 null 时**跳过**，不误杀
  const store = new FakeFilterStore([new FakeFilter('')],
    [new FakeFilter('', true, EhFilter.MODE_UPLOADER)]);
  const filter = new EhFilter(store);

  eq('title 为空串 + 过滤词为空串 → 保留（上游 null 语义）', filter.filterTitle(makeInfo('', 'x')), true);
  eq('uploader 为空串 + 过滤词为空串 → 保留', filter.filterUploader(makeInfo('t', '')), true);

  // 正常命中仍然要过滤
  const store2 = new FakeFilterStore([new FakeFilter('bad')],
    [new FakeFilter('evil', true, EhFilter.MODE_UPLOADER)]);
  const filter2 = new EhFilter(store2);
  eq('标题含 bad → 过滤', filter2.filterTitle(makeInfo('this is bad', 'u')), false);
  eq('标题不含 → 保留', filter2.filterTitle(makeInfo('good', 'u')), true);
  eq('上传者相等 → 过滤', filter2.filterUploader(makeInfo('t', 'evil')), false);
  eq('上传者不等 → 保留', filter2.filterUploader(makeInfo('t', 'good')), true);

  // info 为 null → false（上游同）
  eq('info=null → filterTitle false', filter2.filterTitle(null), false);
  eq('info=null → filterUploader false', filter2.filterUploader(null), false);

  // 禁用的规则不生效
  const store3 = new FakeFilterStore([new FakeFilter('bad', false)], []);
  const filter3 = new EhFilter(store3);
  eq('禁用的标题规则不生效', filter3.filterTitle(makeInfo('bad', 'u')), true);
}

// ---------------------------------------------------------------- L-07：store 注入后规则生效
{
  // 注入一个真的含规则的 store，验证「过滤器是有数据的」而不是恒空
  const store = new FakeFilterStore([new FakeFilter('spoiler')],
    [new FakeFilter('artistX', true, EhFilter.MODE_UPLOADER)]);
  const filter = new EhFilter(store);
  eq('注入后标题规则生效', filter.filterTitle(makeInfo('spoiler ahead', 'u')), false);
  eq('注入后上传者规则生效', filter.filterUploader(makeInfo('t', 'artistX')), false);
  // needTags：两类规则都不含标签 → false（等价上游「没有标签过滤」）
  eq('无标签规则时 needTags 为 false', filter.needTags(), false);
}

// ---------------------------------------------------------------- L-08：isPossible / getInstance
{
  /** 造一个 tag 库字节：4 字节大端长度 + 正文（正文格式见 EhTagDatabase 构造）。 */
  function makeTagData(rows: string[]): ArrayBuffer {
    const body = rows.join('\n');
    const bodyBytes = encodeUtf8(body);
    const out = new Uint8Array(4 + bodyBytes.length);
    const dv = new DataView(out.buffer);
    dv.setUint32(0, bodyBytes.length, false);   // 大端
    out.set(bodyBytes, 4);
    return out.buffer;
  }

  function encodeUtf8(s: string): Uint8Array {
    const out: number[] = [];
    for (let i = 0; i < s.length; i++) {
      const c = s.charCodeAt(i);
      if (c < 0x80) {
        out.push(c);
      } else if (c < 0x800) {
        out.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f));
      } else {
        out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
      }
    }
    return new Uint8Array(out);
  }

  const data = makeTagData(['artist:abc\r|YXJ0aXN0', 'female:girl\r|Z2lybA==']);

  const ioOk: TagDatabaseIo = {
    getMetadata: (): string[] | null => ['sha1', 'http://S/1', 'db.dat', 'http://S/2'],
    readData: (name: string): ArrayBuffer | null => (name === 'db.dat' ? data : null)
  };
  const ioNone: TagDatabaseIo = {
    getMetadata: (): string[] | null => null,
    readData: (): ArrayBuffer | null => null
  };
  const ioShort: TagDatabaseIo = {
    getMetadata: (): string[] | null => ['only', 'two'],
    readData: (): ArrayBuffer | null => null
  };
  const ioNoFile: TagDatabaseIo = {
    getMetadata: (): string[] | null => ['sha1', 'u1', 'missing.dat', 'u2'],
    readData: (): ArrayBuffer | null => null
  };

  eq('元数据缺失 → isPossible false', EhTagDatabase.isPossible(ioNone), false);
  eq('元数据只有 2 项 → isPossible false（上游要求 4 项）', EhTagDatabase.isPossible(ioShort), false);
  eq('元数据齐全 → isPossible true', EhTagDatabase.isPossible(ioOk), true);

  EhTagDatabase.clearInstance();
  eq('不可用 → getInstance 返回 null', EhTagDatabase.getInstance(ioNone), null);
  eq('数据文件缺失 → getInstance 返回 null', EhTagDatabase.getInstance(ioNoFile), null);

  EhTagDatabase.clearInstance();
  const db = EhTagDatabase.getInstance(ioOk);
  ok('可用 → getInstance 返回实例', db !== null);
  ok('第二次调用命中缓存（引用相等）', EhTagDatabase.getInstance(ioOk) === db);
  // 缓存命中时不应再读文件：用一个计数 io 验证
  let reads = 0;
  const ioCount: TagDatabaseIo = {
    getMetadata: (): string[] | null => ['sha1', 'u1', 'db.dat', 'u2'],
    readData: (name: string): ArrayBuffer | null => {
      reads++;
      return data;
    }
  };
  EhTagDatabase.clearInstance();
  EhTagDatabase.getInstance(ioCount);
  EhTagDatabase.getInstance(ioCount);
  eq('两次 getInstance 只读一次数据（懒加载 + 缓存）', reads, 1);

  // 损坏数据 → null 且不抛
  const ioBad: TagDatabaseIo = {
    getMetadata: (): string[] | null => ['sha1', 'u1', 'bad.dat', 'u2'],
    readData: (): ArrayBuffer | null => new ArrayBuffer(2)   // 少于 4 字节
  };
  EhTagDatabase.clearInstance();
  eq('数据损坏 → 返回 null（不抛）', EhTagDatabase.getInstance(ioBad), null);
}

console.log(`\n=== 结果：${pass} passed, ${fails.length} failed ===`);
if (fails.length > 0) {
  for (const f of fails) {
    console.log('  FAIL ' + f);
  }
  throw new Error('审计 L-07/L-08/L-18 断言失败：' + fails.length);
}
