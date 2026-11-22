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
 * Phase B Track P3 unit tests:
 *   1. FilterPageAdapter + FilterPersistencePort + FilterStatePort
 *      (CRUD, toggle, grouping, MODE_HEADER guards, EhFilter normalization, validation)
 *   2. BlackListPageAdapter + BlackListPersistencePort + BlackListStatePort
 *      (CRUD, validation, manual constants '/手动添加/' & mode=1, dedup by badgayname, ID hydration)
 *   3. MyTagsPageCoordinator + MyTagsActivity + EhCookieStore + WebCookieBackendPort
 *      (flush -> removeAll -> removeSession -> setCookie -> loadUrl order, exact URL whitelist,
 *       progress visibility, home finish, unavailable fallback confirm & cancel)
 *   4. UConfigPageCoordinator + UConfigActivity + EhCookieStore + WebCookieBackendPort
 *      (cookie seeding, cookie harvesting across e/ex domains on pageEnd & destroy, progress/error,
 *       canGoBack vs exit, navigation whitelist, unavailable fallback)
 *   5. TagSelectorPageCoordinator + EhTagDatabaseSuggester + AppTagDatabaseIo + TagSelectorResultBus
 *      (9 groups, pinned languages, preload non-language groups, pagination/collapse/end,
 *       keyword search, zh vs en normalization, CJK filtering, null DB fallback, ResultBus)
 *
 * Run:
 *   pwsh -NoProfile -ExecutionPolicy Bypass -File harmony/entry/src/test/ui-scene/run.ps1 -Filter p3-
 */

import fs from '@ohos.file.fs';
import common from '@ohos.app.ability.common';
import { AppConfig } from '../../main/ets/hippo/ehviewer/AppConfig';
import { Settings } from '../../main/ets/hippo/ehviewer/Settings';
import { EhCookieStore } from '../../main/ets/hippo/ehviewer/client/EhCookieStore';
import { EhFilter } from '../../main/ets/hippo/ehviewer/client/EhFilter';
import { EhTagDatabase } from '../../main/ets/hippo/ehviewer/client/EhTagDatabase';
import { EhUrl, EhUrlSiteConfig } from '../../main/ets/hippo/ehviewer/client/EhUrl';
import { BlackList } from '../../main/ets/hippo/ehviewer/dao/BlackList';
import { Filter } from '../../main/ets/hippo/ehviewer/dao/Filter';
import {
  DRAWABLE_BACK,
  MyTagsInitResult,
  STR_WEBVIEW_UNAVAILABLE_MESSAGE,
  STR_WEBVIEW_UNAVAILABLE_TITLE,
  WebViewUnavailableSpec
} from '../../main/ets/hippo/ehviewer/ui/MyTagsActivity';
import {
  FooterState,
  SelectedTagGroup,
  TagGroup,
  TagSelectorActivity
} from '../../main/ets/hippo/ehviewer/ui/TagSelectorActivity';
import { InMemoryCookieStore } from '../../main/ets/hippo/network/CookieDatabase';
import { Cookie, CookieBuilder } from '../../main/ets/hippo/okhttp/Cookie';
import { HttpUrl } from '../../main/ets/hippo/okhttp/HttpUrl';
import {
  AppTagDatabaseIo,
  BLACKLIST_MANUAL_ANGRYWITH,
  BLACKLIST_MANUAL_MODE,
  BlackListOperationResult,
  BlackListPageAdapter,
  BlackListPersistencePort,
  BlackListRecord,
  BlackListStatePort,
  EhTagDatabaseSuggester,
  FILTER_MODE_HEADER,
  FILTER_MODE_TAG,
  FILTER_MODE_TAG_NAMESPACE,
  FILTER_MODE_TITLE,
  FILTER_MODE_UPLOADER,
  FilterDisplayRow,
  FilterOperationResult,
  FilterPageAdapter,
  FilterPersistencePort,
  FilterRecord,
  FilterStatePort,
  formatCookieForWebView,
  MyTagsPageCoordinator,
  MyTagsPageListener,
  P3TextFormatter,
  TagSelectorGroupSnapshot,
  TagSelectorPageCoordinator,
  TagSelectorResultBus,
  UConfigBackAction,
  UConfigCookieSyncResult,
  UConfigInitResult,
  UConfigPageCoordinator,
  UConfigPageListener,
  WebCookieBackendPort
} from '../../main/ets/hippo/ui/p3/P3PageAdapters';

let passed: number = 0;
const failures: string[] = [];

function eq(name: string, got: Object | null | undefined, want: Object | null | undefined): void {
  const g: string = JSON.stringify(got);
  const w: string = JSON.stringify(want);
  if (g === w) {
    passed++;
  } else {
    failures.push(`${name}\n    got  ${g}\n    want ${w}`);
  }
}

function ok(name: string, cond: boolean): void {
  if (cond) {
    passed++;
  } else {
    failures.push(`${name} (expected true)`);
  }
}

// ============================================================================
// Fakes & Test Builders
// ============================================================================

class FakeFilterPersistence implements FilterPersistencePort {
  store: Filter[] = [];
  nextId: number = 1;
  mutateOnTrigger: boolean = true;
  changedCalls: number = 0;

  async getAllFilter(): Promise<Filter[]> {
    return this.store.slice();
  }

  async addFilter(filter: Filter): Promise<void> {
    filter.setId(this.nextId++);
    this.store.push(filter);
  }

  async deleteFilter(filter: Filter): Promise<void> {
    const idx: number = this.store.indexOf(filter);
    if (idx >= 0) {
      this.store.splice(idx, 1);
    }
  }

  async triggerFilter(filter: Filter): Promise<void> {
    if (this.mutateOnTrigger) {
      filter.setEnable(!(filter.getEnable() === true));
    }
  }

  async onFiltersChanged(): Promise<void> {
    this.changedCalls++;
  }
}

class FakeFilterStatePort implements FilterStatePort {
  syncedCount: number = 0;
  records: FilterRecord[] = [];

  syncFromRecords(records: FilterRecord[]): void {
    this.syncedCount++;
    this.records = records.slice();
  }

  isEmpty(): boolean {
    return this.records.length === 0;
  }

  visibleView(): number {
    return this.isEmpty() ? 1 : 0;
  }
}

class FakeBlackListPersistence implements BlackListPersistencePort {
  store: BlackList[] = [];
  nextId: number = 100;
  insertCalls: number = 0;
  deleteCalls: number = 0;

  async getAllBlackList(): Promise<BlackList[]> {
    return this.store.slice();
  }

  async insertBlackList(item: BlackList): Promise<void> {
    this.insertCalls++;
    // Mimics EhDB.insertBlackList: assigns DB row in table without writing id back to caller entity.
    const stored: BlackList = new BlackList(
      this.nextId++,
      item.getBadgayname() !== null ? (item.getBadgayname() as string) : undefined,
      item.getReason() !== null ? (item.getReason() as string) : undefined,
      item.getAngrywith() !== null ? (item.getAngrywith() as string) : undefined,
      item.getAdd_time() !== null ? (item.getAdd_time() as string) : undefined,
      item.getMode() !== null ? (item.getMode() as number) : undefined
    );
    this.store.push(stored);
  }

