# 检查全仓文本文件的行尾是否为 LF
# 只检查 **git 跟踪**的文件 —— 生成的临时报告（coverage-report.md 等）不算
param([switch]$Fix, [switch]$Gate, [switch]$IncludeUntracked)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    $exts = @('*.ets','*.ts','*.js','*.json','*.json5','*.md','*.csv','*.ps1','*.c','*.h','*.txt')
    $excludeDirs = @('node_modules','build','out','.cxx','.git','.hvigor','oh_modules','.upstream-res','artifacts','.idea','.vscode')

    if ($IncludeUntracked) {
        # 全盘扫（慢，但能看到未跟踪文件）
        $candidates = Get-ChildItem $root -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $exts -contains ('*' + $_.Extension) } |
            ForEach-Object { $_.FullName.Substring($root.Length + 1) }
    } else {
        # 只用 git 跟踪的文件（快，且语义正确：检查入库内容）
        $tracked = git ls-files 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "SKIP: 不是 git 仓库，本项不生效" -ForegroundColor Yellow
            exit 0
        }
        $candidates = $tracked | Where-Object { $exts -contains ('*' + [IO.Path]::GetExtension($_)) }
    }

    $bad = @()
    foreach ($rel in $candidates) {
        $rel = "$rel".Trim()
        if (-not $rel) { continue }
        $parts = $rel -split '[\\/]'
        $skip = $false
        foreach ($d in $excludeDirs) { if ($parts -contains $d) { $skip = $true; break } }
        if ($skip) { continue }
        $full = Join-Path $root $rel
        if (-not (Test-Path $full)) { continue }
        $bytes = [IO.File]::ReadAllBytes($full)
        $cr = 0; $lf = 0
        foreach ($b in $bytes) { if ($b -eq 13) { $cr++ } elseif ($b -eq 10) { $lf++ } }
        if ($cr -gt 0) { $bad += [pscustomobject]@{ File = $rel; CR = $cr; LF = $lf } }
    }

    if ($bad.Count -eq 0) {
        Write-Host "行尾检查：$($candidates.Count) 个跟踪文件全部 LF OK" -ForegroundColor Green
        exit 0
    }
    Write-Host "行尾检查：$($bad.Count) / $($candidates.Count) 个跟踪文件含 CRLF" -ForegroundColor Yellow
    $bad | Sort-Object CR -Descending | Select-Object -First 25 | ForEach-Object { "  $($_.File)  CR=$($_.CR) LF=$($_.LF)" }
    if ($bad.Count -gt 25) { Write-Host "  ...（另有 $($bad.Count - 25) 个）" }
    if ($Fix) {
        Write-Host "`n归一为 LF..." -ForegroundColor Cyan
        foreach ($f in $bad) {
            $full = Join-Path $root $f.File
            $text = [IO.File]::ReadAllText($full) -replace "`r`n", "`n" -replace "`r", "`n"
            [IO.File]::WriteAllText($full, $text, [Text.UTF8Encoding]::new($false))
        }
        Write-Host "已归一 $($bad.Count) 个文件" -ForegroundColor Green
        exit 0
    }
    if ($Gate) { exit 1 }
    exit 0
} finally { Pop-Location }