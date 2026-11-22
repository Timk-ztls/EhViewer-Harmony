/*
 * `EhDbFilterStore` —— `FilterStore`（**同步接口**）到 `EhDB`（**异步 API**）的适配器。
 *
 * 上游 `EhFilter` 内存持有过滤列表，DB 写入异步化（通过 `EhDB.serial` FIFO 串行落库）：
 *   addFilter     → `filter.enable = true` → `EhDB.addFilter`（并回写数据库生成的 id）→ 进内存列表
 *   deleteFilter  → `EhDB.deleteFilter` → 从内存列表移除
 *   triggerFilter → 内存翻转 enable，`EhDB.triggerFilter` 串行翻转持久化实体并更新库
 *   getAllFilter  → 直接读内存；未加载时触发 `reload()`
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { EhFilter, FilterLike, FilterStore } from '../client/EhFilter';
import { Filter } from '../dao/Filter';
import { EhDB } from '../EhDB';

const DOMAIN: number = 0x0E5D;
const TAG: string = 'EhDbFilterStore';

/**
 * `FilterLike` 的内存实现（包装持久化实体 `Filter`）。
 *
 * 为什么包一层：`FilterLike.getId()` 返回 `number`（非空），而 `Filter.getId()` 返回 `number | null`
 * → `Filter` 不满足 `FilterLike`。这里用 `id = -1` 表示"尚未拿到真实 id"，并持有同一个
 * `Filter` 实体以配合 `EhDB.serial` 在 FIFO 队列里传递插入生成的自增 id 与 enable 翻转状态。
 */
class FilterRow implements FilterLike {
  private mode: number;
  private text: string;
  private enable: boolean;
  private id: number;
  private entity: Filter | null = null;

  constructor(mode: number, text: string, enable: boolean, id: number, entity: Filter | null = null) {
    this.mode = mode;
    this.text = text;
    this.enable = enable;
    this.id = id;
    this.entity = entity;
  }

  static fromEntity(e: Filter): FilterRow {
    const text: string | null = e.getText();
    const enable: boolean | null = e.getEnable();
    const id: number | null = e.getId();
    return new FilterRow(
      e.getMode(),
      text !== null ? text : '',
      enable !== null ? enable : true,
      id !== null ? id : -1,
      e
    );
  }

  toEntity(): Filter {
    const f: Filter = new Filter();
    if (this.id >= 0) {
      f.setId(this.id);
    }
    f.setMode(this.mode);
    f.setText(this.text);
    f.setEnable(this.enable);
    return f;
  }

  bindNewEntity(): Filter {
    const f: Filter = new Filter(undefined, this.mode, this.text, this.enable);
    this.id = -1;
    this.entity = f;
    return f;
  }

  getOrCreateEntity(): Filter {
    if (this.entity === null) {
      this.entity = this.toEntity();
    }
    return this.entity;
  }

  getMode(): number {
    return this.mode;
  }

  getText(): string {
    return this.text;
  }

  setText(text: string): void {
    this.text = text;
    if (this.entity !== null) {
      this.entity.setText(text);
    }
  }

  isEnable(): boolean {
    return this.enable;
  }

  setEnable(enable: boolean): void {
    this.enable = enable;
  }

  getId(): number {
    return this.id;
  }

  setId(id: number): void {
    this.id = id;
    if (this.entity !== null) {
      this.entity.setId(id >= 0 ? id : null);
    }
  }
}

export class EhDbFilterStore implements FilterStore {
  private cache: FilterRow[] = [];
  private loaded: boolean = false;
  private loadFailed: boolean = false;
  private reloadPromise: Promise<void> | null = null;
  private reloadSeq: number = 0;
  private warnedNotLoaded: boolean = false;
  private pendingWrites: number = 0;
  private writeFailures: number = 0;
  private unsupportedOps: number = 0;

  // ---------------------------------------------------------------- 观测面

  isLoaded(): boolean {
    return this.loaded;
  }

  hasLoadFailed(): boolean {
    return this.loadFailed;
  }

  getPendingWriteCount(): number {
    return this.pendingWrites;
  }

  getWriteFailureCount(): number {
    return this.writeFailures;
  }

  getUnsupportedOpCount(): number {
    return this.unsupportedOps;
  }

  // ---------------------------------------------------------------- FilterStore

  getAllFilter(): FilterLike[] {
    if (!this.loaded && !this.loadFailed && this.reloadPromise === null) {
      this.reload().catch((e: Object): void => {
        hilog.error(DOMAIN, TAG,
          '首次加载过滤器失败（getAllFilter 返回空、isLoaded()=false、hasLoadFailed()=true）: %{public}s',
          (e as Error).message);
      });
      if (!this.warnedNotLoaded) {
        this.warnedNotLoaded = true;
        hilog.info(DOMAIN, TAG,
          'getAllFilter() 首次调用：异步加载中，本次返回空 —— **空 ≠ 没有过滤器**，请用 isLoaded() 区分');
      }
    }
    return this.cache;
  }

