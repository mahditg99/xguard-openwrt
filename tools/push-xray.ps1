<#
  Pushes dist\xray.gz into the router's RAM (tmpfs) over SSH and lets the supervisor start it.
  Use it for the first start after flashing, or any time the router has no xray in RAM and no
  download source configured. The router verifies the sha256 of the unpacked binary.

  usage:  powershell -File tools\push-xray.ps1 [-Router 192.168.5.1] [-User root]
#>
param(
  [string]$Router = '192.168.5.1',
  [string]$User = 'root',
  [string]$Dist = (Join-Path $PSScriptRoot '..\dist')
)
$ErrorActionPreference = 'Stop'
$gz = (Resolve-Path (Join-Path $Dist 'xray.gz')).Path
$sha = ((Get-Content (Join-Path $Dist 'xray.gz.sha256') -Raw).Trim() -split '\s+')[0]
if ($sha.Length -ne 64) { throw 'bad dist\xray.gz.sha256 - run tools\build-xray.ps1 first' }

Write-Host ("pushing {0:N1} MB to {1}@{2} ..." -f ((Get-Item $gz).Length / 1MB), $User, $Router)
# cmd's "<" redirection is binary-safe (PowerShell pipelines are not)
cmd /c "ssh -o ConnectTimeout=15 $User@$Router `"xguardctl push-xray $sha`" < `"$gz`""
if ($LASTEXITCODE -ne 0) { throw "push failed (exit $LASTEXITCODE)" }
