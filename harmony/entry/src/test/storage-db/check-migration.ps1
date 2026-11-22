# 迁移一致性断言：`EhDB.migrate()` 到 v8 之后的结构  vs  `DaoMaster.createAllTables()`（各 Dao 的 CREATE_TABLE_SQL）
#
# 为什么必须测这一条：新装走 `createAllTables()`，升级走 `migrate()`。两者若不一致，就会出现
# **"新装正常、升级后缺列/多列"** —— 这类缺陷常规构建与单测都发现不了（SQLite 允许列不存在时
# 报错在运行时才暴露），而且只有用过旧版本的用户会踩到。
#
# 做法（纯文本解析，不连数据库）：
#   1. 从 10 个 `*Dao.ets` 里取 `CREATE_TABLE_SQL` → v8 目标结构
#   2. 从 `EhDB.ets` 的 `migrate()` 里按顺序取 `CREATE TABLE` / `ALTER TABLE ... ADD COLUMN` /
#      `DROP TABLE` / `RENAME TO` → 模拟出"升级后"的结构
#   3. 逐表比对列集合（并报告顺序差异）
#
# 用法：pwsh -File harmony/entry/src/test/storage-db/check-migration.ps1
param(
  [string]$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..\..')).Path
)
$ErrorActionPreference = 'Stop'

$daoDir = Join-Path $Repo 'harmony\entry\src\main\ets\hippo\ehviewer\dao'
$ehdbPath = Join-Path $Repo 'harmony\entry\src\main\ets\hippo\ehviewer\EhDB.ets'
if (-not (Test-Path $daoDir)) { throw "找不到 dao 目录: $daoDir" }
if (-not (Test-Path $ehdbPath)) { throw "找不到 EhDB.ets: $ehdbPath" }

# 从一段 SQL 的括号体里拆列名（保留原始顺序与拼写）
function Get-ColumnsFromCreateSql([string]$sql) {
  $open = $sql.IndexOf('(')
  $close = $sql.LastIndexOf(')')
  if ($open -lt 0 -or $close -le $open) { return @() }
  $body = $sql.Substring($open + 1, $close - $open - 1)
  $cols = @()
  foreach ($part in ($body -split ',')) {
    $p = $part.Trim()
    if ($p.Length -eq 0) { continue }
    # 跳过表级约束（PRIMARY KEY (...)、UNIQUE (...)、FOREIGN KEY(...)、CONSTRAINT ...）
    if ($p -match '^(PRIMARY\s+KEY|UNIQUE|FOREIGN\s+KEY|CONSTRAINT|CHECK)\b') { continue }
    # 第一段：可能带引号的标识符
    if ($p -match '^["\[]?([^"\s\[\]]+)["\]]?\s') {
      $cols += $Matches[1]
    } elseif ($p -match '^["\[]?([^"\s\[\]]+)["\]]?$') {
      $cols += $Matches[1]
    }
  }
  return $cols
}

# ---------------------------------------------------------------- 1) v8 目标结构（各 Dao 的 DDL）

$target = @{}   # table -> @{ Columns = [string[]]; File = '...' }
foreach ($f in (Get-ChildItem $daoDir -Filter '*Dao.ets' | Sort-Object Name)) {
  if ($f.Name -eq 'DaoMaster.ets' -or $f.Name -eq 'DaoSession.ets') { continue }
  $text = [IO.File]::ReadAllText($f.FullName)
  # CREATE_TABLE_SQL 可能是单行，也可能是多行字符串拼接
  $m = [regex]::Match($text, 'CREATE_TABLE_SQL[^=]*=\s*(?<sql>(?:''[^'']*''\s*\+?\s*)+);', 'Singleline')
  if (-not $m.Success) { continue }
  $sql = ([regex]::Matches($m.Groups['sql'].Value, "'([^']*)'") | ForEach-Object { $_.Groups[1].Value }) -join ''
  $tblMatch = [regex]::Match($sql, 'CREATE TABLE (?:IF NOT EXISTS )?["\[]?([A-Za-z_0-9]+)["\]]?')
  if (-not $tblMatch.Success) { continue }
  $table = $tblMatch.Groups[1].Value
  $target[$table] = @{ Columns = (Get-ColumnsFromCreateSql $sql); File = $f.Name; Sql = $sql }
}

# ---------------------------------------------------------------- 2) 模拟 migrate() 之后的结构

