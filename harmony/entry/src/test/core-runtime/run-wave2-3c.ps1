# Wave 2 (3C): theme auto-switch, read progress cache, EH events bus, cellular warning guard
$ErrorActionPreference = 'Stop'
$root = (git -C $PSScriptRoot rev-parse --show-toplevel) -replace '/', '\'
$d = Join-Path $env:TEMP 'tscheck'
. "$root\scripts\lib\sync_hippo.ps1"
Sync-HippoTree -SrcHippo "$root\harmony\entry\src\main\ets\hippo" -DstHippo "$d\src\hippo"
. "$root\scripts\lib\tsc_gate.ps1"
if (-not (Invoke-TscGate -WorkDir $d -OutDir 'out11' -RootTs @(
  'src/hippo/ehviewer/Settings.ts',
  'src/hippo/ehviewer/ReadProgressCache.ts',
  'src/hippo/ehviewer/EhEventPaneBus.ts',
  'src/hippo/ehviewer/OhosNetworkMonitor.ts',
  'src/hippo/ehviewer/client/EhEngine.ts',
  'src/hippo/ui/ThemeAutoSwitchHelper.ts',
  'src/hippo/ui/reader/ReaderEngineCoordinator.ts'
) -Quiet)) { exit 1 }
node "$PSScriptRoot/wave2-3c.test.js" "$d\out11\hippo"
exit $LASTEXITCODE
