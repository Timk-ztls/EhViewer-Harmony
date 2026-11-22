/*
 * Stage C Track P5 阅读器引擎协同 / API 20 按键映射 / 外部归档 Want / Shortcuts S1 单测
 */

import { Want } from '@kit.AbilityKit';
import {
  ACTION_DIR,
  ACTION_EH,
  ACTION_VIEW,
  GalleryActivity,
  KeyAction,
  KeyCode,
  LayoutMode,
  ProviderKind
} from '../../main/ets/hippo/ehviewer/ui/GalleryActivity';
import { ShortcutsActivity } from '../../main/ets/hippo/ehviewer/shortcuts/ShortcutsActivity';
import { DownloadService } from '../../main/ets/hippo/ehviewer/download/DownloadService';
import {
  FallbackReason,
  OHOS_ACTION_VIEW_DATA,
  ProgressThrottle,
  ReaderEngineCoordinator,
  ReaderRouteRequest,
  RenderEngineMode,
  computeSafeDownloadPercent,
  mapArkKeyCodeToGalleryKeyCode,
  resolveZoomedEdgeTurn
} from '../../main/ets/hippo/ui/reader/ReaderEngineCoordinator';
import {
  ExternalWantRouter,
  LaunchIntentKind,
  ParsedLaunchRequest,
  PendingLaunchBus,
  WantLike
} from '../../main/ets/hippo/ui/ExternalWantRouter';

let pass = 0;
const fails: string[] = [];

function eq(name: string, got: unknown, want: unknown): void {
  const g = JSON.stringify(got);
  const w = JSON.stringify(want);
  if (g === w) {
    pass++;
  } else {
    fails.push(`${name}\n    got  ${g}\n    want ${w}`);
  }
}

function ok(name: string, cond: boolean): void {
  if (cond) {
    pass++;
  } else {
    fails.push(name);
  }
}

// ================================================================ 1) ReaderEngineCoordinator
{
  const coord = new ReaderEngineCoordinator();
  coord.reset(4, 20);
  eq('initial mode GL_PENDING', coord.getMode(), RenderEngineMode.GL_PENDING);
  eq('initial page preserved', coord.getCurrentPage(), 4);
  eq('initial totalPages preserved', coord.getTotalPages(), 20);

  // Watchdog timeout during GL_PENDING -> SWIPER_FALLBACK
  ok('watchdog during GL_PENDING triggers fallback', coord.onWatchdogTimeout());
  eq('fallback mode after watchdog', coord.getMode(), RenderEngineMode.SWIPER_FALLBACK);
  eq('fallback reason WATCHDOG_TIMEOUT', coord.getFallbackReason(), FallbackReason.WATCHDOG_TIMEOUT);
  eq('page preserved after fallback', coord.getCurrentPage(), 4);
  eq('duplicate fallback is idempotent false', coord.onWatchdogTimeout(), false);

  // Ready -> GL_ACTIVE -> watchdog ignored
  coord.reset(2, 10);
  coord.onGlSurfaceReady();
  eq('GL_ACTIVE after surface ready', coord.isGlActive(), true);
  eq('watchdog after GL_ACTIVE ignored', coord.onWatchdogTimeout(), false);
  eq('stays GL_ACTIVE', coord.getMode(), RenderEngineMode.GL_ACTIVE);

  // Non-fatal frame error streak reset on success, fallback on 3rd error
  eq('1st non-fatal error stays GL', coord.onGlRenderError(1, false), false);
  eq('2nd non-fatal error stays GL', coord.onGlRenderError(2, false), false);
  coord.onGlFrameSuccess();
  eq('success resets consecutiveErrors', coord.getConsecutiveErrors(), 0);
  eq('1st error after reset stays GL', coord.onGlRenderError(1, false), false);
  eq('2nd error stays GL', coord.onGlRenderError(2, false), false);
  eq('3rd consecutive error triggers fallback', coord.onGlRenderError(3, false), true);
  eq('fallback reason CONSECUTIVE_RENDER_ERRORS', coord.getFallbackReason(), FallbackReason.CONSECUTIVE_RENDER_ERRORS);

  // Fatal init error triggers immediate fallback
  coord.reset(1, 5);
  ok('fatal init error triggers immediate fallback', coord.onGlRenderError(1, true));
  eq('fallback reason SURFACE_INIT_FAILED', coord.getFallbackReason(), FallbackReason.SURFACE_INIT_FAILED);

  // ARKUI_PRIMARY default mode ignores GL watchdog and GL errors
  coord.useArkUiPrimary(3, 18);
  eq('ARKUI_PRIMARY mode set', coord.getMode(), RenderEngineMode.ARKUI_PRIMARY);
  eq('isArkUiPrimary true', coord.isArkUiPrimary(), true);
  eq('isArkUiMode true', coord.isArkUiMode(), true);
  eq('ARKUI_PRIMARY currentPage preserved', coord.getCurrentPage(), 3);
  eq('ARKUI_PRIMARY totalPages preserved', coord.getTotalPages(), 18);
  eq('watchdog ignored in ARKUI_PRIMARY', coord.onWatchdogTimeout(), false);
  eq('fatal GL error ignored in ARKUI_PRIMARY', coord.onGlRenderError(1, true), false);
  eq('triggerFallback ignored in ARKUI_PRIMARY', coord.triggerFallback(FallbackReason.BACKEND_UNAVAILABLE), false);
  eq('remains ARKUI_PRIMARY', coord.getMode(), RenderEngineMode.ARKUI_PRIMARY);
}

