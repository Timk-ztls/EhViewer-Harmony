# EhDB.migrate() SQL 文本断言
$ErrorActionPreference = 'Stop'
$root = (git -C $PSScriptRoot rev-parse --show-toplevel) -replace '/', '\'
node "$PSScriptRoot/migrate.test.js" "$root/harmony/entry/src/main/ets/hippo/ehviewer/EhDB.ets"
exit $LASTEXITCODE
