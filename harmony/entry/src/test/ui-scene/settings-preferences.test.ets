import { Settings } from '../../main/ets/hippo/ehviewer/Settings';
import { ProxyType as SelectorProxyType } from '../../main/ets/hippo/ehviewer/EhProxySelector';
import { EhFragment, InMemoryThemeStore } from '../../main/ets/hippo/ehviewer/ui/fragment/EhFragment';
import {
  AdvancedFragment,
  AdvancedActionsLike,
  SettingsLoadingStatusStore
} from '../../main/ets/hippo/ehviewer/ui/fragment/AdvancedFragment';
import {
  PrivacySettingsRules,
  AnalyticsTogglePlan
} from '../../main/ets/hippo/ehviewer/ui/fragment/PrivacySettingsRules';
import {
  THEME_LIGHT as ACTIVITY_THEME_LIGHT,
  THEME_DARK as ACTIVITY_THEME_DARK,
  THEME_BLACK as ACTIVITY_THEME_BLACK
} from '../../main/ets/hippo/ehviewer/ui/SettingsActivity';
import { PreferenceActions } from '../../main/ets/hippo/ehviewer/preference/PreferenceActions';
import { InetValidator } from '../../main/ets/hippo/network/InetValidator';
import { Hosts } from '../../main/ets/hippo/ehviewer/Hosts';

let pass: number = 0;
const fails: string[] = [];

function eq(name: string, got: Object | null, want: Object | null): void {
  const g: string = JSON.stringify(got);
  const w: string = JSON.stringify(want);
  if (g === w) {
    pass++;
  } else {
    fails.push(`${name}: got ${g}, want ${w}`);
  }
}

function ok(name: string, cond: boolean): void {
  if (cond) {
    pass++;
  } else {
    fails.push(`${name}: expected true, got false`);
  }
}

class NoopAdvancedActions implements AdvancedActionsLike {
  async dumpLogcat(): Promise<void> {}
  async clearMemoryCache(): Promise<void> {}
  openAppLanguage(): void {}
  async importData(): Promise<void> {}
  openWifiServer(): void {}
  openWifiClient(): void {}
}

function testPrivacySettingsRules(): void {
  const key: string = 'enable_analytics';
  const pTrue: AnalyticsTogglePlan = PrivacySettingsRules.planAnalyticsToggle(key, true, key);
  eq('primitive boolean true triggers analytics', [pTrue.accept, pTrue.shouldStartAnalytics], [true, true]);

  const pFalse: AnalyticsTogglePlan = PrivacySettingsRules.planAnalyticsToggle(key, false, key);
  eq('primitive boolean false does not trigger analytics', [pFalse.accept, pFalse.shouldStartAnalytics], [true, false]);

  const boxedTrue: Object = new Boolean(true);
  const pBoxedTrue: AnalyticsTogglePlan = PrivacySettingsRules.planAnalyticsToggle(key, boxedTrue, key);
  eq('boxed Boolean(true) triggers analytics', [pBoxedTrue.accept, pBoxedTrue.shouldStartAnalytics], [true, true]);

  const boxedFalse: Object = new Boolean(false);
  const pBoxedFalse: AnalyticsTogglePlan = PrivacySettingsRules.planAnalyticsToggle(key, boxedFalse, key);
  eq('boxed Boolean(false) does not trigger analytics', [pBoxedFalse.accept, pBoxedFalse.shouldStartAnalytics], [true, false]);

  const pStr: AnalyticsTogglePlan = PrivacySettingsRules.planAnalyticsToggle(key, 'true', key);
  eq('non-boolean value does not trigger analytics', [pStr.accept, pStr.shouldStartAnalytics], [true, false]);

  const pOther: AnalyticsTogglePlan = PrivacySettingsRules.planAnalyticsToggle('other_key', true, key);
  eq('other key ignores analytics toggle', [pOther.accept, pOther.shouldStartAnalytics], [true, false]);
}

function testEhFragmentThemeAlignment(): void {
  eq('EhFragment themes align with Settings.THEME_*',
    [EhFragment.THEME_LIGHT, EhFragment.THEME_DARK, EhFragment.THEME_BLACK],
    [Settings.THEME_LIGHT, Settings.THEME_DARK, Settings.THEME_BLACK]);
  eq('EhFragment themes align with SettingsActivity themes',
    [EhFragment.THEME_LIGHT, EhFragment.THEME_DARK, EhFragment.THEME_BLACK],
    [ACTIVITY_THEME_LIGHT, ACTIVITY_THEME_DARK, ACTIVITY_THEME_BLACK]);

  const store: InMemoryThemeStore = new InMemoryThemeStore();
  const frag: EhFragment = new EhFragment(store);
  ok('accepts THEME_LIGHT (0)', frag.onPreferenceChange(EhFragment.KEY_THEME, EhFragment.THEME_LIGHT));
  eq('stored mode = 0', store.getThemeMode(), 0);
  ok('accepts THEME_DARK (1)', frag.onPreferenceChange(EhFragment.KEY_THEME, EhFragment.THEME_DARK));
  eq('stored mode = 1', store.getThemeMode(), 1);
  ok('accepts THEME_BLACK (2)', frag.onPreferenceChange(EhFragment.KEY_THEME, EhFragment.THEME_BLACK));
  eq('stored mode = 2', store.getThemeMode(), 2);
  ok('rejects invalid theme (-1)', !frag.onPreferenceChange(EhFragment.KEY_THEME, -1));
  eq('invalid theme preserves previous mode (2)', store.getThemeMode(), 2);
}

