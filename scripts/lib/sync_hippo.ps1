# 增量同步 hippo/*.ets 到测试沙箱 src/hippo/*.ts（仅在缺失、大小或时间戳变化时拷贝）
function Sync-HippoTree {
  param(
    [Parameter(Mandatory = $true)][string]$SrcHippo,
    [Parameter(Mandatory = $true)][string]$DstHippo
  )

  $srcAbs = [System.IO.Path]::GetFullPath($SrcHippo).TrimEnd('\', '/')
  if (-not [System.IO.Directory]::Exists($srcAbs)) {
    throw "Sync-HippoTree: 源目录不存在: $srcAbs"
  }
  $dstAbs = [System.IO.Path]::GetFullPath($DstHippo).TrimEnd('\', '/')
  if (-not [System.IO.Directory]::Exists($dstAbs)) {
    [System.IO.Directory]::CreateDirectory($dstAbs) | Out-Null
  }

  $seenDirs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  $expected = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  $prefixLen = $srcAbs.Length + 1
  $files = [System.IO.Directory]::GetFiles($srcAbs, '*.ets', [System.IO.SearchOption]::AllDirectories)

  foreach ($f in $files) {
    $rel = $f.Substring($prefixLen)
    $dstFile = [System.IO.Path]::Combine($dstAbs, [System.IO.Path]::ChangeExtension($rel, '.ts'))
    [void]$expected.Add($dstFile)
    $dstDir = [System.IO.Path]::GetDirectoryName($dstFile)
    if ($seenDirs.Add($dstDir) -and -not [System.IO.Directory]::Exists($dstDir)) {
      [System.IO.Directory]::CreateDirectory($dstDir) | Out-Null
    }
    $srcInfo = [System.IO.FileInfo]::new($f)
    if ([System.IO.File]::Exists($dstFile)) {
      $dstInfo = [System.IO.FileInfo]::new($dstFile)
      if ($dstInfo.Length -eq $srcInfo.Length -and $dstInfo.LastWriteTimeUtc -eq $srcInfo.LastWriteTimeUtc) {
        continue
      }
    }
    [System.IO.File]::Copy($f, $dstFile, $true)
  }

  # 清理源树已删/重命名的残留 .ts
  foreach ($existing in [System.IO.Directory]::GetFiles($dstAbs, '*.ts', [System.IO.SearchOption]::AllDirectories)) {
    if (-not $expected.Contains($existing)) {
      [System.IO.File]::Delete($existing)
    }
  }
}
