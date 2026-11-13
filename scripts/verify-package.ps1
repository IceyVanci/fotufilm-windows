param([Parameter(Mandatory=$true)][string]$Exe, [string]$Dir = 'F:\Futo\tmp\verify')
$ErrorActionPreference='Stop'
if (Test-Path $Dir) { Remove-Item $Dir -Recurse -Force }
New-Item -ItemType Directory -Force $Dir | Out-Null
$exeItem = Get-Item $Exe
'package : ' + $exeItem.Name + '  ' + [math]::Round($exeItem.Length/1MB,1) + ' MB'
$log = Join-Path $Dir 'launch.log'
$env:FOTUFILM_LAUNCH_LOG = $log
$p = Start-Process -FilePath $Exe -ArgumentList '--extract-only','--runtime-dir',$Dir -PassThru -Wait
'extract : exit ' + $p.ExitCode
$files = Get-ChildItem $Dir -Recurse -File
'files   : ' + $files.Count + '  ' + [math]::Round(($files | Measure-Object Length -Sum).Sum/1MB,1) + ' MB'
'engine  : ' + (Test-Path (Join-Path $Dir 'libfotufilm.dll'))
'runner  : ' + (Test-Path (Join-Path $Dir 'fotufilm.exe'))
$glyphs = Get-ChildItem (Join-Path $Dir 'data\flutter_assets\assets\generated\glyphs') -Filter *.svg -ErrorAction SilentlyContinue
'glyphs  : ' + $glyphs.Count
$swift = Get-ChildItem $Dir -Filter 'swift*.dll' -ErrorAction SilentlyContinue
'swift   : ' + $swift.Count + ' dll'