// ================================================================ 2) ReaderRouteRequest & API 20 KeyCode 映射
{
  const archParams: Record<string, Object> = {
    'action': OHOS_ACTION_VIEW_DATA,
    'uri': 'file://docs/storage/Users/currentUser/Download/Test%20Comic.cbz',
    'page': 3
  };
  const archReq = ReaderRouteRequest.fromParams(archParams);
  eq('viewData normalized to ACTION_VIEW', archReq.action, ACTION_VIEW);
  eq('archive provider plan kind', archReq.providerPlan.kind, ProviderKind.ARCHIVE);
  eq('archive decoded title fallback', archReq.title, 'Test Comic.cbz');
  eq('archive initial page', archReq.page, 3);

  const dirParams: Record<string, Object> = {
    'action': ACTION_DIR,
    'filename': '/data/storage/el2/base/files/EhViewer/download/12345-abc'
  };
  const dirReq = ReaderRouteRequest.fromParams(dirParams);
  eq('dir provider plan kind', dirReq.providerPlan.kind, ProviderKind.DIR);
  eq('dir title derived from dirname', dirReq.title, '12345-abc');

  const ehParams: Record<string, Object> = {
    'gid': 98765,
    'token': 'deadbeef01',
    'pages': 42,
    'page': 7,
    'title': 'Sample EH'
  };
  const ehReq = ReaderRouteRequest.fromParams(ehParams);
  eq('eh implicit action', ehReq.action, ACTION_EH);
  eq('eh provider plan kind', ehReq.providerPlan.kind, ProviderKind.EH);

  // API 20 KeyCodes -> GalleryActivity KeyCodes -> KeyAction
  eq('VOL_UP 16 -> KeyCode.VOLUME_UP', mapArkKeyCodeToGalleryKeyCode(16), KeyCode.VOLUME_UP);
  eq('VOL_DOWN 17 -> KeyCode.VOLUME_DOWN', mapArkKeyCodeToGalleryKeyCode(17), KeyCode.VOLUME_DOWN);
  eq('DPAD_UP 2012', mapArkKeyCodeToGalleryKeyCode(2012), KeyCode.DPAD_UP);
  eq('DPAD_DOWN 2013', mapArkKeyCodeToGalleryKeyCode(2013), KeyCode.DPAD_DOWN);
  eq('DPAD_LEFT 2014', mapArkKeyCodeToGalleryKeyCode(2014), KeyCode.DPAD_LEFT);
  eq('DPAD_RIGHT 2015', mapArkKeyCodeToGalleryKeyCode(2015), KeyCode.DPAD_RIGHT);
  eq('DPAD_CENTER 2016', mapArkKeyCodeToGalleryKeyCode(2016), KeyCode.DPAD_CENTER);
  eq('SPACE 2050', mapArkKeyCodeToGalleryKeyCode(2050), KeyCode.SPACE);
  eq('MENU 2067', mapArkKeyCodeToGalleryKeyCode(2067), KeyCode.MENU);
  eq('PAGE_UP 2068', mapArkKeyCodeToGalleryKeyCode(2068), KeyCode.PAGE_UP);
  eq('PAGE_DOWN 2069', mapArkKeyCodeToGalleryKeyCode(2069), KeyCode.PAGE_DOWN);
  eq('unknown key -> -1', mapArkKeyCodeToGalleryKeyCode(9999), -1);

  eq('API 20 MENU 2067 -> TAP_MENU',
    GalleryActivity.keyActionFor(mapArkKeyCodeToGalleryKeyCode(2067), true, false, LayoutMode.RIGHT_TO_LEFT),
    KeyAction.TAP_MENU);
  eq('API 20 VOL_UP 16 RTL unReverse -> PAGE_RIGHT',
    GalleryActivity.keyActionFor(mapArkKeyCodeToGalleryKeyCode(16), true, false, LayoutMode.RIGHT_TO_LEFT),
    KeyAction.PAGE_RIGHT);

  // 2A: computeSafeDownloadPercent
  eq('percent unknown total -1 -> -1', computeSafeDownloadPercent(-1, 500), -1);
  eq('percent zero total -> -1', computeSafeDownloadPercent(0, 500), -1);
  eq('percent NaN total -> -1', computeSafeDownloadPercent(Number.NaN, 100), -1);
  eq('percent Infinity -> -1', computeSafeDownloadPercent(Number.POSITIVE_INFINITY, 100), -1);
  eq('percent negative received -> -1', computeSafeDownloadPercent(100, -1), -1);
  eq('percent 0/100 -> 0', computeSafeDownloadPercent(100, 0), 0);
  eq('percent 50/100 -> 50', computeSafeDownloadPercent(100, 50), 50);
  eq('percent overflow 150/100 -> 100', computeSafeDownloadPercent(100, 150), 100);

  // 2A: ProgressThrottle
  const throttle = new ProgressThrottle();
  eq('throttle first push 0% emits', throttle.shouldEmit(0, 1000), true);
  eq('throttle duplicate 0% suppressed', throttle.shouldEmit(0, 1010), false);
  eq('throttle +1% within 85ms suppressed', throttle.shouldEmit(1, 1020), false);
  eq('throttle +3% within 32ms frame guard suppressed', throttle.shouldEmit(3, 1020), false);
  eq('throttle +3% after 32ms emits', throttle.shouldEmit(3, 1040), true);
  eq('throttle +1% after 85ms emits', throttle.shouldEmit(4, 1130), true);
  eq('throttle 100% final push always emits immediately', throttle.shouldEmit(100, 1131), true);
  eq('throttle duplicate 100% suppressed', throttle.shouldEmit(100, 1200), false);

  // 3A: resolveZoomedEdgeTurn
  eq('edgeTurn inside bounds -> none', resolveZoomedEdgeTurn(0, 200, -50, 0, 500), 'none');
  eq('edgeTurn recent pinch < 250ms -> none', resolveZoomedEdgeTurn(-200, 200, -100, 0, 120), 'none');
  eq('edgeTurn vertical dominant drag -> none', resolveZoomedEdgeTurn(-200, 200, -90, 90, 500), 'none');
  eq('edgeTurn dragged slightly past right edge (-40) -> none', resolveZoomedEdgeTurn(-200, 200, -40, 0, 500), 'none');
  eq('edgeTurn dragged past right edge (-80) -> right', resolveZoomedEdgeTurn(-200, 200, -80, 10, 500), 'right');
  eq('edgeTurn dragged past left edge (+80) -> left', resolveZoomedEdgeTurn(200, 200, 80, -10, 500), 'left');
}