function testAdvancedFragmentAndNetworkSettings(): void {
  const keys: string[] = AdvancedFragment.getNetworkPreferenceKeys();
  eq('network preference keys order', keys, [
    AdvancedFragment.KEY_PROXY,
    AdvancedFragment.KEY_BUILT_IN_HOSTS,
    AdvancedFragment.KEY_BUILT_EX_HOSTS,
    AdvancedFragment.KEY_CUSTOM_HOSTS,
    AdvancedFragment.KEY_DOH,
    AdvancedFragment.KEY_DOMAIN_FRONTING
  ]);

  ok('applyNetworkSwitch built-in hosts', AdvancedFragment.applyNetworkSwitch(AdvancedFragment.KEY_BUILT_IN_HOSTS, false));
  eq('Settings.getBuiltInHosts updated', Settings.getBuiltInHosts(), false);
  ok('applyNetworkSwitch built-in hosts true', AdvancedFragment.applyNetworkSwitch(AdvancedFragment.KEY_BUILT_IN_HOSTS, true));
  eq('Settings.getBuiltInHosts true', Settings.getBuiltInHosts(), true);

  ok('applyNetworkSwitch built-ex hosts', AdvancedFragment.applyNetworkSwitch(AdvancedFragment.KEY_BUILT_EX_HOSTS, false));
  eq('Settings.getBuiltEXHosts updated', Settings.getBuiltEXHosts(), false);

  ok('applyNetworkSwitch DoH', AdvancedFragment.applyNetworkSwitch(AdvancedFragment.KEY_DOH, true));
  eq('Settings.getDoH updated', Settings.getDoH(), true);

  ok('applyNetworkSwitch DF', AdvancedFragment.applyNetworkSwitch(AdvancedFragment.KEY_DOMAIN_FRONTING, true));
  eq('Settings.getDF updated', Settings.getDF(), true);

  ok('applyNetworkSwitch rejects unknown key', !AdvancedFragment.applyNetworkSwitch('unknown', true));

  const store: SettingsLoadingStatusStore = new SettingsLoadingStatusStore();
  const frag: AdvancedFragment = new AdvancedFragment(store, new NoopAdvancedActions());
  eq('loading status store round-trip', [frag.getPreferenceKeys().length, store.getProgress()], [6, 100]);
  store.setProgress(42);
  eq('SettingsLoadingStatusStore saves progress', store.getProgress(), 42);
}

function testProxyCategoriesNamespacesAndValidators(): void {
  eq('EhProxySelector constants',
    [SelectorProxyType.TYPE_DIRECT, SelectorProxyType.TYPE_SYSTEM, SelectorProxyType.TYPE_HTTP, SelectorProxyType.TYPE_SOCKS],
    [0, 1, 2, 3]);

  Settings.putProxyType(SelectorProxyType.TYPE_HTTP);
  Settings.putProxyIp('127.0.0.1');
  Settings.putProxyPort(8080);
  eq('Settings proxy HTTP persisted', [Settings.getProxyType(), Settings.getProxyIp(), Settings.getProxyPort()], [2, '127.0.0.1', 8080]);

  Settings.putProxyType(SelectorProxyType.TYPE_DIRECT);
  eq('Settings proxy DIRECT persisted', Settings.getProxyType(), 0);

  ok('InetValidator valid port 0', InetValidator.isValidInetPort(0));
  ok('InetValidator valid port 65535', InetValidator.isValidInetPort(65535));
  ok('InetValidator invalid port -1', !InetValidator.isValidInetPort(-1));
  ok('InetValidator invalid port 65536', !InetValidator.isValidInetPort(65536));

  Settings.putDefaultCategories(0x01 | 0x04);
  eq('DefaultCategories bitmask persisted', Settings.getDefaultCategories(), 0x05);

  Settings.putExcludedTagNamespaces(0x01 | 0x20);
  eq('ExcludedTagNamespaces bitmask persisted', Settings.getExcludedTagNamespaces(), 0x21);

  ok('Hosts host validation rejects uppercase', !Hosts.isValidHost('Example.COM'));
  ok('Hosts host validation accepts lowercase', Hosts.isValidHost('e-hentai.org'));
  ok('Hosts IP validation accepts IPv4 and IPv6', Hosts.isValidIp('1.1.1.1') && Hosts.isValidIp('2001:DB8::1'));
}

async function testPreferenceActionsAndLogin(): Promise<void> {
  let cleared: boolean = false;
  await PreferenceActions.clearDownloadPathCache(async (): Promise<void> => {
    cleared = true;
  });
  ok('PreferenceActions.clearDownloadPathCache invokes callback', cleared);
  Settings.setLoginState(false);
  pass++;
}

async function main(): Promise<void> {
  testPrivacySettingsRules();
  testEhFragmentThemeAlignment();
  testAdvancedFragmentAndNetworkSettings();
  testProxyCategoriesNamespacesAndValidators();
  await testPreferenceActionsAndLogin();
  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('settings-preferences test failed');
  }
  console.log(`✓ 设置与偏好修复单测: ${pass} 条断言全部通过`);
}

main().catch((err: Object): void => {
  console.error(err);
  throw err;
});