$ehdb = [IO.File]::ReadAllText($ehdbPath)
# 只取 migrate 方法体（从 'migrate(' 到下一个明显的方法边界）
$mStart = $ehdb.IndexOf('static async migrate')
if ($mStart -lt 0) { throw 'EhDB.ets 里找不到 static async migrate' }
$migrateBody = $ehdb.Substring($mStart, [Math]::Min(9000, $ehdb.Length - $mStart))

# 收集 executeSql('...') 的字面量，按出现顺序
$statements = @()
foreach ($mm in [regex]::Matches($migrateBody, "executeSql\(\s*(?<sql>(?:'[^']*'\s*\+?\s*)+)")) {
  $s = ([regex]::Matches($mm.Groups['sql'].Value, "'([^']*)'") | ForEach-Object { $_.Groups[1].Value }) -join ''
  $s = $s.Trim()
  if ($s.Length -gt 0) { $statements += $s }
}

$migrated = @{}    # table -> [string[]]（Column 顺序按语句顺序）
$created = @{}     # table -> $true：该表在迁移里被 CREATE 过（区别于"只被 ALTER"，如 DOWNLOADS）
$renames = @()     # @{ From; To }
foreach ($s in $statements) {
  if ($s -match '^\s*CREATE\s+TABLE\s+(?:IF NOT EXISTS\s+)?["\[]?(?<t>[A-Za-z_0-9]+)["\]]?') {
    $cols = Get-ColumnsFromCreateSql $s
    $migrated[$Matches['t']] = $cols
    $created[$Matches['t']] = $true
  } elseif ($s -match '^\s*ALTER\s+TABLE\s+["\[]?(?<t>[A-Za-z_0-9]+)["\]]?\s+ADD\s+COLUMN\s+["\[]?(?<c>[A-Za-z_0-9]+)["\]]?') {
    $t = $Matches['t']; $c = $Matches['c']
    if (-not $migrated.ContainsKey($t)) { $migrated[$t] = @() }
    if ($migrated[$t] -notcontains $c) { $migrated[$t] = @($migrated[$t]) + $c }
  } elseif ($s -match '^\s*ALTER\s+TABLE\s+["\[]?(?<f>[A-Za-z_0-9]+)["\]]?\s+RENAME\s+TO\s+["\[]?(?<to>[A-Za-z_0-9]+)["\]]?') {
    $renames += @{ From = $Matches['f']; To = $Matches['to'] }
  } elseif ($s -match '^\s*DROP\s+TABLE\s+(?:IF EXISTS\s+)?["\[]?(?<t>[A-Za-z_0-9]+)["\]]?') {
    $t = $Matches['t']
    if ($migrated.ContainsKey($t)) { $migrated.Remove($t) }
  }
}
# 应用 RENAME（FILTER2 → FILTER / QUICK_SEARCH2 → QUICK_SEARCH）
foreach ($r in $renames) {
  if ($migrated.ContainsKey($r.From)) {
    $migrated[$r.To] = $migrated[$r.From]
    $migrated.Remove($r.From)
    # 重命名的表也算"迁移里重建过"（FILTER2 → FILTER），否则会被误判成"只被 ALTER"
    if ($created.ContainsKey($r.From)) {
      $created[$r.To] = $true
      $created.Remove($r.From)
    }
  }
}

# ---------------------------------------------------------------- 3) 比对

$ok = 0; $bad = 0
# ---------------------------------------------------------------- 3a) 必须存在的迁移语句（防"删掉语句 → 落入 SKIP → 静默通过"）
#
# 这是我在同一条断言上踩过的坑：把 `ALTER TABLE DOWNLOADS ADD COLUMN ARCHIVE_URI` 删掉后，
# DOWNLOADS 变成"迁移不涉及此表"→ 走 SKIP 分支 → 断言照样通过（**假绿**）。
# 所以对 v7/v8 明确新增的两列单独做存在性断言。

