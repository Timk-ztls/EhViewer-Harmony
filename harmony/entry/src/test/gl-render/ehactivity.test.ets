/*
 * EhActivity 纯逻辑单测
 *
 * `EhActivity` 上游是 Activity 基类，绝大部分能力在鸿蒙侧要映射到页面/窗口（D-051）。
 * 但有两段是**纯函数**，且都是"容易理解反"的那种，所以必须钉住：
 *
 * 1. `parseLocaleTag(language)` —— 上游 `attachBaseContext` 里 `split("-")` 的 1/2/3 段分支
 * 2. `shouldSwitchTheme(isSystemDark)` —— 上游 `(Settings.getTheme() == 0) == isDark` 这个双重否定
 */

import {
  EhActivity,
  EhActivitySettings,
  EhActivitySettingsHolder,
  UnwiredEhActivitySettings
} from '../../main/ets/hippo/ehviewer/ui/EhActivity';

let pass = 0;
const fails: string[] = [];
function eq(name: string, got: unknown, want: unknown): void {
  const g = JSON.stringify(got);
  const w = JSON.stringify(want);
  if (g === w) { pass++; } else { fails.push(`${name}: got ${g} want ${w}`); }
}

/** 可配置的假设置（用于驱动 shouldSwitchTheme）。 */
class FakeSettings implements EhActivitySettings {
  THEME_LIGHT: number = 0;
  THEME_DARK: number = 1;
  THEME_BLACK: number = 2;

  theme: number = 0;
  autoSwitch: boolean = true;
  security: boolean = false;
  language: string | null = 'system';
  putThemeCalls: number[] = [];

  getTheme(): number { return this.theme; }
  putTheme(theme: number): void { this.theme = theme; this.putThemeCalls.push(theme); }
  isThemeAutoSwitchAvailable(): boolean { return this.autoSwitch; }
  getAppLanguage(): string | null { return this.language; }
  getEnabledSecurity(): boolean { return this.security; }
}

/** 具体化 EhActivity（只需实现 getThemeResId）。 */
class ProbeActivity extends EhActivity {
  protected getThemeResId(theme: number): number {
    return 100 + theme;
  }

  // 暴露 protected 的 settings 供测试替换
  useSettings(s: EhActivitySettings): void {
    EhActivitySettingsHolder.set(s);
  }
}

// ---------- 1) parseLocaleTag ----------
{
  eq('system → null', EhActivity.parseLocaleTag('system'), null);
  eq('null → null', EhActivity.parseLocaleTag(null), null);
  eq('empty → null', EhActivity.parseLocaleTag(''), null);
  eq('1 part', EhActivity.parseLocaleTag('zh'), 'zh');
  eq('2 parts', EhActivity.parseLocaleTag('zh-CN'), 'zh-CN');
  eq('3 parts', EhActivity.parseLocaleTag('zh-Hans-CN'), 'zh-Hans-CN');
  // 上游：split.length > 3 时**不设 locale**（这里同样回落 null）
  eq('4 parts → null (upstream falls back to system)', EhActivity.parseLocaleTag('a-b-c-d'), null);
  // 脏数据：空段直接回落（上游会 new Locale("zh","") 这种半残值，这里更严格，见注释）
  eq('empty segment → null', EhActivity.parseLocaleTag('zh--CN'), null);
}

// ---------- 2) getThemeResId 走 Settings.getTheme() ----------
{
  const fake = new FakeSettings();
  fake.theme = 2;   // BLACK
  const act = new ProbeActivity();
  act.useSettings(fake);
  act.setPageId('probe');
  act.onCreate();
  eq('themeResId follows Settings.getTheme()', act.getAppliedThemeResId(), 102);
  eq('page registered on create', EhActivity.isPageAlive('probe'), true);
  act.onDestroy();
  eq('page unregistered on destroy', EhActivity.isPageAlive('probe'), false);
  EhActivity.resetPageRegistry();
}

// ---------- 3) shouldSwitchTheme：双重否定的语义 ----------
{
  const fake = new FakeSettings();
  fake.autoSwitch = true;
  const act = new ProbeActivity();
  act.useSettings(fake);

  fake.theme = 0;   // 浅色
  eq('light + system light → no switch', act.shouldSwitchTheme(false), false);
  eq('light + system dark → switch', act.shouldSwitchTheme(true), true);

  fake.theme = 1;   // 深色
  eq('dark + system dark → no switch', act.shouldSwitchTheme(true), false);
  eq('dark + system light → switch', act.shouldSwitchTheme(false), true);

  fake.autoSwitch = false;
  eq('auto switch disabled → never switch', act.shouldSwitchTheme(true), false);
}

// ---------- 4) applyThemeSwitch 写入方向 ----------
{
  const fake = new FakeSettings();
  const act = new ProbeActivity();
  act.useSettings(fake);
  act.applyThemeSwitch(true);
  eq('system dark → THEME_DARK written', fake.theme, fake.THEME_DARK);
  act.applyThemeSwitch(false);
  eq('system light → THEME_LIGHT written', fake.theme, fake.THEME_LIGHT);
  eq('two putTheme calls', fake.putThemeCalls.length, 2);
}

// ---------- 5) 未接线实现的默认值必须偏安全侧 ----------
{
  const unwired = new UnwiredEhActivitySettings();
  eq('unwired theme = LIGHT (upstream default)', unwired.getTheme(), 0);
  eq('unwired security = false (upstream default)', unwired.getEnabledSecurity(), false);
  eq('unwired language = system', unwired.getAppLanguage(), 'system');
  eq('unwired autoSwitch = false (never silently change theme)',
    unwired.isThemeAutoSwitchAvailable(), false);
}

// ---------- 6) 页面注册表 ----------
{
  EhActivity.resetPageRegistry();
  EhActivity.registerPage('a');
  EhActivity.registerPage('b');
  EhActivity.registerPage('a');   // 幂等
  eq('alive count', EhActivity.alivePageCount(), 2);
  EhActivity.unregisterPage('a');
  eq('alive count after unregister', EhActivity.alivePageCount(), 1);
  EhActivity.unregisterPage('not-exist');   // 不应抛错
  eq('unregister missing is no-op', EhActivity.alivePageCount(), 1);
  EhActivity.resetPageRegistry();
}

EhActivitySettingsHolder.reset();

console.log(`PASS ${pass}  FAIL ${fails.length}`);
for (const f of fails) console.log('  x ' + f);
process.exit(fails.length === 0 ? 0 : 1);
