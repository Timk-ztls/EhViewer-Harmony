/*
 * Copyright 2026 ehviewer-harmony contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/*
 * Phase B Track P3: Pure-logic adapters and coordinators for Filter, BlackList,
 * MyTags, UConfig, and TagSelector secondary pages.
 *
 * Kept free of ArkUI `@Component` / `@kit.ArkWeb` imports so all CRUD, normalization,
 * grouping, WebView cookie seeding/harvesting, exact URL whitelist, and tag batching
 * logic compiles and executes cleanly in Node/tsc unit tests.
 */

import fs from '@ohos.file.fs';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConfig } from '../../ehviewer/AppConfig';
import { EhDB } from '../../ehviewer/EhDB';
import { Settings } from '../../ehviewer/Settings';
import { EhConfig } from '../../ehviewer/client/EhConfig';
import { EhCookieStore } from '../../ehviewer/client/EhCookieStore';
import { EhEngine } from '../../ehviewer/client/EhEngine';
import { EhFilter } from '../../ehviewer/client/EhFilter';
import { EhTagDatabase, TagDatabaseIo, TagSuggestion } from '../../ehviewer/client/EhTagDatabase';
import { EhUrl } from '../../ehviewer/client/EhUrl';
import { BlackList } from '../../ehviewer/dao/BlackList';
import { Filter } from '../../ehviewer/dao/Filter';
import { EhDbFilterStore } from '../../ehviewer/db/EhDbFilterStore';
import {
  DRAWABLE_BACK,
  MyTagsActivity,
  MyTagsHost,
  MyTagsInitResult,
  WebViewUnavailableSpec
} from '../../ehviewer/ui/MyTagsActivity';
import {
  BatchPlan,
  FooterState,
  FooterUI,
  SelectedTagGroup,
  TagGroup,
  TagItem,
  TagPair,
  TagRow,
  TagSelectorActivity,
  TagSuggester
} from '../../ehviewer/ui/TagSelectorActivity';
import { ProgressViewLike, UConfigActivity } from '../../ehviewer/ui/UConfigActivity';
import { WebCookie, WebViewSignInScene } from '../../ehviewer/ui/scene/sign/WebViewSignInScene';
import { Cookie, CookieBuilder } from '../../okhttp/Cookie';
import { HttpUrl } from '../../okhttp/HttpUrl';

const LOG_DOMAIN: number = 0x0000;
const TAG_P3: string = 'P3PageAdapters';

// ============================================================================
// Shared Text Formatting Helpers
// ============================================================================

export class P3TextFormatter {
  /** Formats `%s` / `%1$s` placeholder for confirmation dialogs. */
  static formatString(template: string, value: string): string {
    if (template.length === 0) {
      return value;
    }
    if (template.indexOf('%1$s') >= 0) {
      return template.split('%1$s').join(value);
    }
    if (template.indexOf('%s') >= 0) {
      const idx: number = template.indexOf('%s');
      return template.substring(0, idx) + value + template.substring(idx + 2);
    }
    return `${template} ${value}`;
  }

  /** Formats `%d` / `%1$d` placeholder for count labels. */
  static formatCount(template: string, count: number): string {
    const numStr: string = `${count}`;
    if (template.length === 0) {
      return numStr;
    }
    if (template.indexOf('%1$d') >= 0) {
      return template.split('%1$d').join(numStr);
    }
    if (template.indexOf('%d') >= 0) {
      const idx: number = template.indexOf('%d');
      return template.substring(0, idx) + numStr + template.substring(idx + 2);
    }
    return `${template} ${numStr}`;
  }
}

// ============================================================================
// 1. Filter Page Adapter & Persistence Port
// ============================================================================

/** Matches upstream `FilterList.MODE_HEADER` / `FilterListConst.MODE_HEADER`. */
export const FILTER_MODE_HEADER: number = -1;
export const FILTER_MODE_TITLE: number = EhFilter.MODE_TITLE;
export const FILTER_MODE_UPLOADER: number = EhFilter.MODE_UPLOADER;
export const FILTER_MODE_TAG: number = EhFilter.MODE_TAG;
export const FILTER_MODE_TAG_NAMESPACE: number = EhFilter.MODE_TAG_NAMESPACE;

export const FILTER_MODE_ORDER: number[] = [
  FILTER_MODE_TITLE,
  FILTER_MODE_UPLOADER,
  FILTER_MODE_TAG,
  FILTER_MODE_TAG_NAMESPACE
];

export const FILTER_MODE_RES_KEYS: string[] = [
  'filter_title',
  'filter_uploader',
  'filter_tag',
  'filter_tag_namespace'
];

export class FilterRecord {
  id: number | null;
  mode: number;
  text: string;
  enabled: boolean;
  readonly recordKey: string;

  constructor(id: number | null, mode: number, text: string, enabled: boolean, recordKey: string) {
    this.id = id;
    this.mode = mode;
    this.text = text;
    this.enabled = enabled;
    this.recordKey = recordKey;
  }
}

export class FilterDisplayRow {
  readonly isHeader: boolean;
  readonly mode: number;
  readonly headerResKey: string;
  readonly text: string;
  readonly enabled: boolean;
  readonly record: FilterRecord | null;
  readonly rowKey: string;

  constructor(
    isHeader: boolean,
    mode: number,
    headerResKey: string,
    text: string,
    enabled: boolean,
    record: FilterRecord | null,
    rowKey: string
  ) {
    this.isHeader = isHeader;
    this.mode = mode;
    this.headerResKey = headerResKey;
    this.text = text;
    this.enabled = enabled;
    this.record = record;
    this.rowKey = rowKey;
  }
}

export class FilterOperationResult {
  readonly ok: boolean;
  readonly errorResKey: string;
  readonly record: FilterRecord | null;

  constructor(ok: boolean, errorResKey: string, record: FilterRecord | null) {
    this.ok = ok;
    this.errorResKey = errorResKey;
    this.record = record;
  }
}

/** Injectable persistence port bridging `FilterPageAdapter` to `EhDB` and `EhEngine`. */
export interface FilterPersistencePort {
  getAllFilter(): Promise<Filter[]>;
  addFilter(filter: Filter): Promise<void>;
  deleteFilter(filter: Filter): Promise<void>;
  triggerFilter(filter: Filter): Promise<void>;
  onFiltersChanged(): Promise<void>;
}

/** Optional UI state mirror port for keeping `FilterActivityState` synchronized. */
export interface FilterStatePort {
  syncFromRecords(records: FilterRecord[]): void;
  isEmpty(): boolean;
  visibleView(): number;
}

/** Production `FilterPersistencePort` backed by `EhDB` + live `EhEngine` reload. */
export class EhDbFilterPersistencePort implements FilterPersistencePort {
  async getAllFilter(): Promise<Filter[]> {
    return await EhDB.getAllFilter();
  }

  async addFilter(filter: Filter): Promise<void> {
    await EhDB.addFilter(filter);
  }

  async deleteFilter(filter: Filter): Promise<void> {
    await EhDB.deleteFilter(filter);
  }

  async triggerFilter(filter: Filter): Promise<void> {
    await EhDB.triggerFilter(filter);
  }

  async onFiltersChanged(): Promise<void> {
    try {
      const store: EhDbFilterStore = new EhDbFilterStore();
      await store.reload();
      EhEngine.setFilterStore(store);
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(LOG_DOMAIN, TAG_P3, 'Failed to sync EhFilter store to EhEngine: %{public}s', msg);
    }
  }
}

export class FilterPageAdapter {
  private readonly persistence: FilterPersistencePort;
  private readonly statePort: FilterStatePort | null;
  private records: FilterRecord[] = [];
  private readonly entities: Map<string, Filter> = new Map<string, Filter>();
  private keySeq: number = 0;

