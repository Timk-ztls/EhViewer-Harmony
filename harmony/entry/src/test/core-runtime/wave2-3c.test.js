// Wave 2 (3C) unit tests: theme auto-switch, read progress cache, EH event pane bus, cellular warning
global.Observed = (target) => target;
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out11', 'hippo');

const { Settings } = require(path.join(OUT, 'ehviewer', 'Settings.js'));
const { ReadProgressCache } = require(path.join(OUT, 'ehviewer', 'ReadProgressCache.js'));
const { EhEventPaneBus } = require(path.join(OUT, 'ehviewer', 'EhEventPaneBus.js'));
const { OhosNetworkMonitor, CellularNetworkWarningGuard } =
  require(path.join(OUT, 'ehviewer', 'OhosNetworkMonitor.js'));
const { EhEngine } = require(path.join(OUT, 'ehviewer', 'client', 'EhEngine.js'));
const {
  THEME_MODE_LIGHT,
  THEME_MODE_DARK,
  THEME_MODE_BLACK,
  SYSTEM_COLOR_MODE_NOT_SET,
  SYSTEM_COLOR_MODE_DARK,
  SYSTEM_COLOR_MODE_LIGHT,
  ThemeAutoSwitchHelper
} = require(path.join(OUT, 'ui', 'ThemeAutoSwitchHelper.js'));
const { ReaderNetworkRecoveryGuard } = require(path.join(OUT, 'ui', 'reader', 'ReaderEngineCoordinator.js'));

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a);
  const B = JSON.stringify(b);
  if (A === B) {
    console.log('  PASS  ' + label);
  } else {
    fail++;
    console.log('  FAIL  ' + label + '\n    actual:   ' + A + '\n    expected: ' + B);
  }
};

