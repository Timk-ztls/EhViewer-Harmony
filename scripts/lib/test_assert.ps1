# Shared UTF-8 console helper and assertion summary parser for module test runners.

function Initialize-Utf8Console {
  $utf8 = [System.Text.UTF8Encoding]::new($false)
  try { [Console]::OutputEncoding = $utf8 } catch { }
  $script:OutputEncoding = $utf8
}

function Get-NodeAssertionCounts {
  param([string]$Text)

  if ([string]::IsNullOrEmpty($Text)) {
    return @(0, 0)
  }
  if ($Text -match 'PASS\s+(\d+)\s+FAIL\s+(\d+)') {
    return @([int]$Matches[1], [int]$Matches[2])
  }
  if ($Text -match '(\d+)\s+passed,\s*(\d+)\s+failed') {
    return @([int]$Matches[1], [int]$Matches[2])
  }
  if ($Text -match '(\d+)\s+assertions?\s+passed') {
    return @([int]$Matches[1], 0)
  }
  if ($Text -match '全部通过[：:\s]*(\d+)\s*个断言') {
    return @([int]$Matches[1], 0)
  }
  if ($Text -match '(\d+)\s*条断言全部通过') {
    return @([int]$Matches[1], 0)
  }
  if ($Text -match '通过\s*(\d+)[，,]\s*失败\s*(\d+)') {
    return @([int]$Matches[1], [int]$Matches[2])
  }
  if ($Text -match '(\d+)\s*条失败\s*/\s*(\d+)\s*条断言') {
    $f = [int]$Matches[1]
    return @([Math]::Max(0, [int]$Matches[2] - $f), $f)
  }
  $p = ([regex]::Matches($Text, '(?m)^\s*PASS\s')).Count
  $f = ([regex]::Matches($Text, '(?m)^\s*FAIL\s')).Count
  return @($p, $f)
}

function Invoke-NodeTestFile {
  param(
    [string]$NodeExe = 'node',
    [string[]]$NodeArgs
  )

  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $lines = & $NodeExe @NodeArgs 2>&1
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $prevEap
  }
  $outText = ($lines | ForEach-Object { "$_" }) -join "`n"
  if ($outText.Length -gt 0) {
    Write-Host $outText
  }
  $counts = Get-NodeAssertionCounts -Text $outText
  return [pscustomobject]@{
    ExitCode = $exitCode
    Pass     = $counts[0]
    Fail     = $counts[1]
  }
}