  constructor(persistence: FilterPersistencePort, statePort: FilterStatePort | null = null) {
    this.persistence = persistence;
    this.statePort = statePort;
  }

  static isValidMode(mode: number): boolean {
    return mode === FILTER_MODE_TITLE
      || mode === FILTER_MODE_UPLOADER
      || mode === FILTER_MODE_TAG
      || mode === FILTER_MODE_TAG_NAMESPACE;
  }

  /**
   * Matches `EhFilter` normalization rules:
   * - `MODE_TITLE` / `MODE_TAG` / `MODE_TAG_NAMESPACE`: trim + lowercase
   * - `MODE_UPLOADER`: trim only (uploader match is case-sensitive in upstream `EhFilter`)
   */
  static normalizeText(mode: number, rawText: string): string {
    const trimmed: string = rawText.trim();
    if (mode === FILTER_MODE_UPLOADER) {
      return trimmed;
    }
    return trimmed.toLowerCase();
  }

  static headerResKeyForMode(mode: number): string {
    if (mode === FILTER_MODE_TITLE) {
      return 'filter_title';
    }
    if (mode === FILTER_MODE_UPLOADER) {
      return 'filter_uploader';
    }
    if (mode === FILTER_MODE_TAG) {
      return 'filter_tag';
    }
    if (mode === FILTER_MODE_TAG_NAMESPACE) {
      return 'filter_tag_namespace';
    }
    return 'filter_title';
  }

  static canDelete(row: FilterDisplayRow): boolean {
    return !row.isHeader && row.mode !== FILTER_MODE_HEADER && row.record !== null;
  }

  static canTrigger(row: FilterDisplayRow): boolean {
    return !row.isHeader && row.mode !== FILTER_MODE_HEADER && row.record !== null;
  }

  async load(): Promise<FilterDisplayRow[]> {
    const list: Filter[] = await this.persistence.getAllFilter();
    this.records = [];
    this.entities.clear();
    for (let i = 0; i < list.length; i++) {
      const entity: Filter = list[i];
      const mode: number = entity.getMode();
      if (!FilterPageAdapter.isValidMode(mode)) {
        hilog.warn(LOG_DOMAIN, TAG_P3, 'Skipping unknown filter mode=%{public}d', mode);
        continue;
      }
      const rawText: string | null = entity.getText();
      const text: string = FilterPageAdapter.normalizeText(mode, rawText !== null ? rawText : '');
      const enableVal: boolean | null = entity.getEnable();
      const enabled: boolean = enableVal !== null ? enableVal : true;
      const id: number | null = entity.getId();
      const key: string = this.allocateRecordKey(id);
      const record: FilterRecord = new FilterRecord(id, mode, text, enabled, key);
      this.records.push(record);
      this.entities.set(key, entity);
    }
    this.syncStatePort();
    return this.buildDisplayRows();
  }

  async addFilter(mode: number, rawText: string): Promise<FilterOperationResult> {
    const trimmed: string = rawText.trim();
    if (trimmed.length === 0) {
      return new FilterOperationResult(false, 'text_is_empty', null);
    }
    let safeMode: number = mode;
    if (!FilterPageAdapter.isValidMode(safeMode)) {
      hilog.warn(LOG_DOMAIN, TAG_P3, 'Invalid filter mode=%{public}d, falling back to MODE_TITLE', safeMode);
      safeMode = FILTER_MODE_TITLE;
    }
    const normalized: string = FilterPageAdapter.normalizeText(safeMode, trimmed);
    const entity: Filter = new Filter(undefined, safeMode, normalized, true);
    await this.persistence.addFilter(entity);
    const id: number | null = entity.getId();
    const key: string = this.allocateRecordKey(id);
    const record: FilterRecord = new FilterRecord(id, safeMode, normalized, true, key);
    this.records.push(record);
    this.entities.set(key, entity);
    await this.persistence.onFiltersChanged();
    this.syncStatePort();
    return new FilterOperationResult(true, '', record);
  }

  async toggleFilter(row: FilterDisplayRow): Promise<boolean> {
    if (!FilterPageAdapter.canTrigger(row)) {
      return false;
    }
    const record: FilterRecord = row.record as FilterRecord;
    const entity: Filter | undefined = this.entities.get(record.recordKey);
    if (entity === undefined) {
      hilog.warn(LOG_DOMAIN, TAG_P3, 'toggleFilter: entity missing for key=%{public}s', record.recordKey);
      return false;
    }
    const beforeEnable: boolean = entity.getEnable() === true;
    await this.persistence.triggerFilter(entity);
    const afterEntityEnable: boolean | null = entity.getEnable();
    // Respect `EhDB.triggerFilter` mutation; if a custom port did not mutate the passed entity, flip locally.
    if (afterEntityEnable === null || afterEntityEnable === beforeEnable) {
      entity.setEnable(!beforeEnable);
    }
    record.enabled = entity.getEnable() === true;
    await this.persistence.onFiltersChanged();
    this.syncStatePort();
    return true;
  }

  async deleteFilter(row: FilterDisplayRow): Promise<boolean> {
    if (!FilterPageAdapter.canDelete(row)) {
      return false;
    }
    const record: FilterRecord = row.record as FilterRecord;
    const entity: Filter | undefined = this.entities.get(record.recordKey);
    if (entity === undefined) {
      hilog.warn(LOG_DOMAIN, TAG_P3, 'deleteFilter: entity missing for key=%{public}s', record.recordKey);
      return false;
    }
    await this.persistence.deleteFilter(entity);
    this.entities.delete(record.recordKey);
    const next: FilterRecord[] = [];
    for (let i = 0; i < this.records.length; i++) {
      if (this.records[i].recordKey !== record.recordKey) {
        next.push(this.records[i]);
      }
    }
    this.records = next;
    await this.persistence.onFiltersChanged();
    this.syncStatePort();
    return true;
  }

  /** Builds grouped rows in upstream order (Title → Uploader → Tag → TagNamespace) with `MODE_HEADER` headers. */
  buildDisplayRows(): FilterDisplayRow[] {
    const rows: FilterDisplayRow[] = [];
    for (let m = 0; m < FILTER_MODE_ORDER.length; m++) {
      const mode: number = FILTER_MODE_ORDER[m];
      const groupItems: FilterRecord[] = [];
      for (let i = 0; i < this.records.length; i++) {
        if (this.records[i].mode === mode) {
          groupItems.push(this.records[i]);
        }
      }
      if (groupItems.length === 0) {
        continue;
      }
      const headerKey: string = FilterPageAdapter.headerResKeyForMode(mode);
      rows.push(new FilterDisplayRow(
        true,
        FILTER_MODE_HEADER,
        headerKey,
        '',
        true,
        null,
        `hdr:${mode}`
      ));
      for (let j = 0; j < groupItems.length; j++) {
        const rec: FilterRecord = groupItems[j];
        rows.push(new FilterDisplayRow(
          false,
          rec.mode,
          '',
          rec.text,
          rec.enabled,
          rec,
          `item:${rec.recordKey}`
        ));
      }
    }
    return rows;
  }

  isEmpty(): boolean {
    return this.records.length === 0;
  }

  visibleView(): number {
    return this.isEmpty() ? 1 : 0;
  }

  getRecords(): FilterRecord[] {
    return this.records.slice();
  }

  private allocateRecordKey(id: number | null): string {
    this.keySeq++;
    if (id !== null) {
      return `id:${id}`;
    }
    return `seq:${this.keySeq}`;
  }

  private syncStatePort(): void {
    if (this.statePort !== null) {
      this.statePort.syncFromRecords(this.records);
    }
  }
}

// ============================================================================
// 2. BlackList Page Adapter & Persistence Port
// ============================================================================

/** Matches upstream `BlackListActivityState.MANUAL_ANGRYWITH` & `MANUAL_MODE`. */
export const BLACKLIST_MANUAL_ANGRYWITH: string = '/手动添加/';
export const BLACKLIST_MANUAL_MODE: number = 1;
export const BLACKLIST_MODE_HEADER: number = -1;