  async deleteBlackList(item: BlackList): Promise<void> {
    this.deleteCalls++;
    const targetId: number | null = item.getId();
    const next: BlackList[] = [];
    for (let i = 0; i < this.store.length; i++) {
      const cur: BlackList = this.store[i];
      if (targetId !== null && cur.getId() === targetId) {
        continue;
      }
      if (targetId === null && cur === item) {
        continue;
      }
      next.push(cur);
    }
    this.store = next;
  }
}

class FakeBlackListStatePort implements BlackListStatePort {
  syncedCount: number = 0;
  records: BlackListRecord[] = [];

  syncFromRecords(records: BlackListRecord[]): void {
    this.syncedCount++;
    this.records = records.slice();
  }

  isEmpty(): boolean {
    return this.records.length === 0;
  }

  visibleView(): number {
    return this.isEmpty() ? 1 : 0;
  }
}

class FakeWebCookieBackend implements WebCookieBackendPort {
  ops: string[] = [];
  configured: string[] = [];
  fetchedByUrl: Map<string, string> = new Map<string, string>();
  throwOnClearAll: boolean = false;
  throwOnFetch: boolean = false;
  acceptCookie: boolean = false;
  acceptThirdParty: boolean = false;

  saveCookieSync(): void {
    this.ops.push('flush');
  }

  clearAllCookiesSync(): void {
    this.ops.push('removeAll');
    if (this.throwOnClearAll) {
      throw new Error('WebCookieManager broken');
    }
  }

  clearSessionCookieSync(): void {
    this.ops.push('removeSession');
  }

  putAcceptCookieEnabled(accept: boolean): void {
    this.acceptCookie = accept;
  }

  putAcceptThirdPartyCookieEnabled(accept: boolean): void {
    this.acceptThirdParty = accept;
  }

  configCookieSync(url: string, value: string): void {
    this.ops.push('set:' + value);
    this.configured.push(`${url}|${value}`);
  }

  fetchCookieSync(url: string): string {
    if (this.throwOnFetch) {
      throw new Error('fetch boom');
    }
    const found: string | undefined = this.fetchedByUrl.get(url);
    return found !== undefined ? found : '';
  }
}

class FakeMyTagsListener implements MyTagsPageListener {
  loadedUrls: string[] = [];
  progressEvents: boolean[] = [];
  unavailableDialogs: WebViewUnavailableSpec[] = [];
  finishCalls: number = 0;

  onLoadUrl(url: string): void {
    this.loadedUrls.push(url);
  }

  onProgressVisibleChanged(visible: boolean): void {
    this.progressEvents.push(visible);
  }

  onShowUnavailableDialog(spec: WebViewUnavailableSpec): void {
    this.unavailableDialogs.push(spec);
  }

  onFinish(): void {
    this.finishCalls++;
  }
}

class FakeUConfigListener implements UConfigPageListener {
  loadedUrls: string[] = [];
  progressVisibleEvents: boolean[] = [];
  progressValues: number[] = [];
  loadedEvents: boolean[] = [];
  errorEvents: string[] = [];
  unavailableDialogs: WebViewUnavailableSpec[] = [];
  finishCalls: number = 0;

  onLoadUrl(url: string): void {
    this.loadedUrls.push(url);
  }

  onProgressVisibleChanged(visible: boolean): void {
    this.progressVisibleEvents.push(visible);
  }

  onProgressValueChanged(progress: number): void {
    this.progressValues.push(progress);
  }

  onLoadedChanged(loaded: boolean): void {
    this.loadedEvents.push(loaded);
  }

  onErrorChanged(error: string): void {
    this.errorEvents.push(error);
  }

  onShowUnavailableDialog(spec: WebViewUnavailableSpec): void {
    this.unavailableDialogs.push(spec);
  }

  onFinish(): void {
    this.finishCalls++;
  }
}

class StaticSiteConfig extends EhUrlSiteConfig {
  private readonly siteValue: number;

  constructor(siteValue: number) {
    super();
    this.siteValue = siteValue;
  }

  getGallerySite(): number {
    return this.siteValue;
  }
}

class FakeAppContext implements common.Context {
  filesDir: string;
  cacheDir: string;

  constructor(filesDir: string, cacheDir: string) {
    this.filesDir = filesDir;
    this.cacheDir = cacheDir;
  }
}

const B64_ALPHA: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

function encodeUtf8Bytes(s: string): Uint8Array {
  const out: number[] = [];
  for (let i = 0; i < s.length; i++) {
    const c: number = s.charCodeAt(i);
    if (c < 0x80) {
      out.push(c);
    } else if (c < 0x800) {
      out.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f));
    } else if (c >= 0xd800 && c <= 0xdbff && i + 1 < s.length) {
      const next: number = s.charCodeAt(i + 1);
      const cp: number = 0x10000 + ((c - 0xd800) << 10) + (next - 0xdc00);
      out.push(
        0xf0 | (cp >> 18),
        0x80 | ((cp >> 12) & 0x3f),
        0x80 | ((cp >> 6) & 0x3f),
        0x80 | (cp & 0x3f)
      );
      i++;
    } else {
      out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
    }
  }
  const u8: Uint8Array = new Uint8Array(out.length);
  for (let i = 0; i < out.length; i++) {
    u8[i] = out[i];
  }
  return u8;
}

function encodeBase64Utf8(s: string): string {
  const bytes: Uint8Array = encodeUtf8Bytes(s);
  let out: string = '';
  let i: number = 0;
  while (i < bytes.length) {
    const b0: number = bytes[i++];
    const hasB1: boolean = i < bytes.length;
    const b1: number = hasB1 ? bytes[i++] : 0;
    const hasB2: boolean = i < bytes.length;
    const b2: number = hasB2 ? bytes[i++] : 0;
    const triple: number = (b0 << 16) | (b1 << 8) | b2;
    out += B64_ALPHA.charAt((triple >> 18) & 0x3f);
    out += B64_ALPHA.charAt((triple >> 12) & 0x3f);
    out += hasB1 ? B64_ALPHA.charAt((triple >> 6) & 0x3f) : '=';
    out += hasB2 ? B64_ALPHA.charAt(triple & 0x3f) : '=';
  }
  return out;
}

/** Builds a valid binary `EhTagDatabase` ArrayBuffer from `[shortKey, zhTranslation]` pairs. */
function buildBinaryTagDatabase(entries: string[][]): ArrayBuffer {
  const lines: string[] = [];
  for (let i = 0; i < entries.length; i++) {
    const eng: string = entries[i][0];
    const zh: string = entries[i][1];
    const b64: string = encodeBase64Utf8(zh);
    lines.push(`${eng}\r${b64}`);
  }
  const payload: Uint8Array = encodeUtf8Bytes(lines.join('\n'));
  const out: Uint8Array = new Uint8Array(4 + payload.length);
  out[0] = (payload.length >>> 24) & 0xff;
  out[1] = (payload.length >>> 16) & 0xff;
  out[2] = (payload.length >>> 8) & 0xff;
  out[3] = payload.length & 0xff;
  for (let i = 0; i < payload.length; i++) {
    out[4 + i] = payload[i];
  }
  return out.buffer;
}