  /** 从库重新加载到内存（首次加载 / 手动刷新共用；并发调用复用同一 Promise）。 */
  async reload(): Promise<void> {
    if (this.reloadPromise !== null) {
      return this.reloadPromise;
    }
    const seq: number = ++this.reloadSeq;
    const run = async (): Promise<void> => {
      try {
        const rows: Filter[] = await EhDB.getAllFilter();
        const next: FilterRow[] = [];
        for (let i = 0; i < rows.length; i++) {
          next.push(FilterRow.fromEntity(rows[i]));
        }
        this.cache = next;
        this.loaded = true;
        this.loadFailed = false;
      } catch (e) {
        this.loaded = false;
        this.loadFailed = true;
        throw e as Error;
      } finally {
        if (this.reloadSeq === seq) {
          this.reloadPromise = null;
        }
      }
    };
    const p: Promise<void> = run();
    this.reloadPromise = p;
    return p;
  }

  /** 对位上游 `addFilter`：`enable=true` → 文本转小写（标题/标签/命名空间）→ 落库（回写 id）→ 进内存。 */
  addFilter(filter: FilterLike): void {
    filter.setEnable(true);
    const mode: number = filter.getMode();
    if (mode === EhFilter.MODE_TITLE || mode === EhFilter.MODE_TAG ||
      mode === EhFilter.MODE_TAG_NAMESPACE) {
      filter.setText(filter.getText().toLowerCase());
    }
    const row: FilterRow = filter instanceof FilterRow
      ? filter as FilterRow
      : new FilterRow(mode, filter.getText(), true, filter.getId());
    this.cache.push(row);
    const entity: Filter = row.bindNewEntity();
    this.enqueueWrite(
      EhDB.addFilter(entity).then((): void => {
        const dbId: number | null = entity.getId();
        if (dbId !== null) {
          row.setId(dbId);
        }
      }),
      'addFilter'
    );
  }

  /** 对位上游 `deleteFilter`：内存先移除，并通过 `EhDB.deleteFilter` 持久化删除。 */
  deleteFilter(filter: FilterLike): void {
    const existing: FilterRow | null = this.findInCache(filter);
    this.removeFromCache(filter.getMode(), filter.getText());
    const entity: Filter = existing !== null
      ? existing.getOrCreateEntity()
      : new FilterRow(filter.getMode(), filter.getText(), filter.isEnable(), filter.getId()).toEntity();
    if (existing === null && entity.getId() === null) {
      return;
    }
    this.enqueueWrite(EhDB.deleteFilter(entity), 'deleteFilter');
  }

  /** 对位上游 `triggerFilter`（`EhDB.java:897`）：内存翻转 enable，并通过 `EhDB.triggerFilter` 持久化。 */
  triggerFilter(filter: FilterLike): void {
    const existing: FilterRow | null = this.findInCache(filter);
    const nextEnable: boolean = !filter.isEnable();
    filter.setEnable(nextEnable);
    if (existing !== null && existing !== filter) {
      existing.setEnable(nextEnable);
    }
    const entity: Filter = existing !== null
      ? existing.getOrCreateEntity()
      : new FilterRow(filter.getMode(), filter.getText(), !nextEnable, filter.getId()).toEntity();
    if (existing === null && entity.getId() === null) {
      return;
    }
    this.enqueueWrite(EhDB.triggerFilter(entity), 'triggerFilter');
  }

  // ---------------------------------------------------------------- 内部

  private enqueueWrite(op: Promise<void>, opName: string): void {
    this.pendingWrites++;
    op.then((): void => {
      this.pendingWrites--;
    }).catch((e: Object): void => {
      this.pendingWrites--;
      this.writeFailures++;
      hilog.error(DOMAIN, TAG, '%{public}s 落库失败: %{public}s', opName, (e as Error).message);
    });
  }

  private findInCache(filter: FilterLike): FilterRow | null {
    for (let i = 0; i < this.cache.length; i++) {
      const item: FilterRow = this.cache[i];
      if (item === filter) {
        return item;
      }
      if (item.getMode() === filter.getMode() && item.getText() === filter.getText()) {
        return item;
      }
    }
    return null;
  }

  private removeFromCache(mode: number, text: string): void {
    const next: FilterRow[] = [];
    for (const item of this.cache) {
      const same: boolean = item.getMode() === mode && item.getText() === text;
      if (!same) {
        next.push(item);
      }
    }
    this.cache = next;
  }
}