export class BlackListRecord {
  readonly id: number | null;
  readonly badgayname: string;
  readonly reason: string;
  readonly angrywith: string;
  readonly addTime: string;
  readonly mode: number;
  readonly rowKey: string;

  constructor(
    id: number | null,
    badgayname: string,
    reason: string,
    angrywith: string,
    addTime: string,
    mode: number,
    rowKey: string
  ) {
    this.id = id;
    this.badgayname = badgayname;
    this.reason = reason;
    this.angrywith = angrywith;
    this.addTime = addTime;
    this.mode = mode;
    this.rowKey = rowKey;
  }
}

export class BlackListOperationResult {
  readonly ok: boolean;
  readonly duplicate: boolean;
  readonly errorResKey: string;
  readonly record: BlackListRecord | null;

  constructor(ok: boolean, duplicate: boolean, errorResKey: string, record: BlackListRecord | null) {
    this.ok = ok;
    this.duplicate = duplicate;
    this.errorResKey = errorResKey;
    this.record = record;
  }
}

/** Injectable persistence port bridging `BlackListPageAdapter` to `EhDB`. */
export interface BlackListPersistencePort {
  getAllBlackList(): Promise<BlackList[]>;
  insertBlackList(item: BlackList): Promise<void>;
  deleteBlackList(item: BlackList): Promise<void>;
}

/** Optional UI state mirror port for keeping `BlackListActivityState` synchronized. */
export interface BlackListStatePort {
  syncFromRecords(records: BlackListRecord[]): void;
  isEmpty(): boolean;
  visibleView(): number;
}

/** Production `BlackListPersistencePort` backed by `EhDB`. */
export class EhDbBlackListPersistencePort implements BlackListPersistencePort {
  async getAllBlackList(): Promise<BlackList[]> {
    return await EhDB.getAllBlackList();
  }

  async insertBlackList(item: BlackList): Promise<void> {
    await EhDB.insertBlackList(item);
  }

  async deleteBlackList(item: BlackList): Promise<void> {
    await EhDB.deleteBlackList(item);
  }
}

export class BlackListPageAdapter {
  private readonly persistence: BlackListPersistencePort;
  private readonly statePort: BlackListStatePort | null;
  private records: BlackListRecord[] = [];
  private readonly entities: Map<string, BlackList> = new Map<string, BlackList>();
  private keySeq: number = 0;

  constructor(persistence: BlackListPersistencePort, statePort: BlackListStatePort | null = null) {
    this.persistence = persistence;
    this.statePort = statePort;
  }

  /** Formats epoch ms into `YYYY-MM-DD HH:MM:SS` matching upstream `TimeUtils.getTimeNow()`. */
  static formatTimestamp(nowMs: number): string {
    const d: Date = new Date(nowMs);
    const pad2 = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
    const yyyy: number = d.getFullYear();
    const mm: string = pad2(d.getMonth() + 1);
    const dd: string = pad2(d.getDate());
    const hh: string = pad2(d.getHours());
    const mi: string = pad2(d.getMinutes());
    const ss: string = pad2(d.getSeconds());
    return `${yyyy}-${mm}-${dd} ${hh}:${mi}:${ss}`;
  }

  async load(): Promise<BlackListRecord[]> {
    const list: BlackList[] = await this.persistence.getAllBlackList();
    this.records = [];
    this.entities.clear();
    for (let i = 0; i < list.length; i++) {
      const entity: BlackList = list[i];
      const rawName: string | null = entity.getBadgayname();
      if (rawName === null || rawName.length === 0) {
        continue;
      }
      const id: number | null = entity.getId();
      const reasonVal: string | null = entity.getReason();
      const angryVal: string | null = entity.getAngrywith();
      const timeVal: string | null = entity.getAdd_time();
      const modeVal: number | null = entity.getMode();
      const rowKey: string = this.allocateRowKey(id, rawName);
      const record: BlackListRecord = new BlackListRecord(
        id,
        rawName,
        reasonVal !== null ? reasonVal : '',
        angryVal !== null ? angryVal : '',
        timeVal !== null ? timeVal : '',
        modeVal !== null ? modeVal : BLACKLIST_MANUAL_MODE,
        rowKey
      );
      this.records.push(record);
      this.entities.set(rowKey, entity);
    }
    this.syncStatePort();
    return this.getRecords();
  }

  findByName(badgayname: string): BlackListRecord | null {
    for (let i = 0; i < this.records.length; i++) {
      if (this.records[i].badgayname === badgayname) {
        return this.records[i];
      }
    }
    return null;
  }

  containsName(badgayname: string): boolean {
    return this.findByName(badgayname) !== null;
  }

  /**
   * Validates, deduplicates by `badgayname`, populates upstream manual fields
   * (`angrywith = '/手动添加/'`, `mode = 1`, `add_time`), inserts into DB, and reloads so
   * AUTOINCREMENT primary keys are hydrated before any subsequent delete.
   */
  async addItem(
    rawName: string,
    rawReason: string = '',
    nowMs: number = Date.now()
  ): Promise<BlackListOperationResult> {
    const name: string = rawName.trim();
    if (name.length === 0) {
      return new BlackListOperationResult(false, false, 'text_is_empty', null);
    }
    const existing: BlackListRecord | null = this.findByName(name);
    if (existing !== null) {
      return new BlackListOperationResult(false, true, '', existing);
    }

    const trimmedReason: string = rawReason.trim();
    const entity: BlackList = new BlackList();
    entity.setBadgayname(name);
    entity.setReason(trimmedReason.length > 0 ? trimmedReason : null);
    entity.setAngrywith(BLACKLIST_MANUAL_ANGRYWITH);
    entity.setAdd_time(BlackListPageAdapter.formatTimestamp(nowMs));
    entity.setMode(BLACKLIST_MANUAL_MODE);

    await this.persistence.insertBlackList(entity);
    // Reload so DB-assigned AUTOINCREMENT id is hydrated (`EhDB.insertBlackList` does not write back id).
    await this.load();
    let inserted: BlackListRecord | null = this.findByName(name);
    if (inserted === null) {
      const rowKey: string = this.allocateRowKey(entity.getId(), name);
      inserted = new BlackListRecord(
        entity.getId(),
        name,
        trimmedReason,
        BLACKLIST_MANUAL_ANGRYWITH,
        entity.getAdd_time() !== null ? (entity.getAdd_time() as string) : '',
        BLACKLIST_MANUAL_MODE,
        rowKey
      );
      this.records.push(inserted);
      this.entities.set(rowKey, entity);
      this.syncStatePort();
    }
    return new BlackListOperationResult(true, false, '', inserted);
  }

  async deleteItem(record: BlackListRecord): Promise<boolean> {
    const entity: BlackList | undefined = this.entities.get(record.rowKey);
    if (entity === undefined) {
      hilog.warn(LOG_DOMAIN, TAG_P3, 'deleteItem: entity missing for key=%{public}s', record.rowKey);
      return false;
    }
    await this.persistence.deleteBlackList(entity);
    this.entities.delete(record.rowKey);
    const next: BlackListRecord[] = [];
    for (let i = 0; i < this.records.length; i++) {
      if (this.records[i].rowKey !== record.rowKey) {
        next.push(this.records[i]);
      }
    }
    this.records = next;
    this.syncStatePort();
    return true;
  }

  isEmpty(): boolean {
    return this.records.length === 0;
  }

  visibleView(): number {
    return this.isEmpty() ? 1 : 0;
  }

  getRecords(): BlackListRecord[] {
    return this.records.slice();
  }

  private allocateRowKey(id: number | null, name: string): string {
    if (id !== null) {
      return `id:${id}`;
    }
    this.keySeq++;
    return `name:${name}#${this.keySeq}`;
  }