// ============================================================================
// 1. Filter Tests
// ============================================================================

async function testFilterAdapter(): Promise<void> {
  const persistence: FakeFilterPersistence = new FakeFilterPersistence();
  const statePort: FakeFilterStatePort = new FakeFilterStatePort();
  const adapter: FilterPageAdapter = new FilterPageAdapter(persistence, statePort);

  // Empty load
  const initialRows: FilterDisplayRow[] = await adapter.load();
  eq('Filter: empty load returns 0 rows', initialRows.length, 0);
  eq('Filter: isEmpty is true initially', adapter.isEmpty(), true);
  eq('Filter: visibleView is 1 (empty state)', adapter.visibleView(), 1);
  eq('Filter: statePort synced on load', statePort.syncedCount, 1);

  // Validation: blank input keeps dialog open and writes nothing
  const emptyRes: FilterOperationResult = await adapter.addFilter(FILTER_MODE_TITLE, '   ');
  eq('Filter: empty input ok=false', emptyRes.ok, false);
  eq('Filter: empty input errorResKey=text_is_empty', emptyRes.errorResKey, 'text_is_empty');
  eq('Filter: empty input persists 0 items', persistence.store.length, 0);

  // Add across all 4 modes verifying EhFilter normalization rules
  const rTag: FilterOperationResult = await adapter.addFilter(FILTER_MODE_TAG, '  Female:SwimSuit  ');
  eq('Filter: add TAG succeeds', rTag.ok, true);
  eq('Filter: TAG text lowercased', rTag.record?.text, 'female:swimsuit');

  const rUploader: FilterOperationResult = await adapter.addFilter(FILTER_MODE_UPLOADER, '  MixedCase_Uploader  ');
  eq('Filter: add UPLOADER succeeds', rUploader.ok, true);
  eq('Filter: UPLOADER text preserves case (EhFilter rule)', rUploader.record?.text, 'MixedCase_Uploader');

  const rTitle: FilterOperationResult = await adapter.addFilter(FILTER_MODE_TITLE, '  BAD Title  ');
  eq('Filter: add TITLE succeeds', rTitle.ok, true);
  eq('Filter: TITLE text lowercased', rTitle.record?.text, 'bad title');

  const rNs: FilterOperationResult = await adapter.addFilter(FILTER_MODE_TAG_NAMESPACE, '  Misc  ');
  eq('Filter: add TAG_NAMESPACE succeeds', rNs.ok, true);
  eq('Filter: TAG_NAMESPACE text lowercased', rNs.record?.text, 'misc');

  // Invalid mode falls back to MODE_TITLE
  const rFallback: FilterOperationResult = await adapter.addFilter(99, 'FallbackText');
  eq('Filter: invalid mode falls back to MODE_TITLE', rFallback.record?.mode, EhFilter.MODE_TITLE);
  eq('Filter: fallback title lowercased', rFallback.record?.text, 'fallbacktext');

  // Grouped rows: Title(2) + Uploader(1) + Tag(1) + TagNamespace(1) + 4 headers = 9 rows
  const rows: FilterDisplayRow[] = adapter.buildDisplayRows();
  eq('Filter: grouped row count = 4 headers + 5 items', rows.length, 9);
  eq('Filter: row 0 is Title header', rows[0].isHeader, true);
  eq('Filter: row 0 mode is MODE_HEADER (-1)', rows[0].mode, FILTER_MODE_HEADER);
  eq('Filter: row 0 headerResKey is filter_title', rows[0].headerResKey, 'filter_title');
  eq('Filter: row 1 is first title item', rows[1].text, 'bad title');
  eq('Filter: row 2 is second title item', rows[2].text, 'fallbacktext');
  eq('Filter: row 3 is Uploader header', rows[3].headerResKey, 'filter_uploader');
  eq('Filter: row 4 is Uploader item', rows[4].text, 'MixedCase_Uploader');
  eq('Filter: row 5 is Tag header', rows[5].headerResKey, 'filter_tag');
  eq('Filter: row 6 is Tag item', rows[6].text, 'female:swimsuit');
  eq('Filter: row 7 is TagNamespace header', rows[7].headerResKey, 'filter_tag_namespace');
  eq('Filter: row 8 is TagNamespace item', rows[8].text, 'misc');
  eq('Filter: visibleView is 0 (list)', adapter.visibleView(), 0);
  eq('Filter: onFiltersChanged invoked on each add', persistence.changedCalls, 5);

  // Header guard: MODE_HEADER cannot be triggered or deleted
  eq('Filter: canTrigger(header) = false', FilterPageAdapter.canTrigger(rows[0]), false);
  eq('Filter: canDelete(header) = false', FilterPageAdapter.canDelete(rows[0]), false);
  eq('Filter: toggleFilter(header) = false', await adapter.toggleFilter(rows[0]), false);
  eq('Filter: deleteFilter(header) = false', await adapter.deleteFilter(rows[0]), false);

  // Toggle enabled/disabled (strikethrough state)
  const uploaderRow: FilterDisplayRow = rows[4];
  eq('Filter: item starts enabled=true', uploaderRow.enabled, true);
  eq('Filter: toggle item returns true', await adapter.toggleFilter(uploaderRow), true);
  const afterToggle1: FilterDisplayRow[] = adapter.buildDisplayRows();
  eq('Filter: item toggled to enabled=false', afterToggle1[4].enabled, false);

  // Verify non-mutating persistence port still flips once (no stuck state)
  persistence.mutateOnTrigger = false;
  eq('Filter: second toggle returns true', await adapter.toggleFilter(afterToggle1[4]), true);
  const afterToggle2: FilterDisplayRow[] = adapter.buildDisplayRows();
  eq('Filter: item toggled back to enabled=true', afterToggle2[4].enabled, true);
  persistence.mutateOnTrigger = true;

  // Delete single-item group removes both item and its group header
  eq('Filter: delete uploader item returns true', await adapter.deleteFilter(afterToggle2[4]), true);
  const afterDeleteUploader: FilterDisplayRow[] = adapter.buildDisplayRows();
  eq('Filter: uploader header omitted when group becomes empty', afterDeleteUploader.length, 7);
  ok('Filter: no uploader header remains',
    afterDeleteUploader.every((r: FilterDisplayRow): boolean => r.headerResKey !== 'filter_uploader'));

  // Reload from persistence with unknown mode + null enable default
  persistence.store.push(new Filter(77, 42, 'ignored', true));
  const nullEnableFilter: Filter = new Filter(78, FILTER_MODE_TAG, 'Male:Glasses');
  nullEnableFilter.setEnable(null);
  persistence.store.push(nullEnableFilter);
  const reloaded: FilterDisplayRow[] = await adapter.load();
  const maleTagRow: FilterDisplayRow | undefined = reloaded.find(
    (r: FilterDisplayRow): boolean => !r.isHeader && r.text === 'male:glasses'
  );
  ok('Filter: load skips unknown mode and normalizes TAG text', maleTagRow !== undefined);
  eq('Filter: load defaults enable=null to true', maleTagRow?.enabled, true);

  // Text formatting helpers
  eq('Formatter: %s replacement', P3TextFormatter.formatString('Delete blocker "%s"?', 'spam'), 'Delete blocker "spam"?');
  eq('Formatter: %1$s replacement', P3TextFormatter.formatString('Remove %1$s!', 'userA'), 'Remove userA!');
  eq('Formatter: %d replacement', P3TextFormatter.formatCount('Selected: %d', 7), 'Selected: 7');
  eq('Formatter: %1$d replacement', P3TextFormatter.formatCount('Count=%1$d', 3), 'Count=3');
}