// ================================================================ 3) ExternalWantRouter & ShortcutsActivity S1 & PendingLaunchBus
{
  const notifWant: WantLike = {
    parameters: { 'download_action': 'pause' }
  };
  eq('notification want -> NOTIFICATION',
    ExternalWantRouter.parseWant(notifWant, false).kind, LaunchIntentKind.NOTIFICATION);

  const viewWant: WantLike = {
    action: ExternalWantRouter.OHOS_ACTION_VIEW_DATA,
    uri: 'file://docs/storage/Users/currentUser/Download/bundle.zip'
  };
  const parsedArchive = ExternalWantRouter.parseWant(viewWant, true);
  eq('viewData zip -> READER_ARCHIVE', parsedArchive.kind, LaunchIntentKind.READER_ARCHIVE);
  ok('archive bypasses Gates 2-5 (only Gate 1 runs)', ExternalWantRouter.shouldBypassAuthGates(parsedArchive));
  const routeParams = ExternalWantRouter.toReaderRouteParams(parsedArchive);
  eq('route params action', routeParams['action'], ACTION_VIEW);
  eq('route params title', routeParams['title'], 'bundle.zip');

  const shortcutColdWant: WantLike = {
    parameters: { 'shortcut_action': DownloadService.ACTION_START_ALL }
  };
  const parsedColdSc = ExternalWantRouter.parseWant(shortcutColdWant, true);
  eq('cold shortcut kind', parsedColdSc.kind, LaunchIntentKind.SHORTCUT);
  eq('cold shortcut action', parsedColdSc.shortcutAction, 'start_all');
  eq('cold shortcut navigates to DownloadsScene', ExternalWantRouter.shouldNavigateDownloadsOnShortcut(parsedColdSc), true);

  const shortcutHotWant: WantLike = {
    parameters: { 'shortcut_action': DownloadService.ACTION_STOP_ALL }
  };
  const parsedHotSc = ExternalWantRouter.parseWant(shortcutHotWant, false);
  eq('hot shortcut kind', parsedHotSc.kind, LaunchIntentKind.SHORTCUT);
  eq('hot shortcut keeps current page (no nav)', ExternalWantRouter.shouldNavigateDownloadsOnShortcut(parsedHotSc), false);

  // ShortcutsActivity.getAction / isShortcutWant
  const sdkWant: Want = {
    action: 'action.system.home',
    parameters: { 'shortcut_action': 'stop_all' }
  };
  eq('ShortcutsActivity prefers parameters.shortcut_action over action',
    ShortcutsActivity.getAction(sdkWant), 'stop_all');
  ok('ShortcutsActivity.isShortcutWant true', ShortcutsActivity.isShortcutWant(sdkWant));

  // PendingLaunchBus cold queue + hot subscription
  const bus = PendingLaunchBus.getInstance();
  bus.resetForTest();
  bus.publish(parsedArchive);
  const consumed = bus.consumePending();
  ok('bus queued cold launch', consumed !== null && consumed.uri === viewWant.uri);
  eq('consumePending clears queue', bus.consumePending(), null);

  const received: ParsedLaunchRequest[] = [];
  const listener = (req: ParsedLaunchRequest): void => {
    received.push(req);
  };
  bus.subscribe(listener);
  bus.publish(parsedHotSc);
  eq('live subscriber notified once', received.length, 1);
  eq('hot event action stop_all', received[0].shortcutAction, 'stop_all');
  eq('live delivery does not retain pending', bus.peekPending(), null);
  bus.unsubscribe(listener);
  bus.resetForTest();
}

if (fails.length > 0) {
  console.error(`\n${fails.length} 个断言失败：`);
  for (const f of fails) {
    console.error(`  ✗ ${f}`);
  }
  console.error(`\n通过 ${pass}，失败 ${fails.length}`);
  throw new Error(`p5-reader-want-shortcuts failed: ${fails.length} assertions`);
}
console.log(`✓ p5-reader-want-shortcuts: 全部通过 ${pass} 个断言`);