  private syncStatePort(): void {
    if (this.statePort !== null) {
      this.statePort.syncFromRecords(this.records);
    }
  }
}

// ============================================================================
// 3. Shared ArkWeb Cookie Backend Port & Cookie Serialization
// ============================================================================

/** Injectable interface mirroring `@kit.ArkWeb` `webview.WebCookieManager` static methods. */
export interface WebCookieBackendPort {
  saveCookieSync(): void;
  clearAllCookiesSync(): void;
  clearSessionCookieSync(): void;
  putAcceptCookieEnabled(accept: boolean): void;
  putAcceptThirdPartyCookieEnabled(accept: boolean): void;
  configCookieSync(url: string, value: string): void;
  fetchCookieSync(url: string): string;
}

/**
 * Formats an `okhttp/Cookie` into an RFC 6265 Set-Cookie line suitable for
 * `webview.WebCookieManager.configCookieSync(url, value)`.
 */
export function formatCookieForWebView(cookie: Cookie): string {
  let line: string = `${cookie.name()}=${cookie.value()}`;
  if (!cookie.hostOnly() && cookie.domain().length > 0) {
    line += `; Domain=${cookie.domain()}`;
  }
  const path: string = cookie.path().length > 0 ? cookie.path() : '/';
  line += `; Path=${path}`;
  if (cookie.secure()) {
    line += '; Secure';
  }
  if (cookie.httpOnly()) {
    line += '; HttpOnly';
  }
  return line;
}

// ============================================================================
// 4. MyTags Page Coordinator (`MyTagsHost` over `WebCookieBackendPort` + `EhCookieStore`)
// ============================================================================

export interface MyTagsPageListener {
  onLoadUrl(url: string): void;
  onProgressVisibleChanged(visible: boolean): void;
  onShowUnavailableDialog(spec: WebViewUnavailableSpec): void;
  onFinish(): void;
}

/**
 * Implements `MyTagsHost` and wraps `MyTagsActivity`, enforcing upstream order:
 * `flush → removeAll → removeSession → setCookie(all cookies for url) → loadUrl`,
 * exact URL equality whitelist (`shouldOverrideUrlLoading`), progress visibility,
 * and unavailable-dialog fallback (both confirm & cancel finish).
 */
export class MyTagsPageCoordinator implements MyTagsHost {
  private readonly cookieBackend: WebCookieBackendPort;
  private readonly cookieStore: EhCookieStore | null;
  private readonly urlProvider: () => string;
  private readonly listener: MyTagsPageListener;
  private readonly activity: MyTagsActivity;

  private jsEnabled: boolean = false;
  private dialogsEnabled: boolean = false;
  private navigationIcon: string = '';
  private loadedUrl: string = '';
  private progressVisible: boolean = false;
  private lastError: string = '';
  private unavailableDialog: WebViewUnavailableSpec | null = null;
  private seededCookieCount: number = 0;

  constructor(
    cookieBackend: WebCookieBackendPort,
    cookieStore: EhCookieStore | null,
    listener: MyTagsPageListener,
    urlProvider?: () => string
  ) {
    this.cookieBackend = cookieBackend;
    this.cookieStore = cookieStore;
    this.listener = listener;
    this.urlProvider = urlProvider !== undefined ? urlProvider : (): string => EhUrl.getMyTagsUrl();
    this.activity = new MyTagsActivity(this);
  }

  init(): MyTagsInitResult {
    this.jsEnabled = false;
    this.dialogsEnabled = false;
    this.loadedUrl = '';
    this.lastError = '';
    this.unavailableDialog = null;
    this.seededCookieCount = 0;
    const res: MyTagsInitResult = this.activity.onCreate();
    this.seededCookieCount = res.cookiesSet;
    return res;
  }

  /** Exact URL whitelist: returns `true` to intercept any URL !== `my_tags` URL. */
  shouldOverrideUrlLoading(targetUrl: string): boolean {
    return this.activity.shouldOverrideUrlLoading(targetUrl);
  }

  onPageStarted(): void {
    this.activity.onPageStarted();
  }

  onPageFinished(): void {
    this.activity.onPageFinished();
  }

  onHomeClick(): boolean {
    return this.activity.onOptionsItemSelected('android.R.id.home');
  }

  onUnavailableDialogConfirm(): void {
    this.activity.onUnavailableDialogConfirm();
  }

  onUnavailableDialogCancel(): void {
    this.activity.onUnavailableDialogCancel();
  }

  getUrl(): string {
    return this.activity.getUrl();
  }

  isCreated(): boolean {
    return this.activity.isCreated();
  }

  isJavaScriptEnabled(): boolean {
    return this.jsEnabled;
  }

  isDialogsEnabled(): boolean {
    return this.dialogsEnabled;
  }

  getNavigationIcon(): string {
    return this.navigationIcon;
  }

  getLoadedUrl(): string {
    return this.loadedUrl;
  }

  isProgressVisible(): boolean {
    return this.progressVisible;
  }

  getLastError(): string {
    return this.lastError;
  }

  getUnavailableDialog(): WebViewUnavailableSpec | null {
    return this.unavailableDialog;
  }

  getSeededCookieCount(): number {
    return this.seededCookieCount;
  }

  // ---- MyTagsHost implementation ----

  cookieFlush(): void {
    this.cookieBackend.saveCookieSync();
  }

  cookieRemoveAll(): void {
    this.cookieBackend.clearAllCookiesSync();
  }

  cookieRemoveSession(): void {
    this.cookieBackend.clearSessionCookieSync();
  }

  cookieSet(url: string, cookie: string): void {
    this.cookieBackend.putAcceptCookieEnabled(true);
    this.cookieBackend.configCookieSync(url, cookie);
  }

  getCookiesFor(url: string): string[] {
    if (this.cookieStore === null) {
      hilog.warn(LOG_DOMAIN, TAG_P3, 'MyTagsPageCoordinator: cookieStore is null for url=%{public}s', url);
      return [];
    }
    const parsed: HttpUrl | null = HttpUrl.parse(url);
    if (parsed === null) {
      hilog.warn(LOG_DOMAIN, TAG_P3, 'MyTagsPageCoordinator: invalid url=%{public}s', url);
      return [];
    }
    const cookies: Cookie[] = this.cookieStore.getCookies(parsed);
    const out: string[] = [];
    for (let i = 0; i < cookies.length; i++) {
      out.push(formatCookieForWebView(cookies[i]));
    }
    return out;
  }

  getMyTagsUrl(): string {
    return this.urlProvider();
  }

  setJavaScriptEnabled(enabled: boolean): void {
    this.jsEnabled = enabled;
  }

  enableDialogs(): void {
    this.dialogsEnabled = true;
  }

  loadUrl(url: string): void {
    this.loadedUrl = url;
    this.listener.onLoadUrl(url);
  }

  setProgressVisible(visible: boolean): void {
    this.progressVisible = visible;
    this.listener.onProgressVisibleChanged(visible);
  }

  setNavigationIcon(icon: string): void {
    this.navigationIcon = icon;
  }

  finish(): void {
    this.listener.onFinish();
  }

  logError(msg: string): void {
    this.lastError = msg;
    hilog.error(LOG_DOMAIN, TAG_P3, 'MyTagsPageCoordinator: %{public}s', msg);
  }

  showUnavailableDialog(spec: WebViewUnavailableSpec): void {
    this.unavailableDialog = spec;
    this.listener.onShowUnavailableDialog(spec);
  }
}

// ============================================================================
// 5. UConfig Page Coordinator (Seed App Cookies + Harvest Sync + Progress/Back)
// ============================================================================

export enum UConfigBackAction {
  WEB_GO_BACK = 0,
  EXIT_PAGE = 1
}