// ============================================================================
// 2. BlackList Tests
// ============================================================================

async function testBlackListAdapter(): Promise<void> {
  const persistence: FakeBlackListPersistence = new FakeBlackListPersistence();
  const statePort: FakeBlackListStatePort = new FakeBlackListStatePort();
  const adapter: BlackListPageAdapter = new BlackListPageAdapter(persistence, statePort);

  const initList: BlackListRecord[] = await adapter.load();
  eq('BlackList: empty initial load', initList.length, 0);
  eq('BlackList: isEmpty=true', adapter.isEmpty(), true);
  eq('BlackList: visibleView=1', adapter.visibleView(), 1);

  // Validation: empty text rejected
  const emptyRes: BlackListOperationResult = await adapter.addItem('   ', 'reason');
  eq('BlackList: empty name ok=false', emptyRes.ok, false);
  eq('BlackList: empty name duplicate=false', emptyRes.duplicate, false);
  eq('BlackList: empty name errorResKey=text_is_empty', emptyRes.errorResKey, 'text_is_empty');
  eq('BlackList: empty name does not insert', persistence.insertCalls, 0);

  // Add item preserving upstream manual constants & hydrating AUTOINCREMENT id
  const fixedTs: number = new Date(2026, 4, 15, 9, 5, 7).getTime();
  const addRes: BlackListOperationResult = await adapter.addItem('  TrollUser  ', '  spam comments  ', fixedTs);
  eq('BlackList: add succeeds', addRes.ok, true);
  eq('BlackList: not duplicate', addRes.duplicate, false);
  eq('BlackList: trimmed badgayname', addRes.record?.badgayname, 'TrollUser');
  eq('BlackList: trimmed reason', addRes.record?.reason, 'spam comments');
  eq('BlackList: manual angrywith preserved', addRes.record?.angrywith, BLACKLIST_MANUAL_ANGRYWITH);
  eq('BlackList: manual angrywith literal is /手动添加/', addRes.record?.angrywith, '/手动添加/');
  eq('BlackList: manual mode is 1', addRes.record?.mode, BLACKLIST_MANUAL_MODE);
  eq('BlackList: add_time formatted YYYY-MM-DD HH:MM:SS', addRes.record?.addTime, '2026-05-15 09:05:07');
  eq('BlackList: AUTOINCREMENT id hydrated after insert', addRes.record?.id, 100);
  eq('BlackList: visibleView=0', adapter.visibleView(), 0);
  eq('BlackList: containsName(TrollUser)=true', adapter.containsName('TrollUser'), true);
  eq('BlackList: statePort mirrors count', statePort.records.length, 1);

  // Duplicate check by badgayname
  const dupRes: BlackListOperationResult = await adapter.addItem('TrollUser', 'second reason', fixedTs);
  eq('BlackList: duplicate ok=false', dupRes.ok, false);
  eq('BlackList: duplicate flag=true', dupRes.duplicate, true);
  eq('BlackList: duplicate does not call insert again', persistence.insertCalls, 1);
  eq('BlackList: record list remains size 1', adapter.getRecords().length, 1);

  // Add second item with empty reason
  const addRes2: BlackListOperationResult = await adapter.addItem('SecondUser', '   ', fixedTs);
  eq('BlackList: second add ok=true', addRes2.ok, true);
  eq('BlackList: empty reason stored as empty string in record', addRes2.record?.reason, '');
  eq('BlackList: null reason stored on DAO entity', persistence.store[1].getReason(), null);

  // Delete first item immediately using hydrated DB id
  const firstRecord: BlackListRecord = addRes.record as BlackListRecord;
  eq('BlackList: delete first item returns true', await adapter.deleteItem(firstRecord), true);
  eq('BlackList: 1 record left after delete', adapter.getRecords().length, 1);
  eq('BlackList: deleted user no longer contained', adapter.containsName('TrollUser'), false);
  eq('BlackList: DB store has 1 remaining item', persistence.store.length, 1);

  // Load skips null/empty badgayname entries
  persistence.store.push(new BlackList(200, undefined, 'bad'));
  const reloaded: BlackListRecord[] = await adapter.load();
  eq('BlackList: load filters out null badgayname rows', reloaded.length, 1);
  eq('BlackList: remaining item is SecondUser', reloaded[0].badgayname, 'SecondUser');

  // Delete remaining returns to empty state
  eq('BlackList: delete remaining returns true', await adapter.deleteItem(reloaded[0]), true);
  eq('BlackList: empty again after all deleted', adapter.isEmpty(), true);
  eq('BlackList: visibleView returns to 1', adapter.visibleView(), 1);
}

// ============================================================================
// 3. MyTags Tests
// ============================================================================

