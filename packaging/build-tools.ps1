# Builds fotufilm-launch.exe (self-extracting stub) and fotufilm-pack.exe.
param([switch]$Clean)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$bin  = Join-Path $here 'bin'
if ($Clean -and (Test-Path $bin)) { Remove-Item $bin -Recurse -Force }
New-Item -ItemType Directory -Force $bin | Out-Null

$vswhere = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path $vswhere)) { throw "vswhere not found" }
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw "No MSVC toolset found" }
$vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'
if (-not (Test-Path $vcvars)) { throw "vcvars64.bat not found at $vcvars" }

$src = Join-Path $here 'launcher.cpp'
$common = '/nologo /W4 /O2 /std:c++20 /EHsc /DUNICODE /D_UNICODE /MT /GS /utf-8 /D_CRT_SECURE_NO_WARNINGS /utf-8'
$link = '/link /SUBSYSTEM:'
$cmd = @(
  ('call "{0}" >nul' -f $vcvars),
  ('cd /d "{0}"' -f $here),
  ('cl {0} "{1}" /Fe:"{2}\fotufilm-launch.exe" {3}WINDOWS cabinet.lib shell32.lib user32.lib gdi32.lib' -f $common, $src, $bin, $link),
  ('cl {0} /DFOTUFILM_PACKER "{1}" /Fe:"{2}\fotufilm-pack.exe" {3}CONSOLE cabinet.lib shell32.lib user32.lib gdi32.lib' -f $common, $src, $bin, $link)
) -join ' && '

Write-Host "Compiling with $vs"
cmd /c $cmd
if ($LASTEXITCODE -ne 0) { throw "compile failed ($LASTEXITCODE)" }
Remove-Item (Join-Path $here '*.obj') -ErrorAction SilentlyContinue
Get-ChildItem $bin | ForEach-Object { "{0,-24} {1,10:N0} bytes" -f $_.Name, $_.Length }