export class UConfigCookieSyncResult {
  readonly syncedCount: number;
  readonly names: string[];
  readonly syncedShowJpnTitle: boolean | null;

  constructor(syncedCount: number, names: string[], syncedShowJpnTitle: boolean | null = null) {
    this.syncedCount = syncedCount;
    this.names = names;
    this.syncedShowJpnTitle = syncedShowJpnTitle;
  }
}

export class UConfigInitResult {
  readonly ok: boolean;
  readonly url: string;
  readonly cookiesSeeded: number;
  readonly error: string;
  readonly unavailableDialog: WebViewUnavailableSpec | null;

  constructor(
    ok: boolean,
    url: string,
    cookiesSeeded: number,
    error: string,
    unavailableDialog: WebViewUnavailableSpec | null
  ) {
    this.ok = ok;
    this.url = url;
    this.cookiesSeeded = cookiesSeeded;
    this.error = error;
    this.unavailableDialog = unavailableDialog;
  }
}

export interface UConfigPageListener {
  onLoadUrl(url: string): void;
  onProgressVisibleChanged(visible: boolean): void;
  onProgressValueChanged(progress: number): void;
  onLoadedChanged(loaded: boolean): void;
  onErrorChanged(error: string): void;
  onShowUnavailableDialog(spec: WebViewUnavailableSpec): void;
  onFinish(): void;
}

class UConfigProgressBridge implements ProgressViewLike {
  private readonly onVis: (visible: boolean) => void;
  private readonly onVal: (progress: number) => void;

  constructor(onVis: (visible: boolean) => void, onVal: (progress: number) => void) {
    this.onVis = onVis;
    this.onVal = onVal;
  }

  setVisibility(visible: boolean): void {
    this.onVis(visible);
  }

  setProgress(progress: number): void {
    this.onVal(progress);
  }
}

export class UConfigPageCoordinator {
  /** Upstream `UConfigActivity.apply()` JS trigger clicking `#apply`'s submit input. */
  static readonly APPLY_JS: string =
    '(function(){'
    + 'var apply=document.getElementById("apply");'
    + 'if(apply&&apply.children&&apply.children.length>0){apply.children[0].click();return "apply";}'
    + 'var submit=document.querySelector("input[type=submit]");'
    + 'if(submit){submit.click();return "submit";}'
    + 'return "none";'
    + '})();';

  private readonly cookieBackend: WebCookieBackendPort;
  private readonly cookieStore: EhCookieStore | null;
  private readonly listener: UConfigPageListener;
  private readonly url: string;
  private readonly activity: UConfigActivity;

  private progressVisible: boolean = false;
  private progressValue: number = 0;
  private errorMessage: string = '';
  private initFailed: boolean = false;
  private unavailableDialog: WebViewUnavailableSpec | null = null;

  constructor(
    cookieBackend: WebCookieBackendPort,
    cookieStore: EhCookieStore | null,
    listener: UConfigPageListener,
    urlOverride?: string
  ) {
    this.cookieBackend = cookieBackend;
    this.cookieStore = cookieStore;
    this.listener = listener;
    this.url = urlOverride !== undefined ? urlOverride : EhUrl.getUConfigUrl();
    this.activity = new UConfigActivity(this.url);
    this.activity.setProgressView(new UConfigProgressBridge(
      (visible: boolean): void => {
        this.progressVisible = visible;
        this.listener.onProgressVisibleChanged(visible);
      },
      (progress: number): void => {
        this.progressValue = progress;
        this.listener.onProgressValueChanged(progress);
      }
    ));
  }

  getUrl(): string {
    return this.activity.getUrl();
  }

  isLoaded(): boolean {
    return this.activity.isLoaded();
  }

  isProgressVisible(): boolean {
    return this.progressVisible;
  }

  getProgressValue(): number {
    return this.progressValue;
  }

  getErrorMessage(): string {
    return this.errorMessage;
  }

  isInitFailed(): boolean {
    return this.initFailed;
  }

  getUnavailableDialog(): WebViewUnavailableSpec | null {
    return this.unavailableDialog;
  }

  /**
   * Prepares ArkWeb cookies (`flush → removeAll → removeSession → accept → seed App cookies`)
   * and initiates `UConfigActivity.startLoad()`.
   */
  init(): UConfigInitResult {
    this.errorMessage = '';
    this.initFailed = false;
    this.unavailableDialog = null;
    try {
      this.cookieBackend.saveCookieSync();
      this.cookieBackend.clearAllCookiesSync();
      this.cookieBackend.clearSessionCookieSync();
      this.cookieBackend.putAcceptCookieEnabled(true);
      this.cookieBackend.putAcceptThirdPartyCookieEnabled(true);

      const seeded: number = this.seedStoreCookiesToWebView();
      this.activity.startLoad();
      this.listener.onErrorChanged('');
      this.listener.onLoadedChanged(false);
      this.listener.onLoadUrl(this.url);
      return new UConfigInitResult(true, this.url, seeded, '', null);
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      this.initFailed = true;
      this.errorMessage = msg;
      const spec: WebViewUnavailableSpec = new WebViewUnavailableSpec();
      this.unavailableDialog = spec;
      hilog.error(LOG_DOMAIN, TAG_P3, 'UConfigPageCoordinator init failed: %{public}s', msg);
      this.listener.onErrorChanged(msg);
      this.listener.onShowUnavailableDialog(spec);
      return new UConfigInitResult(false, this.url, 0, msg, spec);
    }
  }

  /** Seeds all `EhCookieStore` cookies for `uconfig.php` into ArkWeb before page load. */
  private seedStoreCookiesToWebView(): number {
    if (this.cookieStore === null) {
      hilog.warn(LOG_DOMAIN, TAG_P3, 'UConfigPageCoordinator: cookieStore is null, skipping seed');
      return 0;
    }
    const parsed: HttpUrl | null = HttpUrl.parse(this.url);
    if (parsed === null) {
      hilog.warn(LOG_DOMAIN, TAG_P3, 'UConfigPageCoordinator: invalid url=%{public}s', this.url);
      return 0;
    }
    const cookies: Cookie[] = this.cookieStore.getCookies(parsed);
    let count: number = 0;
    for (let i = 0; i < cookies.length; i++) {
      const line: string = formatCookieForWebView(cookies[i]);
      this.cookieBackend.configCookieSync(this.url, line);
      count++;
    }
    return count;
  }

  static parseShowJpnTitleFromUConfig(uconfigValue: string): boolean | null {
    if (uconfigValue.length === 0) {
      return null;
    }
    let decoded: string = uconfigValue;
    try {
      decoded = decodeURIComponent(uconfigValue);
    } catch (_e) {
      decoded = uconfigValue;
    }
    const tokens: string[] = decoded.split('-');
    for (let i = 0; i < tokens.length; i++) {
      const token: string = tokens[i].trim();
      if (token === 'tl_j') {
        return true;
      }
      if (token === 'tl_r') {
        return false;
      }
    }
    return null;
  }

  static updateUConfigShowJpnTitle(uconfigValue: string, showJpn: boolean): string {
    if (uconfigValue.trim().length === 0) {
      return '';
    }
    let decoded: string = uconfigValue;
    try {
      decoded = decodeURIComponent(uconfigValue);
    } catch (_e) {
      decoded = uconfigValue;
    }
    const targetToken: string = showJpn ? 'tl_j' : 'tl_r';
    const rawTokens: string[] = decoded.split('-');
    const outTokens: string[] = [];
    let replaced: boolean = false;
    for (let i = 0; i < rawTokens.length; i++) {
      const token: string = rawTokens[i].trim();
      if (token.length === 0) {
        continue;
      }
      if (token === 'tl_j' || token === 'tl_r') {
        if (!replaced) {
          outTokens.push(targetToken);
          replaced = true;
        }
      } else {
        outTokens.push(token);
      }
    }
    if (!replaced) {
      outTokens.push(targetToken);
    }
    return outTokens.join('-');
  }