function testMyTagsCoordinator(): void {
  const cookieStore: EhCookieStore = new EhCookieStore(new InMemoryCookieStore());
  cookieStore.addCookie(new CookieBuilder()
    .name(EhCookieStore.KEY_IPD_MEMBER_ID)
    .value('4242')
    .domain(EhUrl.DOMAIN_E)
    .path('/')
    .expiresAt(EhCookieStore.MAX_EXPIRES)
    .build());
  cookieStore.addCookie(new CookieBuilder()
    .name(EhCookieStore.KEY_IPD_PASS_HASH)
    .value('hash999')
    .domain(EhUrl.DOMAIN_E)
    .path('/')
    .expiresAt(EhCookieStore.MAX_EXPIRES)
    .secure()
    .build());

  // Verify formatCookieForWebView omits non-standard expiresAt and keeps RFC attributes
  const sampleCookies: Cookie[] = cookieStore.getCookies(HttpUrl.parse(EhUrl.URL_MY_TAGS_E) as HttpUrl);
  const formattedSample: string = formatCookieForWebView(sampleCookies[0]);
  ok('MyTags: formatted cookie uses Domain= and Path=',
    formattedSample.indexOf('Domain=e-hentai.org') >= 0 && formattedSample.indexOf('Path=/') >= 0);
  ok('MyTags: formatted cookie has no non-RFC expiresAt=', formattedSample.indexOf('expiresAt=') < 0);

  // Strict upstream init order: flush -> removeAll -> removeSession -> setCookie* -> loadUrl
  EhUrl.setSiteConfig(new StaticSiteConfig(EhUrl.SITE_E));
  const backend: FakeWebCookieBackend = new FakeWebCookieBackend();
  const listener: FakeMyTagsListener = new FakeMyTagsListener();
  const coord: MyTagsPageCoordinator = new MyTagsPageCoordinator(backend, cookieStore, listener);

  const initRes: MyTagsInitResult = coord.init();
  eq('MyTags: init ok=true', initRes.ok, true);
  eq('MyTags: target URL is E-site mytags', coord.getUrl(), EhUrl.URL_MY_TAGS_E);
  eq('MyTags: seeded 2 cookies', initRes.cookiesSet, 2);
  eq('MyTags: first 3 cookie ops strictly flush -> removeAll -> removeSession',
    backend.ops.slice(0, 3), ['flush', 'removeAll', 'removeSession']);
  eq('MyTags: 5 total cookie ops (3 clears + 2 sets)', backend.ops.length, 5);
  ok('MyTags: set ops occur strictly after removeSession',
    backend.ops[3].startsWith('set:') && backend.ops[4].startsWith('set:'));
  eq('MyTags: JS enabled', coord.isJavaScriptEnabled(), true);
  eq('MyTags: dialogs enabled', coord.isDialogsEnabled(), true);
  eq('MyTags: back icon set', coord.getNavigationIcon(), DRAWABLE_BACK);
  eq('MyTags: loadUrl called once with mytags URL', listener.loadedUrls, [EhUrl.URL_MY_TAGS_E]);
  eq('MyTags: isCreated=true', coord.isCreated(), true);

  // Exact URL equality whitelist
  eq('MyTags: exact mytags URL allowed (override=false)', coord.shouldOverrideUrlLoading(EhUrl.URL_MY_TAGS_E), false);
  eq('MyTags: sub-path intercepted (override=true)', coord.shouldOverrideUrlLoading(EhUrl.URL_MY_TAGS_E + '/sub'), true);
  eq('MyTags: query string intercepted (override=true)', coord.shouldOverrideUrlLoading(EhUrl.URL_MY_TAGS_E + '?p=1'), true);
  eq('MyTags: same-domain home intercepted', coord.shouldOverrideUrlLoading(EhUrl.HOST_E), true);
  eq('MyTags: external URL intercepted', coord.shouldOverrideUrlLoading('https://example.com/'), true);

  // Progress & home finish
  coord.onPageStarted();
  coord.onPageFinished();
  eq('MyTags: progress toggles true then false', listener.progressEvents, [true, false]);
  eq('MyTags: home click returns true', coord.onHomeClick(), true);
  eq('MyTags: home click triggers finish', listener.finishCalls, 1);

  // EX-site URL resolution
  EhUrl.setSiteConfig(new StaticSiteConfig(EhUrl.SITE_EX));
  const exBackend: FakeWebCookieBackend = new FakeWebCookieBackend();
  const exListener: FakeMyTagsListener = new FakeMyTagsListener();
  const exCoord: MyTagsPageCoordinator = new MyTagsPageCoordinator(exBackend, null, exListener);
  const exInit: MyTagsInitResult = exCoord.init();
  eq('MyTags: EX-site URL resolved', exInit.url, EhUrl.URL_MY_TAGS_EX);
  eq('MyTags: null cookieStore degrades cleanly (0 seeded)', exInit.cookiesSet, 0);
  EhUrl.setSiteConfig(new StaticSiteConfig(EhUrl.SITE_E));

  // Unavailable fallback when WebCookieManager throws
  const brokenBackend: FakeWebCookieBackend = new FakeWebCookieBackend();
  brokenBackend.throwOnClearAll = true;
  const brokenListener: FakeMyTagsListener = new FakeMyTagsListener();
  const brokenCoord: MyTagsPageCoordinator = new MyTagsPageCoordinator(brokenBackend, cookieStore, brokenListener);
  const failRes: MyTagsInitResult = brokenCoord.init();
  eq('MyTags: broken backend init ok=false', failRes.ok, false);
  eq('MyTags: loadUrl NOT called on failure', brokenListener.loadedUrls.length, 0);
  eq('MyTags: unavailable dialog emitted', brokenListener.unavailableDialogs.length, 1);
  eq('MyTags: unavailable dialog title key',
    brokenListener.unavailableDialogs[0].title, STR_WEBVIEW_UNAVAILABLE_TITLE);
  eq('MyTags: unavailable dialog message key',
    brokenListener.unavailableDialogs[0].message, STR_WEBVIEW_UNAVAILABLE_MESSAGE);
  brokenCoord.onUnavailableDialogConfirm();
  eq('MyTags: unavailable confirm triggers finish', brokenListener.finishCalls, 1);
  brokenCoord.onUnavailableDialogCancel();
  eq('MyTags: unavailable cancel also triggers finish', brokenListener.finishCalls, 2);
}

// ============================================================================
// 4. UConfig Tests
// ============================================================================

