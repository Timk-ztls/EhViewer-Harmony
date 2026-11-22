'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');
const cp = require('child_process');

const HVIGOR_DIR = __dirname;
const PROJECT_ROOT = path.resolve(HVIGOR_DIR, '..');
const CONFIG_PATH = path.join(HVIGOR_DIR, 'hvigor-config.json5');
const HVIGOR_USER_HOME = process.env.HVIGOR_USER_HOME || path.join(os.homedir(), '.hvigor');
const PROJECT_CACHES = path.join(HVIGOR_USER_HOME, 'project_caches');
function parseJson5(content) {
  const noComments = content
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:])\/\/.*$/gm, '$1')
    .replace(/,\s*([}\]])/g, '$1');
  return JSON.parse(noComments);
}

function hashProjectRoot() {
  return crypto.createHash('sha256').update(PROJECT_ROOT).digest('hex').slice(0, 32);
}

function getWorkspace() {
  return path.join(PROJECT_CACHES, hashProjectRoot(), 'workspace');
}

function ensureHvigorInstalled(config) {
  const deps = config.dependencies || {};
  const hvigorVersion = deps['@ohos/hvigor'];
  const pluginVersion = deps['@ohos/hvigor-ohos-plugin'];
  if (!hvigorVersion) {
    console.error('[hvigorw] ERROR: "@ohos/hvigor" version not declared in hvigor/hvigor-config.json5');
    process.exit(1);
  }

  const workspace = getWorkspace();
  const nodeModules = path.join(workspace, 'node_modules');
  const hvigorBin = path.join(nodeModules, '@ohos', 'hvigor', 'bin', 'hvigor.js');
  const pluginPkg = path.join(nodeModules, '@ohos', 'hvigor-ohos-plugin', 'package.json');

  const installed = fs.existsSync(hvigorBin) && fs.existsSync(pluginPkg);
  if (!installed) {
    fs.mkdirSync(workspace, { recursive: true });
    // @ohos scoped packages come from the Huawei registry, other deps from npmjs.
    fs.writeFileSync(path.join(workspace, '.npmrc'),
      '@ohos:registry=https://repo.harmonyos.com/npm/\n');
    console.log(`[hvigorw] Installing hvigor@${hvigorVersion} + hvigor-ohos-plugin@${pluginVersion || hvigorVersion} ...`);
    const pkgs = [`@ohos/hvigor@${hvigorVersion}`];
    if (pluginVersion) {
      pkgs.push(`@ohos/hvigor-ohos-plugin@${pluginVersion}`);
    }
    const args = ['install', '--no-save', ...pkgs];
    const npmCmd = process.platform === 'win32' ? 'npm.cmd' : 'npm';
    cp.execFileSync(npmCmd, args, { cwd: workspace, stdio: 'inherit', shell: process.platform === 'win32' });
  }

  return path.join(nodeModules, '@ohos', 'hvigor', 'bin', 'hvigor.js');
}

function main() {
  let config;
  try {
    config = parseJson5(fs.readFileSync(CONFIG_PATH, 'utf8'));
  } catch (e) {
    console.error('[hvigorw] ERROR: failed to read hvigor/hvigor-config.json5:', e.message);
    process.exit(1);
  }

  const hvigorBin = ensureHvigorInstalled(config);
  const args = process.argv.slice(2);
  const result = cp.spawnSync(process.execPath, [hvigorBin].concat(args), {
    cwd: PROJECT_ROOT,
    stdio: 'inherit',
    env: process.env
  });
  if (result.error) {
    console.error('[hvigorw] ERROR:', result.error.message);
    process.exit(1);
  }
  process.exit(result.status === null ? 0 : result.status);
}

main();