  static syncShowJpnTitleFromCookieStore(cookieStore: EhCookieStore | null): boolean | null {
    if (cookieStore === null) {
      return null;
    }
    const probeHosts: string[] = [EhUrl.HOST_E, EhUrl.HOST_EX];
    for (let i = 0; i < probeHosts.length; i++) {
      const parsedUrl: HttpUrl | null = HttpUrl.parse(probeHosts[i]);
      if (parsedUrl === null) {
        continue;
      }
      const list: Cookie[] = cookieStore.getCookies(parsedUrl);
      for (let j = 0; j < list.length; j++) {
        const c: Cookie = list[j];
        if (c.name() === EhConfig.KEY_UCONFIG && c.value().trim().length > 0) {
          return UConfigPageCoordinator.parseShowJpnTitleFromUConfig(c.value().trim());
        }
      }
    }
    return null;
  }

  static syncShowJpnTitleToCookieStore(cookieStore: EhCookieStore | null, showJpn: boolean): boolean {
    if (cookieStore === null) {
      return false;
    }
    const probeHosts: string[] = [EhUrl.HOST_E, EhUrl.HOST_EX];
    let existingUConfig: string = '';
    for (let i = 0; i < probeHosts.length && existingUConfig.length === 0; i++) {
      const parsedUrl: HttpUrl | null = HttpUrl.parse(probeHosts[i]);
      if (parsedUrl === null) {
        continue;
      }
      const list: Cookie[] = cookieStore.getCookies(parsedUrl);
      for (let j = 0; j < list.length; j++) {
        const c: Cookie = list[j];
        if (c.name() === EhConfig.KEY_UCONFIG && c.value().trim().length > 0) {
          existingUConfig = c.value().trim();
          break;
        }
      }
    }
    // 仅在已有 uconfig Cookie 时原地改写 tl_j/tl_r，绝不凭空写入残缺 uconfig
    if (existingUConfig.length === 0) {
      return false;
    }
    const nextValue: string = UConfigPageCoordinator.updateUConfigShowJpnTitle(existingUConfig, showJpn);
    if (nextValue.length === 0) {
      return false;
    }
    const domains: string[] = [EhUrl.DOMAIN_E, EhUrl.DOMAIN_EX];
    for (let i = 0; i < domains.length; i++) {
      const updated: Cookie = new CookieBuilder()
        .name(EhConfig.KEY_UCONFIG)
        .value(nextValue)
        .domain(domains[i])
        .path('/')
        .expiresAt(EhCookieStore.MAX_EXPIRES)
        .build();
      cookieStore.addCookie(updated);
    }
    hilog.info(LOG_DOMAIN, TAG_P3, 'Updated uconfig cookie for show_jpn_title=%{public}s', String(showJpn));
    return true;
  }

  /**
   * Harvests cookies (e.g. `uconfig`, `sk`, `igneous`, `ipb_member_id`, `ipb_pass_hash`)
   * from ArkWeb `WebCookieManager` and writes them back to `EhCookieStore` across both
   * `e-hentai.org` and `exhentai.org` domains as long-lived persistent cookies
   * (matching upstream `UConfigActivity.onDestroy()`).
   */
  syncCookiesToStore(): UConfigCookieSyncResult {
    const store: EhCookieStore | null = this.cookieStore;
    if (store === null) {
      hilog.warn(LOG_DOMAIN, TAG_P3, 'UConfigPageCoordinator.syncCookiesToStore: cookieStore is null');
      return new UConfigCookieSyncResult(0, [], null);
    }
    try {
      this.cookieBackend.saveCookieSync();
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(LOG_DOMAIN, TAG_P3, 'UConfigPageCoordinator saveCookieSync failed: %{public}s', msg);
    }

    const probeUrls: string[] = [];
    if (this.url.length > 0) {
      probeUrls.push(this.url);
    }
    if (probeUrls.indexOf(EhUrl.HOST_E) < 0) {
      probeUrls.push(EhUrl.HOST_E);
    }
    if (probeUrls.indexOf(EhUrl.HOST_EX) < 0) {
      probeUrls.push(EhUrl.HOST_EX);
    }

    const merged: Map<string, string> = new Map<string, string>();
    for (let i = 0; i < probeUrls.length; i++) {
      const probe: string = probeUrls[i];
      try {
        const raw: string = this.cookieBackend.fetchCookieSync(probe);
        if (raw.length === 0) {
          continue;
        }
        const parsed: WebCookie[] = WebViewSignInScene.parseCookies(raw, probe);
        for (let j = 0; j < parsed.length; j++) {
          const item: WebCookie = parsed[j];
          if (item.name.length > 0 && (!merged.has(item.name) || item.value.length > 0)) {
            merged.set(item.name, item.value);
          }
        }
      } catch (e) {
        const msg: string = e instanceof Error ? e.message : String(e);
        hilog.warn(LOG_DOMAIN, TAG_P3, 'UConfig fetchCookieSync(%{public}s) failed: %{public}s', probe, msg);
      }
    }

    const targetDomains: string[] = [EhUrl.DOMAIN_E, EhUrl.DOMAIN_EX];
    const parsedTarget: HttpUrl | null = HttpUrl.parse(this.url);
    if (parsedTarget !== null) {
      const host: string = parsedTarget.host();
      if (host.length > 0 && targetDomains.indexOf(host) < 0) {
        targetDomains.push(host);
      }
    }

    const syncedNames: string[] = [];
    let syncedShowJpnTitle: boolean | null = null;
    merged.forEach((value: string, name: string): void => {
      if (name === EhConfig.KEY_CONTENT_WARNING) {
        return;
      }
      if (name === EhConfig.KEY_UCONFIG) {
        const parsedJpn: boolean | null = UConfigPageCoordinator.parseShowJpnTitleFromUConfig(value);
        if (parsedJpn !== null) {
          syncedShowJpnTitle = parsedJpn;
          Settings.putShowJpnTitle(parsedJpn);
          void Settings.flush();
          hilog.info(LOG_DOMAIN, TAG_P3, 'UConfig synced show_jpn_title=%{public}s', String(parsedJpn));
        }
      }
      for (let d = 0; d < targetDomains.length; d++) {
        const built: Cookie = new CookieBuilder()
          .name(name)
          .value(value)
          .domain(targetDomains[d])
          .path('/')
          .expiresAt(EhCookieStore.MAX_EXPIRES)
          .build();
        store.addCookie(built);
      }
      syncedNames.push(name);
    });

    if (store.hasSignedIn()) {
      Settings.setLoginState(true);
    }
    return new UConfigCookieSyncResult(syncedNames.length, syncedNames, syncedShowJpnTitle);
  }

  /**
   * Allows navigation to `uconfig.php` on `e-hentai.org` / `exhentai.org` (so form POST / Apply works),
   * while intercepting navigation away to unrelated pages or external origins.
   * @returns `true` to intercept (block), `false` to allow.
   */
  shouldOverrideUrlLoading(targetUrl: string): boolean {
    if (targetUrl === this.url) {
      return false;
    }
    const parsed: HttpUrl | null = HttpUrl.parse(targetUrl);
    if (parsed === null) {
      return true;
    }
    const host: string = parsed.host().toLowerCase();
    const isEhHost: boolean = host === EhUrl.DOMAIN_E || host === EhUrl.DOMAIN_EX;
    const isUConfigPath: boolean = parsed.encodedPath().startsWith('/uconfig.php');
    return !(isEhHost && isUConfigPath);
  }

  onPageStarted(): void {
    this.errorMessage = '';
    this.listener.onErrorChanged('');
    this.activity.startLoad();
    this.listener.onLoadedChanged(false);
  }

  onProgressChanged(newProgress: number): void {
    this.activity.onProgressChanged(newProgress);
  }

