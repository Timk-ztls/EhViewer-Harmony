// MiuiOptimizationHelper：设备判定 + 通知优先级 + 鸿蒙映射
global.Observed = (target) => target;
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out11');
const { MiuiOptimizationHelper, NotificationImportance, SdkVersion } =
  require(path.join(OUT, 'ehviewer', 'util', 'MiuiOptimizationHelper.js'));

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};

// 造一个设备属性（默认是"鸿蒙/非小米"）
const dev = (over) => Object.assign({
  manufacturer: 'HUAWEI', brand: 'HUAWEI', model: 'Mate', display: 'HarmonyOS',
  versionRelease: '5.0', sdkInt: 0, miuiVersionCode: null, miuiVersionName: null,
}, over);

// ── 常量 ──
eq([NotificationImportance.IMPORTANCE_HIGH, NotificationImportance.IMPORTANCE_DEFAULT,
    NotificationImportance.IMPORTANCE_LOW], [4, 3, 2], 'IMPORTANCE_HIGH/DEFAULT/LOW = 4/3/2');
eq([SdkVersion.Q, SdkVersion.UPSIDE_DOWN_CAKE], [29, 34], 'SDK Q=29 / UPSIDE_DOWN_CAKE=34');
eq([MiuiOptimizationHelper.KEY_MIUI_VERSION_CODE, MiuiOptimizationHelper.KEY_MIUI_VERSION_NAME],
  ['ro.miui.ui.version.code', 'ro.miui.ui.version.name'], '两个 MIUI 属性键与上游一致');

// ── isMiuiDevice：三个厂商名（忽略大小写）+ 属性非空 ──
eq(MiuiOptimizationHelper.isMiuiDevice(dev({ manufacturer: 'Xiaomi' })), true, 'Xiaomi → true');
eq(MiuiOptimizationHelper.isMiuiDevice(dev({ manufacturer: 'xiaomi' })), true, 'xiaomi（小写）→ true');
eq(MiuiOptimizationHelper.isMiuiDevice(dev({ manufacturer: 'Redmi' })), true, 'Redmi → true');
eq(MiuiOptimizationHelper.isMiuiDevice(dev({ manufacturer: 'POCO' })), true, 'POCO → true');
eq(MiuiOptimizationHelper.isMiuiDevice(dev({ manufacturer: 'HUAWEI' })), false, 'HUAWEI → false');
eq(MiuiOptimizationHelper.isMiuiDevice(dev({ manufacturer: 'HONOR' })), false, 'HONOR → false');
eq(MiuiOptimizationHelper.isMiuiDevice(dev({ manufacturer: 'Xiaomi', miuiVersionCode: '' })), true,
  "厂商是 Xiaomi、属性为空串 → true（厂商名就够）");
eq(MiuiOptimizationHelper.isMiuiDevice(dev({ manufacturer: 'Unknown', miuiVersionCode: '14' })), true,
  '**厂商不认识但 ro.miui.ui.version.code 有值 → true**（上游 || 的右半边）');
eq(MiuiOptimizationHelper.isMiuiDevice(dev({ manufacturer: 'Unknown', miuiVersionCode: '' })), false,
  '厂商不认识 + 属性空串 → false（空串不算"非空"）');

// ── getMiuiVersion：正则 V(\d+) 优先，回落 version code ──
eq(MiuiOptimizationHelper.getMiuiVersion(dev({ manufacturer: 'Xiaomi', miuiVersionName: 'V14' })), 14,
  "版本名 'V14' → 14");
eq(MiuiOptimizationHelper.getMiuiVersion(dev({ manufacturer: 'Xiaomi', miuiVersionName: 'V816' })), 816,
  "版本名 'V816' → 816（多位数字照取）");
eq(MiuiOptimizationHelper.getMiuiVersion(dev({ manufacturer: 'Xiaomi', miuiVersionName: 'V13.0.5' })), 13,
  "版本名 'V13.0.5' → 13（正则只取 V 后连续数字）");
eq(MiuiOptimizationHelper.getMiuiVersion(dev({ manufacturer: 'Xiaomi', miuiVersionName: 'noVhere',
  miuiVersionCode: '13' })), 13, '版本名无 V → 回落到 version code 13');
eq(MiuiOptimizationHelper.getMiuiVersion(dev({ manufacturer: 'Xiaomi', miuiVersionName: null,
  miuiVersionCode: 'abc' })), -1, 'version code 非数字 → -1');
eq(MiuiOptimizationHelper.getMiuiVersion(dev({ manufacturer: 'Xiaomi' })), -1, '两者都没有 → -1');
eq(MiuiOptimizationHelper.getMiuiVersion(dev({ manufacturer: 'HUAWEI', miuiVersionName: 'V14' })), -1,
  '**非小米设备即使属性有值 → -1**（上游第一行就 return -1）');

// ── isHyperOsDevice：版本 ≥14 或 DISPLAY 含 HyperOS ──
eq(MiuiOptimizationHelper.isHyperOsDevice(dev({ manufacturer: 'Xiaomi', miuiVersionName: 'V14' })), true,
  'MIUI 14 → HyperOS 判定 true');
