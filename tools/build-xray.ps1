<#
  Downloads the official Xray-core release for MIPS little-endian (MT7621 = mipsel_24kc, soft-float),
  verifies it against the .dgst published by the project, and writes:
      dist\xray.gz          gzip -9 of the uncompressed binary (what the router streams into RAM)
      dist\xray.gz.sha256   sha256 of the UNCOMPRESSED binary (what the router verifies)
      dist\xray.version
  The router never stores this on flash: it lives in tmpfs and is re-fetched after every boot.

  usage:  powershell -File tools\build-xray.ps1 [-Version v26.11.9] [-ZipPath C:\path\Xray-linux-mips32le.zip]
#>
param(
  [string]$Version = 'latest',
  [string]$ZipPath = '',
  [string]$Out = (Join-Path $PSScriptRoot '..\dist')
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
New-Item -ItemType Directory -Force $Out | Out-Null
$work = Join-Path ([IO.Path]::GetTempPath()) ('xguard-xray-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $work | Out-Null

try {
  if ($Version -eq 'latest') {
    $rel = Invoke-RestMethod 'https://api.github.com/repos/XTLS/Xray-core/releases/latest' -TimeoutSec 30
    $Version = $rel.tag_name
  }
  Write-Host "Xray-core $Version (linux mips32le)"
  $base = "https://github.com/XTLS/Xray-core/releases/download/$Version"

  if ($ZipPath) { $zip = $ZipPath } else {
    $zip = Join-Path $work 'xray.zip'
    Invoke-WebRequest "$base/Xray-linux-mips32le.zip" -OutFile $zip -TimeoutSec 600
  }
  $dgst = (Invoke-WebRequest "$base/Xray-linux-mips32le.zip.dgst" -TimeoutSec 60 -UseBasicParsing).Content
  if ($dgst -is [byte[]]) { $dgst = [Text.Encoding]::UTF8.GetString($dgst) }   # served as octet-stream
  $want = [regex]::Match($dgst, '(?im)^\s*SHA2-256\s*=\s*([0-9a-f]{64})').Groups[1].Value
  if (-not $want) { throw 'no SHA2-256 line in the .dgst file' }
  $got = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
  if ($got -ne $want) { throw "zip checksum mismatch: $got != $want" }
  Write-Host "zip sha256 OK ($got)"

  # MT7621 userland is soft-float: use the softfloat build
  $z = [IO.Compression.ZipFile]::OpenRead($zip)
  try {
    $entry = $z.Entries | Where-Object { $_.FullName -eq 'xray_softfloat' } | Select-Object -First 1
    if (-not $entry) { throw 'xray_softfloat not found in the zip' }
    $bin = Join-Path $work 'xray'
    [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $bin, $true)
  } finally { $z.Dispose() }

  $sha = (Get-FileHash $bin -Algorithm SHA256).Hash.ToLower()
  $gz = Join-Path $Out 'xray.gz'
  $in = [IO.File]::OpenRead($bin)
  $o = [IO.File]::Create($gz)
  $g = New-Object IO.Compression.GZipStream($o, [IO.Compression.CompressionLevel]::Optimal)
  try { $in.CopyTo($g) } finally { $g.Dispose(); $o.Dispose(); $in.Dispose() }

  [IO.File]::WriteAllText((Join-Path $Out 'xray.gz.sha256'), "$sha  xray`n")
  [IO.File]::WriteAllText((Join-Path $Out 'xray.version'), "$Version`n")
  "{0}  binary {1:N1} MB, xray.gz {2:N1} MB, sha256(binary) {3}" -f $Version, ((Get-Item $bin).Length / 1MB), ((Get-Item $gz).Length / 1MB), $sha
} finally {
  Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