  onPageFinished(): UConfigCookieSyncResult {
    this.activity.onPageFinished();
    this.listener.onLoadedChanged(true);
    return this.syncCookiesToStore();
  }

  onLoadError(description: string): void {
    this.errorMessage = description;
    this.activity.onLoadError(description);
    this.listener.onLoadedChanged(false);
    this.listener.onErrorChanged(description);
  }

  onRefresh(): void {
    this.errorMessage = '';
    this.listener.onErrorChanged('');
    this.activity.startLoad();
    this.listener.onLoadedChanged(false);
  }

  onDestroy(): UConfigCookieSyncResult {
    return this.syncCookiesToStore();
  }

  /** Respects `webController.accessBackward()` before exiting; harvests cookies on exit. */
  handleBack(canGoBack: boolean): UConfigBackAction {
    if (canGoBack) {
      return UConfigBackAction.WEB_GO_BACK;
    }
    this.syncCookiesToStore();
    return UConfigBackAction.EXIT_PAGE;
  }

  onUnavailableDialogConfirm(): void {
    this.listener.onFinish();
  }

  onUnavailableDialogCancel(): void {
    this.listener.onFinish();
  }
}

// ============================================================================
// 6. TagSelector Coordinator, EhTagDatabase Suggester & Result Bus
// ============================================================================

/**
 * `TagDatabaseIo` reading downloaded tag translation data from `AppConfig.getFilesDir('tag-translations')`.
 * Returns `null` cleanly when the database file has not been downloaded yet.
 */
export class AppTagDatabaseIo implements TagDatabaseIo {
  static readonly DEFAULT_METADATA: string[] = [
    'tag-translations-zh-rCN.sha1',
    'https://raw.githubusercontent.com/xiaojieonly/EhTagTranslation/main/tag-translations/tag-translations-zh-rCN.json.sha1',
    'tag-translations-zh-rCN',
    'https://raw.githubusercontent.com/xiaojieonly/EhTagTranslation/main/tag-translations/tag-translations-zh-rCN.json'
  ];

  private readonly metadata: string[] | null;

  constructor(metadata?: string[] | null) {
    this.metadata = metadata !== undefined ? metadata : AppTagDatabaseIo.DEFAULT_METADATA;
  }

  getMetadata(): string[] | null {
    return this.metadata;
  }

  readData(dataName: string): ArrayBuffer | null {
    const dir: string | null = AppConfig.getFilesDir('tag-translations');
    if (dir === null || dir.length === 0 || dataName.length === 0) {
      return null;
    }
    const filePath: string = `${dir}/${dataName}`;
    try {
      if (!fs.accessSync(filePath)) {
        return null;
      }
      const stat: fs.Stat = fs.statSync(filePath);
      if (!stat.isFile() || stat.size <= 0) {
        return null;
      }
      const file: fs.File = fs.openSync(filePath, fs.OpenMode.READ_ONLY);
      try {
        const buf: ArrayBuffer = new ArrayBuffer(stat.size);
        let totalRead: number = 0;
        while (totalRead < stat.size) {
          const chunkLen: number = stat.size - totalRead;
          const chunk: ArrayBuffer = new ArrayBuffer(chunkLen);
          const n: number = fs.readSync(file.fd, chunk, { length: chunkLen });
          if (n <= 0) {
            break;
          }
          new Uint8Array(buf, totalRead, n).set(new Uint8Array(chunk, 0, n));
          totalRead += n;
        }
        return totalRead > 0 ? buf.slice(0, totalRead) : null;
      } finally {
        fs.closeSync(file);
      }
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(LOG_DOMAIN, TAG_P3, 'AppTagDatabaseIo.readData(%{public}s) failed: %{public}s', filePath, msg);
      return null;
    }
  }
}

/**
 * Adapts `EhTagDatabase.suggest(prefix)` into `TagSelectorActivity`'s `TagSuggester` port.
 * Degrades gracefully (returns `[]` + warn-once log) when the tag database is not loaded.
 */
export class EhTagDatabaseSuggester implements TagSuggester {
  private readonly dbProvider: () => EhTagDatabase | null;
  private warnedUnavailable: boolean = false;

  constructor(dbProvider: () => EhTagDatabase | null) {
    this.dbProvider = dbProvider;
  }

  static fromDatabase(db: EhTagDatabase | null): EhTagDatabaseSuggester {
    return new EhTagDatabaseSuggester((): EhTagDatabase | null => db);
  }

  static fromAppFiles(): EhTagDatabaseSuggester {
    const io: AppTagDatabaseIo = new AppTagDatabaseIo();
    return new EhTagDatabaseSuggester((): EhTagDatabase | null => EhTagDatabase.getInstance(io));
  }

  suggest(prefix: string): TagPair[] | null {
    const db: EhTagDatabase | null = this.dbProvider();
    if (db === null) {
      if (!this.warnedUnavailable) {
        this.warnedUnavailable = true;
        hilog.warn(LOG_DOMAIN, TAG_P3, 'EhTagDatabase not loaded; TagSelector falling back to pinned tags');
      }
      return [];
    }
    const raw: TagSuggestion[] = db.suggest(prefix);
    const out: TagPair[] = [];
    for (let i = 0; i < raw.length; i++) {
      const item: TagSuggestion = raw[i];
      out.push(new TagPair(item.chinese, item.english));
    }
    return out;
  }
}

export class TagSelectorGroupSnapshot {
  readonly title: string;
  readonly namespace: string;
  readonly visibleItems: TagItem[];
  readonly footerState: FooterState;
  readonly showCollapse: boolean;
  readonly hasSearchFilter: boolean;

  constructor(
    title: string,
    namespace: string,
    visibleItems: TagItem[],
    footerState: FooterState,
    showCollapse: boolean,
    hasSearchFilter: boolean
  ) {
    this.title = title;
    this.namespace = namespace;
    this.visibleItems = visibleItems;
    this.footerState = footerState;
    this.showCollapse = showCollapse;
    this.hasSearchFilter = hasSearchFilter;
  }
}

/**
 * Tiny static result carrier so callers opening `pages/TagSelectorPage` can receive
 * the confirmed `selectedQueryText()` cleanly via callback or pending consumption on `router.back()`.
 */
export class TagSelectorResultBus {
  private static pendingResult: string | null = null;
  private static hasPending: boolean = false;
  private static listener: ((query: string) => void) | null = null;

  static setListener(cb: ((query: string) => void) | null): void {
    TagSelectorResultBus.listener = cb;
  }

  static deliver(query: string): void {
    const cb: ((q: string) => void) | null = TagSelectorResultBus.listener;
    if (cb !== null) {
      TagSelectorResultBus.pendingResult = null;
      TagSelectorResultBus.hasPending = false;
      try {
        cb(query);
      } catch (e) {
        const msg: string = e instanceof Error ? e.message : String(e);
        hilog.warn(LOG_DOMAIN, TAG_P3, 'TagSelectorResultBus listener threw: %{public}s', msg);
      }
      return;
    }
    TagSelectorResultBus.pendingResult = query;
    TagSelectorResultBus.hasPending = true;
  }

  static hasPendingResult(): boolean {
    return TagSelectorResultBus.hasPending;
  }

  static peekPendingResult(): string | null {
    return TagSelectorResultBus.hasPending ? TagSelectorResultBus.pendingResult : null;
  }

  static consumePendingResult(): string | null {
    if (!TagSelectorResultBus.hasPending) {
      return null;
    }
    const res: string | null = TagSelectorResultBus.pendingResult;
    TagSelectorResultBus.pendingResult = null;
    TagSelectorResultBus.hasPending = false;
    return res;
  }

  static clear(): void {
    TagSelectorResultBus.pendingResult = null;
    TagSelectorResultBus.hasPending = false;
    TagSelectorResultBus.listener = null;
  }
}