eq(MiuiOptimizationHelper.isHyperOsDevice(dev({ manufacturer: 'Xiaomi', miuiVersionName: 'V13' })), false,
  'MIUI 13 且 DISPLAY 无 HyperOS → false');
eq(MiuiOptimizationHelper.isHyperOsDevice(dev({ manufacturer: 'Xiaomi', miuiVersionName: 'V13',
  display: 'HyperOS 1.0' })), true, 'MIUI 13 但 DISPLAY 含 "HyperOS" → true');
eq(MiuiOptimizationHelper.isHyperOsDevice(dev({ manufacturer: 'Xiaomi', miuiVersionName: 'V13',
  display: 'hyperos' })), true, '…忽略大小写');
eq(MiuiOptimizationHelper.isHyperOsDevice(dev({ manufacturer: 'HUAWEI', display: 'HyperOS' })), false,
  '**非小米设备不可能是 HyperOS**（isMiui 是 && 的左半边）');

// ── needsMiuiOptimization：isMiui && SDK≥29 ──
eq(MiuiOptimizationHelper.needsMiuiOptimization(dev({ manufacturer: 'Xiaomi', sdkInt: 29 })), true, 'Xiaomi + SDK29 → true');
eq(MiuiOptimizationHelper.needsMiuiOptimization(dev({ manufacturer: 'Xiaomi', sdkInt: 28 })), false, 'Xiaomi + SDK28 → false');
eq(MiuiOptimizationHelper.needsMiuiOptimization(dev({ manufacturer: 'HUAWEI', sdkInt: 34 })), false,
  '非小米 + SDK34 → false（只认小米）');

// ── needsAggressiveOptimization：SDK≥34 || HyperOS ──
eq(MiuiOptimizationHelper.needsAggressiveOptimization(dev({ sdkInt: 34 })), true, 'SDK34 → true（任何厂商）');
eq(MiuiOptimizationHelper.needsAggressiveOptimization(dev({ sdkInt: 33 })), false, 'SDK33 → false');
eq(MiuiOptimizationHelper.needsAggressiveOptimization(dev({ manufacturer: 'Xiaomi',
  miuiVersionName: 'V14', sdkInt: 30 })), true, 'HyperOS（MIUI14）+ SDK30 → true');

// ── 鸿蒙映射：sdkInt=0 + 非小米 → 全部 false，通知走 LOW ──
const harmony = dev({});
eq(MiuiOptimizationHelper.isMiuiDevice(harmony), false, '鸿蒙（HUAWEI, 无 MIUI 属性）→ 非小米');
eq(MiuiOptimizationHelper.needsMiuiOptimization(harmony), false, '…不做 MIUI 优化');
eq(MiuiOptimizationHelper.needsAggressiveOptimization(harmony), false, '**…不做激进优化**（sdkInt=0 走 HyperOS 分支 → false）');
eq(MiuiOptimizationHelper.getRecommendedNotificationImportance(harmony), NotificationImportance.IMPORTANCE_LOW,
  '…通知优先级落到 **LOW**（与上游"其他设备"路径一致）');

// ── 通知优先级三分支 ──
eq(MiuiOptimizationHelper.getRecommendedNotificationImportance(dev({ manufacturer: 'Xiaomi', sdkInt: 30 })),
  NotificationImportance.IMPORTANCE_HIGH, '小米 + SDK30 → HIGH（最高优先级避免被系统杀）');
eq(MiuiOptimizationHelper.getRecommendedNotificationImportance(dev({ sdkInt: 34 })),
  NotificationImportance.IMPORTANCE_DEFAULT, '非小米 + SDK34 → DEFAULT');
eq(MiuiOptimizationHelper.getRecommendedNotificationImportance(dev({ sdkInt: 33 })),
  NotificationImportance.IMPORTANCE_LOW, '非小米 + SDK33 → LOW');
// 对照：小米优先于 SDK 判定（两条路径顺序不能反）
eq(MiuiOptimizationHelper.getRecommendedNotificationImportance(dev({ manufacturer: 'Xiaomi', sdkInt: 34 })),
  NotificationImportance.IMPORTANCE_HIGH,
  '**小米 + SDK34 → HIGH（小米分支优先）** —— 顺序反了会给 DEFAULT，后台被杀');

// ── getDeviceInfo：诊断文本 ──
const info = MiuiOptimizationHelper.getDeviceInfo(dev({ manufacturer: 'Xiaomi', miuiVersionName: 'V14', sdkInt: 30 }));
eq(info.split('\n').length >= 10, true, 'getDeviceInfo 输出至少 10 行');
eq(info.indexOf('Is MIUI: true') >= 0, true, '…含 Is MIUI 判定结果');
eq(info.indexOf('MIUI Version: 14') >= 0, true, '…含解析出的 MIUI 版本号');
eq(info.indexOf('(API 30)') >= 0, true, '…含注入的 sdkInt');

console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
process.exit(fail === 0 ? 0 : 1);