(async () => {
  // ---- 1. Dark follow system (theme_auto_switch + system_theme) ----
  ThemeAutoSwitchHelper.resetForTest();

  eq(
    ThemeAutoSwitchHelper.resolveApplicationColorMode(THEME_MODE_LIGHT, true),
    SYSTEM_COLOR_MODE_NOT_SET,
    'theme_auto_switch=true -> COLOR_MODE_NOT_SET for LIGHT'
  );
  eq(
    ThemeAutoSwitchHelper.resolveApplicationColorMode(THEME_MODE_DARK, true),
    SYSTEM_COLOR_MODE_NOT_SET,
    'theme_auto_switch=true -> COLOR_MODE_NOT_SET for DARK'
  );
  eq(
    ThemeAutoSwitchHelper.resolveApplicationColorMode(THEME_MODE_BLACK, true),
    SYSTEM_COLOR_MODE_NOT_SET,
    'theme_auto_switch=true -> COLOR_MODE_NOT_SET for BLACK'
  );
  eq(
    [
      ThemeAutoSwitchHelper.resolveApplicationColorMode(THEME_MODE_LIGHT, false),
      ThemeAutoSwitchHelper.resolveApplicationColorMode(THEME_MODE_DARK, false),
      ThemeAutoSwitchHelper.resolveApplicationColorMode(THEME_MODE_BLACK, false)
    ],
    [SYSTEM_COLOR_MODE_LIGHT, SYSTEM_COLOR_MODE_DARK, SYSTEM_COLOR_MODE_DARK],
    'theme_auto_switch=false locks LIGHT / DARK accordingly'
  );

  eq(
    ThemeAutoSwitchHelper.resolveEffectiveTheme(THEME_MODE_LIGHT, true, SYSTEM_COLOR_MODE_DARK, THEME_MODE_DARK),
    THEME_MODE_DARK,
    'autoSwitch + system dark + darkVariant=DARK -> DARK'
  );
  eq(
    ThemeAutoSwitchHelper.resolveEffectiveTheme(THEME_MODE_LIGHT, true, SYSTEM_COLOR_MODE_DARK, THEME_MODE_BLACK),
    THEME_MODE_BLACK,
    'autoSwitch + system dark + darkVariant=BLACK -> BLACK'
  );
  eq(
    ThemeAutoSwitchHelper.resolveEffectiveTheme(THEME_MODE_BLACK, true, SYSTEM_COLOR_MODE_LIGHT, THEME_MODE_BLACK),
    THEME_MODE_LIGHT,
    'autoSwitch + system light -> LIGHT regardless of darkVariant'
  );
  eq(
    ThemeAutoSwitchHelper.resolveEffectiveTheme(THEME_MODE_BLACK, false, SYSTEM_COLOR_MODE_LIGHT, THEME_MODE_DARK),
    THEME_MODE_BLACK,
    'autoSwitch=false keeps saved BLACK theme on light system'
  );

  eq(
    ThemeAutoSwitchHelper.shouldDisableAutoSwitchOnManualTheme(THEME_MODE_BLACK, true, SYSTEM_COLOR_MODE_DARK),
    false,
    'switching DARK <-> BLACK under system dark preserves autoSwitch'
  );
  eq(
    ThemeAutoSwitchHelper.shouldDisableAutoSwitchOnManualTheme(THEME_MODE_LIGHT, true, SYSTEM_COLOR_MODE_DARK),
    true,
    'choosing LIGHT under system dark disables autoSwitch'
  );
  eq(
    ThemeAutoSwitchHelper.shouldDisableAutoSwitchOnManualTheme(THEME_MODE_DARK, true, SYSTEM_COLOR_MODE_LIGHT),
    true,
    'choosing DARK under system light disables autoSwitch'
  );

  const encoded = ThemeAutoSwitchHelper.encodeThemeCache(THEME_MODE_LIGHT, true, THEME_MODE_BLACK);
  eq(encoded, '0|1|2', 'encodeThemeCache encodes themeId|auto|darkVariant');
  const coldDark = ThemeAutoSwitchHelper.decodeThemeCache(encoded, SYSTEM_COLOR_MODE_DARK);
  eq([coldDark.themeId, coldDark.autoSwitch, coldDark.darkVariant], [THEME_MODE_BLACK, true, THEME_MODE_BLACK],
    'decodeThemeCache resolves system dark -> BLACK on cold start');
  const legacyDark = ThemeAutoSwitchHelper.decodeThemeCache('2', SYSTEM_COLOR_MODE_LIGHT);
  eq([legacyDark.themeId, legacyDark.autoSwitch], [THEME_MODE_BLACK, false],
    'decodeThemeCache supports legacy numeric theme_id.cache');

  eq(ThemeAutoSwitchHelper.resolveSystemThemeStringKey(SYSTEM_COLOR_MODE_DARK), 'settings_eh_theme_dark',
    'system_theme key for dark mode');
  eq(ThemeAutoSwitchHelper.resolveSystemThemeStringKey(SYSTEM_COLOR_MODE_LIGHT), 'settings_eh_theme_light',
    'system_theme key for light mode');
  eq(ThemeAutoSwitchHelper.resolveSystemThemeStringKey(SYSTEM_COLOR_MODE_NOT_SET), '',
    'system_theme key when unset');

  Settings.putThemeDarkVariant(THEME_MODE_BLACK);
  eq(Settings.getThemeDarkVariant(), THEME_MODE_BLACK, 'Settings.putThemeDarkVariant round-trips BLACK');
  Settings.putThemeDarkVariant(THEME_MODE_LIGHT);
  eq(Settings.getThemeDarkVariant(), THEME_MODE_DARK, 'Settings.putThemeDarkVariant clamps invalid light -> DARK');

  // ---- 2. Read progress in-memory cache + async loader ----
  ReadProgressCache.resetForTest();

  const v2Bytes = Buffer.from('VERSION2\n0000000b\n123456\nabcdef\n', 'ascii');
  eq(ReadProgressCache.parseStartPageFromHeaderBytes(new Uint8Array(v2Bytes)), 11,
    'parseStartPageFromHeaderBytes parses VERSION2 hex 0000000b -> 11');
  const v1Bytes = Buffer.from('00000003\n123456\n', 'ascii');
  eq(ReadProgressCache.parseStartPageFromHeaderBytes(new Uint8Array(v1Bytes)), 3,
    'parseStartPageFromHeaderBytes parses VERSION1 hex 00000003 -> 3');
  eq(ReadProgressCache.parseStartPageFromHeaderBytes(new Uint8Array(Buffer.from('VERSION99\n0000000b\n', 'ascii'))), 0,
    'parseStartPageFromHeaderBytes ignores unsupported VERSION');

  eq(ReadProgressCache.formatPagesLabel(100, 48, false, true), '',
    'show_gallery_pages=false hides pages even when show_read_progress=true');
  eq(ReadProgressCache.formatPagesLabel(100, 48, true, false), '48P',
    'show_read_progress=false formats plain 48P');
  eq(ReadProgressCache.formatPagesLabel(100, 48, true, true), '48P',
    'cache miss initially renders 48P without blocking');

  let loaderCalls = 0;
  const listenerBatches = [];
  const rpListener = (gids) => listenerBatches.push(gids.slice().sort((a, b) => a - b));
  ReadProgressCache.addListener(rpListener);
  ReadProgressCache.setAsyncLoader(async (gid) => {
    loaderCalls++;
    if (gid === 100) return 11;
    if (gid === 101) return 0;
    return 0;
  });

  await ReadProgressCache.prefetchGids([100, 101, 100]);
  eq(loaderCalls, 2, 'prefetchGids deduplicates GIDs in same batch');
  await ReadProgressCache.prefetchGids([100, 101]);
  eq(loaderCalls, 2, 'prefetchGids hits memory cache on subsequent scroll without reloading');
  eq(listenerBatches.length, 1, 'prefetchGids notifies listener in batched callback');
  eq(listenerBatches[0], [100, 101], 'batched notification carries fetched GIDs');
  eq(ReadProgressCache.formatPagesLabel(100, 48, true, true), '12/48P',
    'cached startPage=11 -> 12/48P');
  eq(ReadProgressCache.formatPagesLabel(101, 20, true, true), '0/20P',
    'cached startPage=0 -> 0/20P');

  ReadProgressCache.update(100, 29);
  eq(ReadProgressCache.formatPagesLabel(100, 48, true, true), '30/48P',
    'reader ReadProgressCache.update immediately updates list label to 30/48P');
  ReadProgressCache.update(100, 99);
  eq(ReadProgressCache.formatPagesLabel(100, 48, true, true), '48/48P',
    'formatPagesLabel clamps display page to total pages');

  // ---- 3. E-Hentai events dialog bus & HTML sanitizer ----
  EhEventPaneBus.resetForTest();
  let loggedIn = true;
  Settings.setLoginProvider(() => loggedIn);
  Settings.setKeyShowEhEvents(true);

  const formattedHtml = EhEventPaneBus.formatEventHtml(
    '<div id="eventpane"><p>Happy <strong>New Year</strong>!<br/>Credits &amp; GP &nbsp;awarded&#39;!</p></div>'
  );
  eq(formattedHtml, "Happy New Year!\nCredits & GP awarded'!",
    'formatEventHtml strips tags and decodes entities');

  // Queues before UI subscriber attaches
  const bus = EhEventPaneBus.getInstance();
  eq(bus.publishHtml('<p>You gained 500 GP</p>'), true,
    'publishHtml queues event when show_eh_events=true & logged in');
  eq(bus.publishHtml('<p>You gained 500 GP</p>'), false,
    'publishHtml deduplicates identical event content within session');
  const pendingMsg = bus.consumePending();
  eq(pendingMsg !== null && pendingMsg.body === 'You gained 500 GP', true,
    'consumePending delivers queued event');

  // Direct delivery + EhEngine._eventPaneHook integration
  const delivered = [];
  bus.subscribe((msg) => delivered.push(msg.body));
  EhEngine.setEventPaneHook({
    showEventPane: (html) => {
      bus.publishHtml(html);
    }
  });
  eq(bus.publishHtml('<p>Dawn of a New Day!</p>'), true,
    'subscribed listener receives new event immediately');
  eq(delivered, ['Dawn of a New Day!'], 'listener received clean event text');

  // Disabled or logged-out guards
  Settings.setKeyShowEhEvents(false);
  eq(bus.publishHtml('<p>Should be blocked</p>'), false,
    'show_eh_events=false blocks event pane delivery');
  Settings.setKeyShowEhEvents(true);
  loggedIn = false;
  eq(bus.publishHtml('<p>Should be blocked when logged out</p>'), false,
    'logged out blocks event pane delivery');
  loggedIn = true;

  // ---- 4. Cellular network warning ----
  CellularNetworkWarningGuard.resetForTest();
  OhosNetworkMonitor.setCellularActiveOverrideForTest(null);

  eq(OhosNetworkMonitor.classifyCellularBearers([0]), true,
    'BEARER_CELLULAR only -> cellular=true');
  eq(OhosNetworkMonitor.classifyCellularBearers([1]), false,
    'BEARER_WIFI -> cellular=false');
  eq(OhosNetworkMonitor.classifyCellularBearers([1, 0]), false,
    'BEARER_WIFI + BEARER_CELLULAR -> cellular=false');
  eq(OhosNetworkMonitor.classifyCellularBearers([4], [[4], [0]]), true,
    'VPN default net over cellular -> cellular=true');
  eq(OhosNetworkMonitor.classifyCellularBearers([4], [[4], [1]]), false,
    'VPN default net over Wi-Fi -> cellular=false');
  eq(OhosNetworkMonitor.classifyCellularBearers([]), false,
    'no active network -> cellular=false');

  Settings.putCellularNetworkWarning(false);
  OhosNetworkMonitor.setCellularActiveOverrideForTest(true);
  let warnCount = 0;
  CellularNetworkWarningGuard.setWarningListener(() => { warnCount++; });
  eq(CellularNetworkWarningGuard.checkAndNotify(), false,
    'cellular_network_warning=false does not warn');

  Settings.putCellularNetworkWarning(true);
  CellularNetworkWarningGuard.setWarningListener(null);
  eq(CellularNetworkWarningGuard.checkAndNotify(), false,
    'missing UI listener does not consume session warning flag');
  eq(CellularNetworkWarningGuard.hasWarnedThisSession(), false,
    'session flag remains false until listener handles it');

  CellularNetworkWarningGuard.setWarningListener(() => { warnCount++; });
  OhosNetworkMonitor.setCellularActiveOverrideForTest(false);
  eq(CellularNetworkWarningGuard.checkAndNotify(), false,
    'non-cellular network does not trigger warning');

  OhosNetworkMonitor.setCellularActiveOverrideForTest(true);
  eq(CellularNetworkWarningGuard.checkAndNotify(), true,
    'enabled + cellular + listener warns once');
  eq(warnCount, 1, 'warning callback invoked once');
  eq(CellularNetworkWarningGuard.checkAndNotify(), false,
    'second check in same cellular stint is deduplicated');
  eq(warnCount, 1, 'warning callback still invoked only once');

  // Transient offline keeps warning deduplicated on same cellular stint
  OhosNetworkMonitor.setCellularActiveOverrideForTest(false);
  OhosNetworkMonitor.setWifiOrEthernetActiveOverrideForTest(false);
  eq(CellularNetworkWarningGuard.checkAndNotify(), false,
    'offline does not warn');
  OhosNetworkMonitor.setCellularActiveOverrideForTest(true);
  eq(CellularNetworkWarningGuard.checkAndNotify(), false,
    'returning from brief offline without Wi-Fi stays deduplicated');

  // Connecting to Wi-Fi / Ethernet resets the flag (even when UI listener is null!)
  CellularNetworkWarningGuard.setWarningListener(null);
  OhosNetworkMonitor.setCellularActiveOverrideForTest(false);
  OhosNetworkMonitor.setWifiOrEthernetActiveOverrideForTest(true);
  eq(CellularNetworkWarningGuard.checkAndNotify(), false,
    'Wi-Fi active does not trigger cellular warning');
  eq(CellularNetworkWarningGuard.hasWarnedThisSession(), false,
    'connecting to Wi-Fi resets cellular warning flag automatically');

  // Returning to cellular warns once again
  CellularNetworkWarningGuard.setWarningListener(() => { warnCount++; });
  OhosNetworkMonitor.setWifiOrEthernetActiveOverrideForTest(false);
  OhosNetworkMonitor.setCellularActiveOverrideForTest(true);
  eq(CellularNetworkWarningGuard.checkAndNotify(), true,
    'switching back from Wi-Fi to cellular warns again without restarting app');
  eq(warnCount, 2, 'warning callback invoked second time after Wi-Fi reset');
  eq(CellularNetworkWarningGuard.checkAndNotify(), false,
    'continuous cellular remains deduplicated after second warning');

  eq(OhosNetworkMonitor.classifyWifiOrEthernetBearers([1]), true,
    'classifyWifiOrEthernetBearers: BEARER_WIFI -> true');
  eq(OhosNetworkMonitor.classifyWifiOrEthernetBearers([3]), true,
    'classifyWifiOrEthernetBearers: BEARER_ETHERNET -> true');
  eq(OhosNetworkMonitor.classifyWifiOrEthernetBearers([4], [[4], [1]]), true,
    'classifyWifiOrEthernetBearers: VPN over Wi-Fi -> true');
  eq(OhosNetworkMonitor.classifyWifiOrEthernetBearers([4], [[4], [0]]), false,
    'classifyWifiOrEthernetBearers: VPN over cellular -> false');
  eq(OhosNetworkMonitor.classifyWifiOrEthernetBearers([0]), false,
    'classifyWifiOrEthernetBearers: BEARER_CELLULAR -> false');

  // ---- 5. Debounced network recovery & ReaderNetworkRecoveryGuard ----
  OhosNetworkMonitor.resetRecoveryForTest();
  const recoveryEpochs = [];
  OhosNetworkMonitor.addNetworkRecoveryListener((ep) => recoveryEpochs.push(ep));

  const sigWifi = OhosNetworkMonitor.buildNetworkSignature(101, [1], false, [[1]], ['192.168.1.10']);
  const sigCell = OhosNetworkMonitor.buildNetworkSignature(102, [0], false, [[0]], ['10.0.0.5']);
  const sigCellVpn = OhosNetworkMonitor.buildNetworkSignature(103, [0, 4], true, [[0, 4]], ['10.0.0.5', '172.18.0.2']);

  eq(OhosNetworkMonitor.notifyNetworkSignatureForRecovery(sigWifi, 25), false,
    'initial network baseline does not trigger spurious recovery');
  eq(OhosNetworkMonitor.notifyNetworkSignatureForRecovery(sigWifi, 25), false,
    'identical stable network signature does not trigger recovery');

  // Burst of transitions collapses into one debounced recovery event
  eq(OhosNetworkMonitor.notifyNetworkSignatureForRecovery(sigCell, 25), true,
    'switch Wi-Fi -> Cellular schedules recovery');
  eq(OhosNetworkMonitor.notifyNetworkSignatureForRecovery(OhosNetworkMonitor.OFFLINE_SIGNATURE, 25), false,
    'transient offline cancels pending recovery until reconnected');
  await new Promise((r) => setTimeout(r, 40));
  eq(recoveryEpochs.length, 0, 'recovery never fires while offline');

  eq(OhosNetworkMonitor.notifyNetworkSignatureForRecovery(sigCell, 25), true,
    'reconnecting after offline schedules recovery');
  eq(OhosNetworkMonitor.notifyNetworkSignatureForRecovery(sigCellVpn, 25), true,
    'VPN activation within debounce window resets debounce timer');
  await new Promise((r) => setTimeout(r, 45));
  eq(recoveryEpochs, [1], 'burst collapses into single debounced recovery epoch 1');

  // Subsequent VPN disconnect triggers epoch 2
  eq(OhosNetworkMonitor.notifyNetworkSignatureForRecovery(sigCell, 25), true,
    'VPN toggle off schedules recovery epoch 2');
  await new Promise((r) => setTimeout(r, 45));
  eq(recoveryEpochs, [1, 2], 'settled VPN disconnect emits recovery epoch 2');

  const guard = new ReaderNetworkRecoveryGuard();
  eq(guard.canRetryErrorPage(1, 5, 'connect timeout'), true,
    'ReaderNetworkRecoveryGuard allows first retry on network error');
  eq(guard.canRetryErrorPage(1, 5, 'connect timeout'), false,
    'ReaderNetworkRecoveryGuard blocks duplicate retry within same epoch');
  eq(guard.canRetryErrorPage(2, 5, 'HTTP 509: Bandwidth Limit Exceeded'), false,
    'ReaderNetworkRecoveryGuard never auto-retries HTTP 509');
  eq(guard.canRetryErrorPage(2, 5, 'GP不足 / Insufficient GP'), false,
    'ReaderNetworkRecoveryGuard never auto-retries Insufficient GP');
  eq(guard.canRetryErrorPage(2, 5, 'reset'), true, 'epoch 2 allows retry #2');
  eq(guard.canRetryErrorPage(3, 5, 'reset'), true, 'epoch 3 allows retry #3');
  eq(guard.canRetryErrorPage(4, 5, 'reset'), false,
    'ReaderNetworkRecoveryGuard caps retries at MAX_AUTO_RETRIES_PER_PAGE=3');
  guard.onPageReady(5);
  eq(guard.canRetryErrorPage(5, 5, 'reset'), true,
    'onPageReady clears page auto-retry counter');

  guard.armPendingForLoading(6, 8, 1000);
  eq(guard.consumePendingRetryOnFailure(7, 'aborted', 1200), false,
    'armed pending failure ignores non-matching page');
  eq(guard.consumePendingRetryOnFailure(8, 'aborted', 1200), true,
    'armed pending failure triggers deferred retry for aborted loading current page');
  eq(guard.consumePendingRetryOnFailure(8, 'aborted', 1300), false,
    'armed pending failure consumes cleanly without duplicate retries');

  OhosNetworkMonitor.resetRecoveryForTest();
  OhosNetworkMonitor.setCellularActiveOverrideForTest(null);
  CellularNetworkWarningGuard.resetForTest();
  ReadProgressCache.resetForTest();
  EhEventPaneBus.resetForTest();

  console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
  process.exit(fail === 0 ? 0 : 1);
})();