export class TagSelectorPageCoordinator {
  private readonly activity: TagSelectorActivity = new TagSelectorActivity();
  private readonly suggester: TagSuggester | null;
  private searchKeyword: string = '';
  private isDarkMode: boolean = false;

  constructor(suggester: TagSuggester | null) {
    this.suggester = suggester;
  }

  init(appLanguage: string, isDarkMode: boolean = false, initialQuery: string = ''): void {
    this.isDarkMode = isDarkMode;
    this.searchKeyword = '';
    const isChinese: boolean = TagSelectorActivity.resolveChineseSystem(appLanguage);
    this.activity.initGroups(isChinese);
    this.activity.selectedTags.clear();

    // Upstream preloads every non-language group on create.
    const toPreload: TagGroup[] = this.activity.groupsToPreload();
    for (let i = 0; i < toPreload.length; i++) {
      this.loadNextBatchForGroup(toPreload[i]);
    }

    if (initialQuery.trim().length > 0) {
      this.seedInitialSelection(initialQuery);
    }
  }

  private seedInitialSelection(initialQuery: string): void {
    const tokens: string[] = initialQuery.trim().split(/\s+/);
    for (let i = 0; i < tokens.length; i++) {
      const key: string = tokens[i].trim();
      if (key.length === 0) {
        continue;
      }
      const display: string = this.findDisplayNameForKey(key);
      this.activity.selectedTags.set(key, display);
    }
  }

  private findDisplayNameForKey(key: string): string {
    for (let i = 0; i < this.activity.groups.length; i++) {
      const g: TagGroup = this.activity.groups[i];
      for (let j = 0; j < g.loadedTags.length; j++) {
        if (g.loadedTags[j].key === key) {
          return g.loadedTags[j].show;
        }
      }
    }
    const colon: number = key.indexOf(':');
    const shortName: string = colon >= 0 ? key.substring(colon + 1) : key;
    return TagSelectorActivity.capitalize(shortName);
  }

  getActivity(): TagSelectorActivity {
    return this.activity;
  }

  isChineseSystem(): boolean {
    return this.activity.isChineseSystem;
  }

  getDarkMode(): boolean {
    return this.isDarkMode;
  }

  getSearchKeyword(): string {
    return this.searchKeyword;
  }

  setSearchKeyword(keyword: string): void {
    this.searchKeyword = keyword;
  }

  findGroup(namespace: string): TagGroup | null {
    for (let i = 0; i < this.activity.groups.length; i++) {
      if (this.activity.groups[i].namespace === namespace) {
        return this.activity.groups[i];
      }
    }
    return null;
  }

  loadNextBatch(namespace: string): boolean {
    const group: TagGroup | null = this.findGroup(namespace);
    if (group === null) {
      return false;
    }
    return this.loadNextBatchForGroup(group);
  }

  private loadNextBatchForGroup(group: TagGroup): boolean {
    const plan: BatchPlan = TagSelectorActivity.planNextBatch(group);
    group.visibleCount = plan.targetCount;
    if (!plan.needQuery) {
      return plan.refresh;
    }
    if (this.suggester === null) {
      group.prefixIndex = TagSelectorActivity.LOAD_PREFIXES.length;
      if (group.visibleCount > group.loadedTags.length) {
        group.visibleCount = group.loadedTags.length;
      }
      return true;
    }
    while (group.prefixIndex < TagSelectorActivity.LOAD_PREFIXES.length) {
      const prefix: string | null = TagSelectorActivity.prefixFor(group);
      if (prefix === null) {
        break;
      }
      const rawPairs: TagPair[] | null = this.suggester.suggest(prefix);
      const normalized: TagItem[] = TagSelectorActivity.normalizeSuggest(
        group,
        rawPairs,
        this.activity.isChineseSystem
      );
      const needMore: boolean = TagSelectorActivity.applyBatch(group, normalized);
      if (!needMore) {
        break;
      }
    }
    return true;
  }

  collapseGroup(namespace: string): boolean {
    const group: TagGroup | null = this.findGroup(namespace);
    if (group === null) {
      return false;
    }
    TagSelectorActivity.collapse(group);
    return true;
  }

  toggleTag(key: string, show: string): boolean {
    return this.activity.toggle(key, show);
  }

  removeSelected(key: string): void {
    this.activity.removeSelected(key);
  }

  clearSelected(): void {
    this.activity.selectedTags.clear();
  }

  isSelected(key: string): boolean {
    return this.activity.selectedTags.has(key);
  }

  getSelectedCount(): number {
    return this.activity.selectedTags.size;
  }

  isEmptySelection(): boolean {
    return this.activity.isEmptySelection();
  }

  getSelectedGroups(): SelectedTagGroup[] {
    return this.activity.rebuildSelectedGroups();
  }

  selectedQueryText(): string {
    return this.activity.selectedQueryText();
  }

  /** Delivers confirmed query string through `TagSelectorResultBus` and returns it. */
  confirmSelection(): string {
    const query: string = this.activity.selectedQueryText();
    TagSelectorResultBus.deliver(query);
    return query;
  }

  buildRows(): TagRow[] {
    return this.activity.buildRows();
  }

  getGroupSnapshots(): TagSelectorGroupSnapshot[] {
    const kw: string = this.searchKeyword.trim().toLowerCase();
    const filtering: boolean = kw.length > 0;
    let extraSuggestions: TagPair[] | null = null;
    if (filtering && this.suggester !== null) {
      extraSuggestions = this.suggester.suggest(kw);
    }

    const out: TagSelectorGroupSnapshot[] = [];
    for (let i = 0; i < this.activity.groups.length; i++) {
      const group: TagGroup = this.activity.groups[i];
      if (!filtering) {
        const limit: number = Math.min(group.visibleCount, group.loadedTags.length);
        const visible: TagItem[] = group.loadedTags.slice(0, limit);
        const footer: FooterUI = TagSelectorActivity.footerState(group);
        out.push(new TagSelectorGroupSnapshot(
          group.title,
          group.namespace,
          visible,
          footer.state,
          footer.showCollapse,
          false
        ));
        continue;
      }

      const matched: TagItem[] = [];
      const seenKeys: Set<string> = new Set<string>();
      for (let j = 0; j < group.loadedTags.length; j++) {
        const item: TagItem = group.loadedTags[j];
        if (item.key.toLowerCase().indexOf(kw) >= 0 || item.show.toLowerCase().indexOf(kw) >= 0) {
          if (!seenKeys.has(item.key)) {
            seenKeys.add(item.key);
            matched.push(item);
          }
        }
      }
      if (extraSuggestions !== null) {
        const normalizedExtra: TagItem[] = TagSelectorActivity.normalizeSuggest(
          group,
          extraSuggestions,
          this.activity.isChineseSystem
        );
        for (let k = 0; k < normalizedExtra.length; k++) {
          const extraItem: TagItem = normalizedExtra[k];
          if (!seenKeys.has(extraItem.key)) {
            seenKeys.add(extraItem.key);
            matched.push(extraItem);
          }
        }
      }
      if (matched.length > 0) {
        out.push(new TagSelectorGroupSnapshot(
          group.title,
          group.namespace,
          matched,
          FooterState.END,
          false,
          true
        ));
      }
    }
    return out;
  }

  static footerMoreText(isChinese: boolean, resText: string): string {
    if (resText.length > 0) {
      return resText;
    }
    return isChinese ? '▼ 更多' : '▼ More';
  }

  static footerCollapseText(isChinese: boolean, resText: string): string {
    if (resText.length > 0) {
      return resText;
    }
    return isChinese ? '▲ 收起' : '▲ Collapse';
  }

  static footerEndText(isChinese: boolean, resText: string): string {
    if (resText.length > 0) {
      return resText;
    }
    return isChinese ? '--- 已到底 ---' : '--- End ---';
  }
}

export { DRAWABLE_BACK };