$required = @(
  @{ Table = 'DOWNLOADS';     Column = 'ARCHIVE_URI' },
  @{ Table = 'Gallery_Tags';  Column = 'LOCATION' }
)
$missingRequired = @()
foreach ($r in $required) {
  $hit = $statements | Where-Object {
    ($_ -match "ALTER\s+TABLE\s+[""']?$([regex]::Escape($r.Table))[""']?\s+ADD\s+COLUMN\s+[""']?$([regex]::Escape($r.Column))") -or
    ($_ -match "CREATE\s+TABLE\s+[""']?$([regex]::Escape($r.Table))" -and $_ -match "[""']?$([regex]::Escape($r.Column))[""']?\s")
  }
  if (-not $hit) { $missingRequired += "$($r.Table).$($r.Column)" }
}
if ($missingRequired.Count -gt 0) {
  Write-Host ("  FAIL 迁移缺必需语句: {0}" -f ($missingRequired -join ', ')) -ForegroundColor Red
  $bad++
} else {
  Write-Host ("  OK   迁移含 v7/v8 必需列: {0}" -f (($required | ForEach-Object { "$($_.Table).$($_.Column)" }) -join ', ')) -ForegroundColor Green
  $ok++
}
Write-Host "== 迁移后结构 vs v8 目标结构 ==" -ForegroundColor Cyan
foreach ($table in ($target.Keys | Sort-Object)) {
  $want = @($target[$table].Columns)
  if (-not $created.ContainsKey($table) -and -not $migrated.ContainsKey($table)) {
    # 迁移里没重建的表：可以是"未被迁移触及"（如 BOOKMARKS / HISTORY）或"只有 ALTER"（如 DOWNLOADS）
    $alterCols = @($statements | Where-Object { $_ -match "ALTER\s+TABLE\s+[""']?$([regex]::Escape($table))[""']?\s+ADD\s+COLUMN" } | ForEach-Object { [regex]::Match($_, 'ADD\s+COLUMN\s+["\[]?([A-Za-z_0-9]+)').Groups[1].Value })
    if ($alterCols.Count -eq 0) {
      Write-Host ("  SKIP {0,-18}（迁移不涉及此表）" -f $table) -ForegroundColor DarkGray
      $ok++
      continue
    }
    # 只有 ALTER 的表：DDL 必须包含被 ADD 的列，否则升级后多出的列在新装里不存在
    $missing = @($alterCols | Where-Object { $want -notcontains $_ })
    if ($missing.Count -eq 0) {
      Write-Host ("  OK   {0,-18} 含迁移新增列 {1}" -f $table, ($alterCols -join ',')) -ForegroundColor Green
      $ok++
    } else {
      Write-Host ("  FAIL {0,-18} DDL 缺迁移新增列: {1}" -f $table, ($missing -join ',')) -ForegroundColor Red
      $bad++
    }
    continue
  }
  if (-not $created.ContainsKey($table)) {
    # 迁移里只 ALTER 过的表（DOWNLOADS）：DDL 必须含被 ADD 的列
    $alterCols = @($migrated[$table])
    $missing2 = @($alterCols | Where-Object { $want -notcontains $_ })
    if ($missing2.Count -eq 0) {
      Write-Host ("  OK   {0,-18} 含迁移新增列 {1}" -f $table, ($alterCols -join ',')) -ForegroundColor Green
      $ok++
    } else {
      Write-Host ("  FAIL {0,-18} DDL 缺迁移新增列: {1}" -f $table, ($missing2 -join ',')) -ForegroundColor Red
      $bad++
    }
    continue
  }
  $got = @($migrated[$table])
  $missingInMigration = @($want | Where-Object { $got -notcontains $_ })
  $extraInMigration = @($got | Where-Object { $want -notcontains $_ })
  if ($missingInMigration.Count -eq 0 -and $extraInMigration.Count -eq 0) {
    $orderNote = if (($want -join ',') -ne ($got -join ',')) { '（列顺序不同，不影响 RDB 读写）' } else { '' }
    Write-Host ("  OK   {0,-18} {1} 列{2}" -f $table, $want.Count, $orderNote) -ForegroundColor Green
    $ok++
  } else {
    if ($missingInMigration.Count -gt 0) {
      Write-Host ("  FAIL {0,-18} 迁移缺列: {1}" -f $table, ($missingInMigration -join ',')) -ForegroundColor Red
    }
    if ($extraInMigration.Count -gt 0) {
      Write-Host ("  FAIL {0,-18} 迁移多列: {1}" -f $table, ($extraInMigration -join ',')) -ForegroundColor Red
    }
    $bad++
  }
}

Write-Host ""
if ($bad -gt 0) {
  Write-Host "迁移一致性断言失败：$bad 张表不一致" -ForegroundColor Red
  exit 1
}
Write-Host "迁移一致性断言通过：$ok 张表（新装结构 == 升级到 v8 后的结构）" -ForegroundColor Green
exit 0