function testUConfigCoordinator(): void {
  EhUrl.setSiteConfig(new StaticSiteConfig(EhUrl.SITE_E));
  const cookieStore: EhCookieStore = new EhCookieStore(new InMemoryCookieStore());
  cookieStore.addCookie(new CookieBuilder()
    .name(EhCookieStore.KEY_IPD_MEMBER_ID)
    .value('7788')
    .domain(EhUrl.DOMAIN_E)
    .path('/')
    .expiresAt(EhCookieStore.MAX_EXPIRES)
    .build());
  cookieStore.addCookie(new CookieBuilder()
    .name(EhCookieStore.KEY_IPD_PASS_HASH)
    .value('pass7788')
    .domain(EhUrl.DOMAIN_E)
    .path('/')
    .expiresAt(EhCookieStore.MAX_EXPIRES)
    .build());

  const backend: FakeWebCookieBackend = new FakeWebCookieBackend();
  const listener: FakeUConfigListener = new FakeUConfigListener();
  const coord: UConfigPageCoordinator = new UConfigPageCoordinator(backend, cookieStore, listener);

  // Init seeds cookies and starts load
  const initRes: UConfigInitResult = coord.init();
  eq('UConfig: init ok=true', initRes.ok, true);
  eq('UConfig: URL is E-site uconfig.php', initRes.url, EhUrl.URL_UCONFIG_E);
  eq('UConfig: seeded 2 App cookies into ArkWeb', initRes.cookiesSeeded, 2);
  eq('UConfig: clear order flush -> removeAll -> removeSession',
    backend.ops.slice(0, 3), ['flush', 'removeAll', 'removeSession']);
  eq('UConfig: accept cookies enabled', backend.acceptCookie && backend.acceptThirdParty, true);
  eq('UConfig: loadUrl emitted', listener.loadedUrls, [EhUrl.URL_UCONFIG_E]);
  eq('UConfig: progress visible on startLoad', coord.isProgressVisible(), true);
  eq('UConfig: loaded initially false', coord.isLoaded(), false);

  // Progress updates
  coord.onProgressChanged(45);
  eq('UConfig: progress=45 keeps visible', coord.isProgressVisible(), true);
  eq('UConfig: progressValue=45', coord.getProgressValue(), 45);
  coord.onProgressChanged(100);
  eq('UConfig: progress=100 hides bar', coord.isProgressVisible(), false);

  // Page finish harvests updated cookies back into EhCookieStore across BOTH e & ex domains
  backend.fetchedByUrl.set(
    EhUrl.URL_UCONFIG_E,
    'uconfig=tl_r-uh_y-rc_0; sk=newsk123; igneous=ig999; ipb_member_id=7788; ipb_pass_hash=pass7788; nw=1'
  );
  const syncRes: UConfigCookieSyncResult = coord.onPageFinished();
  eq('UConfig: loaded=true after pageFinished', coord.isLoaded(), true);
  eq('UConfig: harvested 5 cookies (nw skipped)', syncRes.syncedCount, 5);
  ok('UConfig: harvested uconfig cookie', syncRes.names.indexOf('uconfig') >= 0);
  ok('UConfig: harvested sk cookie', syncRes.names.indexOf('sk') >= 0);
  ok('UConfig: harvested igneous cookie', syncRes.names.indexOf('igneous') >= 0);

  const eUrl: HttpUrl = HttpUrl.parse(EhUrl.HOST_E) as HttpUrl;
  const exUrl: HttpUrl = HttpUrl.parse(EhUrl.HOST_EX) as HttpUrl;
  eq('UConfig: uconfig synced to e-hentai.org', cookieStore.contains(eUrl, 'uconfig'), true);
  eq('UConfig: uconfig synced to exhentai.org', cookieStore.contains(exUrl, 'uconfig'), true);
  eq('UConfig: sk synced to exhentai.org', cookieStore.contains(exUrl, 'sk'), true);
  eq('UConfig: igneous synced to exhentai.org', cookieStore.contains(exUrl, 'igneous'), true);
  eq('UConfig: EhCookieStore remains signed in', cookieStore.hasSignedIn(), true);

  // Navigation whitelist allows uconfig.php (including POST/query) and blocks external/other paths
  eq('UConfig: exact uconfig URL allowed', coord.shouldOverrideUrlLoading(EhUrl.URL_UCONFIG_E), false);
  eq('UConfig: uconfig with query allowed', coord.shouldOverrideUrlLoading(EhUrl.URL_UCONFIG_E + '?apply=1'), false);
  eq('UConfig: EX uconfig allowed', coord.shouldOverrideUrlLoading(EhUrl.URL_UCONFIG_EX), false);
  eq('UConfig: non-uconfig EH path blocked', coord.shouldOverrideUrlLoading(EhUrl.HOST_E + 'favorites.php'), true);
  eq('UConfig: external URL blocked', coord.shouldOverrideUrlLoading('https://evil.example/uconfig.php'), true);

  // Error & refresh state machine
  coord.onLoadError('ERR_CONNECTION_TIMED_OUT');
  eq('UConfig: error resets loaded=false', coord.isLoaded(), false);
  eq('UConfig: error hides progress', coord.isProgressVisible(), false);
  eq('UConfig: error message stored', coord.getErrorMessage(), 'ERR_CONNECTION_TIMED_OUT');
  coord.onRefresh();
  eq('UConfig: refresh clears error', coord.getErrorMessage(), '');
  eq('UConfig: refresh restores progress visible', coord.isProgressVisible(), true);

  // Back navigation & exit cookie harvest
  eq('UConfig: handleBack(true) navigates WebView back', coord.handleBack(true), UConfigBackAction.WEB_GO_BACK);
  backend.fetchedByUrl.set(EhUrl.URL_UCONFIG_E, 'uconfig=updated_on_exit; sk=exit_sk');
  eq('UConfig: handleBack(false) exits page', coord.handleBack(false), UConfigBackAction.EXIT_PAGE);
  const exitCookies: Cookie[] = cookieStore.getCookies(exUrl);
  const exitUconfig: Cookie | undefined = exitCookies.find((c: Cookie): boolean => c.name() === 'uconfig');
  eq('UConfig: exit back synced updated uconfig value', exitUconfig?.value(), 'updated_on_exit');

  // onDestroy syncs latest cookies too
  backend.fetchedByUrl.set(EhUrl.URL_UCONFIG_E, 'uconfig=destroy_sync');
  const destroySync: UConfigCookieSyncResult = coord.onDestroy();
  eq('UConfig: onDestroy synced 1 cookie', destroySync.syncedCount, 1);
  const destroyCookies: Cookie[] = cookieStore.getCookies(eUrl);
  const destroyUconfig: Cookie | undefined = destroyCookies.find((c: Cookie): boolean => c.name() === 'uconfig');
  eq('UConfig: onDestroy value written to e-hentai.org', destroyUconfig?.value(), 'destroy_sync');

  // APPLY_JS targets #apply
  ok('UConfig: APPLY_JS references #apply element', UConfigPageCoordinator.APPLY_JS.indexOf('getElementById("apply")') >= 0);

  // Init failure fallback
  const brokenBackend: FakeWebCookieBackend = new FakeWebCookieBackend();
  brokenBackend.throwOnClearAll = true;
  const brokenListener: FakeUConfigListener = new FakeUConfigListener();
  const brokenCoord: UConfigPageCoordinator = new UConfigPageCoordinator(brokenBackend, cookieStore, brokenListener);
  const failInit: UConfigInitResult = brokenCoord.init();
  eq('UConfig: broken backend init ok=false', failInit.ok, false);
  eq('UConfig: isInitFailed=true', brokenCoord.isInitFailed(), true);
  eq('UConfig: unavailable dialog emitted', brokenListener.unavailableDialogs.length, 1);
  brokenCoord.onUnavailableDialogConfirm();
  brokenCoord.onUnavailableDialogCancel();
  eq('UConfig: confirm & cancel both call finish', brokenListener.finishCalls, 2);

  // uconfig tl_j / tl_r <-> Settings.show_jpn_title sync
  eq('UConfig parse tl_j', UConfigPageCoordinator.parseShowJpnTitleFromUConfig('uh_y-tl_j-ar_0'), true);
  eq('UConfig parse tl_r', UConfigPageCoordinator.parseShowJpnTitleFromUConfig('uh_y-tl_r-ar_0'), false);
  eq('UConfig parse URL-encoded tl_j',
    UConfigPageCoordinator.parseShowJpnTitleFromUConfig('uh_y%2Dtl_j%2Dar_0'), true);
  eq('UConfig parse without tl token',
    UConfigPageCoordinator.parseShowJpnTitleFromUConfig('uh_y-ar_0'), null);

  const prevShowJpn: boolean = Settings.getShowJpnTitle();
  try {
    Settings.putShowJpnTitle(false);
    backend.fetchedByUrl.set(EhUrl.URL_UCONFIG_E, 'uconfig=uh_y-tl_j-ar_0');
    const jpnRes: UConfigCookieSyncResult = coord.syncCookiesToStore();
    eq('UConfig sync tl_j result field', jpnRes.syncedShowJpnTitle, true);
    eq('UConfig sync tl_j updates Settings.getShowJpnTitle()', Settings.getShowJpnTitle(), true);

    backend.fetchedByUrl.set(EhUrl.URL_UCONFIG_E, 'uconfig=uh_y-tl_r-ar_0');
    const romajiRes: UConfigCookieSyncResult = coord.syncCookiesToStore();
    eq('UConfig sync tl_r result field', romajiRes.syncedShowJpnTitle, false);
    eq('UConfig sync tl_r updates Settings.getShowJpnTitle()', Settings.getShowJpnTitle(), false);

    // 1B uconfig token updater & CookieStore two-way helpers
    eq('UConfig update replaces tl_r -> tl_j',
      UConfigPageCoordinator.updateUConfigShowJpnTitle('uh_y-tl_r-ar_0', true), 'uh_y-tl_j-ar_0');
    eq('UConfig update replaces tl_j -> tl_r',
      UConfigPageCoordinator.updateUConfigShowJpnTitle('uh_y-tl_j-ar_0', false), 'uh_y-tl_r-ar_0');
    eq('UConfig update appends tl_j when missing',
      UConfigPageCoordinator.updateUConfigShowJpnTitle('uh_y-ar_0', true), 'uh_y-ar_0-tl_j');
    eq('UConfig update empty returns empty',
      UConfigPageCoordinator.updateUConfigShowJpnTitle('', true), '');

    const emptyStore: EhCookieStore = new EhCookieStore(new InMemoryCookieStore());
    eq('UConfig syncToCookieStore skips when no uconfig exists',
      UConfigPageCoordinator.syncShowJpnTitleToCookieStore(emptyStore, true), false);
    eq('UConfig syncToCookieStore does not fabricate uconfig on empty store',
      emptyStore.contains(eUrl, 'uconfig'), false);
    eq('UConfig syncFromCookieStore returns null on empty store',
      UConfigPageCoordinator.syncShowJpnTitleFromCookieStore(emptyStore), null);

    eq('UConfig syncToCookieStore updates existing uconfig to tl_j',
      UConfigPageCoordinator.syncShowJpnTitleToCookieStore(cookieStore, true), true);
    eq('UConfig syncFromCookieStore reads tl_j after update',
      UConfigPageCoordinator.syncShowJpnTitleFromCookieStore(cookieStore), true);
    const updatedExUConfig: Cookie | undefined = cookieStore.getCookies(exUrl).find((c: Cookie): boolean => c.name() === 'uconfig');
    eq('UConfig ex domain preserved other segments and switched to tl_j', updatedExUConfig?.value(), 'uh_y-tl_j-ar_0');
  } finally {
    Settings.putShowJpnTitle(prevShowJpn);
  }
}

// ============================================================================
// 5. TagSelector Tests
// ============================================================================

function testTagSelectorCoordinatorAndBus(): void {
  // Build binary EhTagDatabase with 28 female tags + male + parody + CJK garbage tag
  const rawEntries: string[][] = [
    ['f:swimsuit', '泳装'],
    ['f:glasses', '眼镜娘'],
    ['f:ponytail', '马尾'],
    ['f:中文脏标签', '脏标签'],
    ['m:glasses', '眼镜男'],
    ['p:touhou project', '东方Project'],
    ['l:dutch', '荷兰语']
  ];
  // Add 25 more female tags with prefix a..y to verify multi-batch loading & collapse
  const letters: string = 'abcdefghijklmnopqrstuvwxy';
  for (let i = 0; i < letters.length; i++) {
    const ch: string = letters.charAt(i);
    rawEntries.push([`f:${ch}tag`, `女性标签${ch.toUpperCase()}`]);
  }
  const dbBuf: ArrayBuffer = buildBinaryTagDatabase(rawEntries);
  const tagDb: EhTagDatabase = new EhTagDatabase('tag-translations-zh-rCN', dbBuf);

  // Verify AppTagDatabaseIo reads binary file from AppConfig.getFilesDir('tag-translations')
  AppConfig.initialize(new FakeAppContext('/tmp/p3-files', '/tmp/p3-cache'));
  const tagDir: string | null = AppConfig.getFilesDir('tag-translations');
  ok('TagSelector: AppConfig tag-translations dir created', tagDir !== null);
  const dataPath: string = `${tagDir as string}/tag-translations-zh-rCN`;
  const f: fs.File = fs.openSync(dataPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  fs.writeSync(f.fd, dbBuf);
  fs.closeSync(f);
  EhTagDatabase.clearInstance();
  const appIo: AppTagDatabaseIo = new AppTagDatabaseIo();
  const loadedDb: EhTagDatabase | null = EhTagDatabase.getInstance(appIo);
  ok('TagSelector: AppTagDatabaseIo loads EhTagDatabase from sandbox FS', loadedDb !== null);
  eq('TagSelector: loaded DB suggests female:swimsuit',
    loadedDb !== null ? loadedDb.suggest('female:swimsuit').length : 0, 1);

  // Coordinator with zh-CN locale
  const suggester: EhTagDatabaseSuggester = EhTagDatabaseSuggester.fromDatabase(tagDb);
  const coord: TagSelectorPageCoordinator = new TagSelectorPageCoordinator(suggester);
  coord.init('zh-CN', false, 'language:chinese');

  eq('TagSelector: zh-CN sets isChineseSystem=true', coord.isChineseSystem(), true);
  eq('TagSelector: 9 groups created', coord.getActivity().groups.length, 9);
  const langGroup: TagGroup = coord.findGroup('language') as TagGroup;
  eq('TagSelector: Language group has 12 pinned tags (not preloaded)', langGroup.loadedTags.length, 12);
  eq('TagSelector: Language prefixIndex stays 0 until More clicked', langGroup.prefixIndex, 0);
  eq('TagSelector: pinned chinese displays 中文', langGroup.loadedTags[0].show, '中文');

  // Preloaded female group should have tags loaded automatically and CJK garbage key stripped
  const femaleGroup: TagGroup = coord.findGroup('female') as TagGroup;
  ok('TagSelector: Female group preloaded >= 24 tags', femaleGroup.loadedTags.length >= 24);
  ok('TagSelector: CJK garbage key dropped during normalization',
    femaleGroup.loadedTags.every((t): boolean => !TagSelectorActivity.containsCjk(t.key)));
  const swimsuitItem = femaleGroup.loadedTags.find((t): boolean => t.key === 'female:swimsuit');
  eq('TagSelector: zh-CN translates female:swimsuit to 泳装', swimsuitItem?.show, '泳装');

  // Initial query seeded language:chinese
  eq('TagSelector: initial query selected 1 tag', coord.getSelectedCount(), 1);
  eq('TagSelector: initial query text matches', coord.selectedQueryText(), 'language:chinese');

  // Load more & collapse on Language group
  eq('TagSelector: loadNextBatch on language returns true', coord.loadNextBatch('language'), true);
  ok('TagSelector: language now includes loaded language:dutch',
    langGroup.loadedTags.some((t): boolean => t.key === 'language:dutch'));
  const snapAfterMore: TagSelectorGroupSnapshot[] = coord.getGroupSnapshots();
  const langSnap: TagSelectorGroupSnapshot = snapAfterMore[0];
  eq('TagSelector: language expanded shows collapse button', langSnap.showCollapse, true);
  eq('TagSelector: language exhausted prefixes reaches END', langSnap.footerState, FooterState.END);

  eq('TagSelector: collapseGroup resets language visibleCount to 12', coord.collapseGroup('language'), true);
  eq('TagSelector: language visibleCount=12 after collapse', langGroup.visibleCount, 12);
  eq('TagSelector: collapsed language hides collapse button', coord.getGroupSnapshots()[0].showCollapse, false);

  // Keyword search filtering
  coord.setSearchKeyword('泳装');
  const searchSnaps: TagSelectorGroupSnapshot[] = coord.getGroupSnapshots();
  eq('TagSelector: search 泳装 narrows to 1 group', searchSnaps.length, 1);
  eq('TagSelector: search result group is female', searchSnaps[0].namespace, 'female');
  eq('TagSelector: search result contains female:swimsuit', searchSnaps[0].visibleItems[0].key, 'female:swimsuit');
  eq('TagSelector: search snapshot marks hasSearchFilter=true', searchSnaps[0].hasSearchFilter, true);

  // Clear search restores all 9 groups
  coord.setSearchKeyword('');
  eq('TagSelector: clearing search restores 9 groups', coord.getGroupSnapshots().length, 9);

  // Toggle selection, grouped selected panel, remove, clear
  eq('TagSelector: toggle female:swimsuit adds', coord.toggleTag('female:swimsuit', '泳装'), true);
  eq('TagSelector: toggle male:glasses adds', coord.toggleTag('male:glasses', '眼镜男'), true);
  eq('TagSelector: toggle unnamespaced tag adds', coord.toggleTag('customtag', 'CustomTag'), true);
  eq('TagSelector: selectedCount is 4', coord.getSelectedCount(), 4);
  eq('TagSelector: query text space-joined in insertion order',
    coord.selectedQueryText(), 'language:chinese female:swimsuit male:glasses customtag');

  const selGroups: SelectedTagGroup[] = coord.getSelectedGroups();
  eq('TagSelector: 4 selected namespace groups', selGroups.length, 4);
  eq('TagSelector: group order Language -> Female -> Male -> Other',
    [selGroups[0].title, selGroups[1].title, selGroups[2].title, selGroups[3].title],
    ['Language', 'Female', 'Male', 'tag_selector_other_group']);

  coord.removeSelected('male:glasses');
  eq('TagSelector: removeSelected reduces count to 3', coord.getSelectedCount(), 3);
  eq('TagSelector: toggle existing removes it', coord.toggleTag('customtag', 'CustomTag'), false);
  eq('TagSelector: selectedQueryText after removals',
    coord.selectedQueryText(), 'language:chinese female:swimsuit');

  // ResultBus: pending mode
  TagSelectorResultBus.clear();
  const confirmed: string = coord.confirmSelection();
  eq('TagSelector: confirmSelection returns query text', confirmed, 'language:chinese female:swimsuit');
  eq('TagSelectorResultBus: hasPendingResult=true', TagSelectorResultBus.hasPendingResult(), true);
  eq('TagSelectorResultBus: peek returns query without clearing',
    TagSelectorResultBus.peekPendingResult(), 'language:chinese female:swimsuit');
  eq('TagSelectorResultBus: consume returns query',
    TagSelectorResultBus.consumePendingResult(), 'language:chinese female:swimsuit');
  eq('TagSelectorResultBus: second consume returns null',
    TagSelectorResultBus.consumePendingResult(), null);

  // ResultBus: listener callback mode
  const delivered: string[] = [];
  TagSelectorResultBus.setListener((q: string): void => {
    delivered.push(q);
  });
  coord.confirmSelection();
  eq('TagSelectorResultBus: listener invoked immediately', delivered, ['language:chinese female:swimsuit']);
  eq('TagSelectorResultBus: no stale pending after listener delivery',
    TagSelectorResultBus.hasPendingResult(), false);

  // ResultBus: throwing listener handled safely
  TagSelectorResultBus.setListener((_q: string): void => {
    throw new Error('caller crash');
  });
  coord.confirmSelection();
  ok('TagSelectorResultBus: throwing listener does not crash confirmSelection', true);
  TagSelectorResultBus.clear();

  // Clear selection
  coord.clearSelected();
  eq('TagSelector: clearSelected empties selection', coord.isEmptySelection(), true);

  // English system forces English labels even when DB has Chinese translations
  const enCoord: TagSelectorPageCoordinator = new TagSelectorPageCoordinator(suggester);
  enCoord.init('en-US', true, '');
  eq('TagSelector: en-US sets isChineseSystem=false', enCoord.isChineseSystem(), false);
  eq('TagSelector: darkMode persisted', enCoord.getDarkMode(), true);
  eq('TagSelector: en-US pinned language is Chinese', enCoord.findGroup('language')?.loadedTags[0].show, 'Chinese');
  const enSwimsuit = enCoord.findGroup('female')?.loadedTags.find((t): boolean => t.key === 'female:swimsuit');
  eq('TagSelector: en-US forces Swimsuit instead of 泳装', enSwimsuit?.show, 'Swimsuit');

  // Graceful fallback when EhTagDatabase is null (not downloaded)
  const nullSuggester: EhTagDatabaseSuggester = EhTagDatabaseSuggester.fromDatabase(null);
  const offlineCoord: TagSelectorPageCoordinator = new TagSelectorPageCoordinator(nullSuggester);
  offlineCoord.init('zh-CN', false, '');
  eq('TagSelector: offline fallback keeps 12 pinned languages',
    offlineCoord.findGroup('language')?.loadedTags.length, 12);
  eq('TagSelector: offline female group converges to 0 without crashing',
    offlineCoord.findGroup('female')?.loadedTags.length, 0);
  eq('TagSelector: footer fallback text zh',
    TagSelectorPageCoordinator.footerMoreText(true, ''), '▼ 更多');
  eq('TagSelector: footer fallback text en',
    TagSelectorPageCoordinator.footerCollapseText(false, ''), '▲ Collapse');
  eq('TagSelector: footer prefers resource string when present',
    TagSelectorPageCoordinator.footerEndText(false, 'Custom End'), 'Custom End');
}

async function main(): Promise<void> {
  await testFilterAdapter();
  await testBlackListAdapter();
  testMyTagsCoordinator();
  testUConfigCoordinator();
  testTagSelectorCoordinatorAndBus();

  if (failures.length > 0) {
    console.error(`\n✗ P3 tests failed: ${failures.length} / ${passed + failures.length} assertions`);
    for (let i = 0; i < failures.length; i++) {
      console.error('  - ' + failures[i]);
    }
    throw new Error('p3-filter-blacklist-tags tests failed');
  }
  console.log(`✓ P3 Filter/BlackList/MyTags/UConfig/TagSelector: ${passed} assertions passed`);
}

main().catch((err: Error): void => {
  console.error(err.stack !== undefined ? err.stack : err.message);
  throw err;
});
