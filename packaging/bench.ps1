$ErrorActionPreference='Stop'
$bin='F:\Futo\packaging\bin'
$root='F:\Futo\tmp\bench'
if (Test-Path $root) { Remove-Item $root -Recurse -Force }
$src=Join-Path $root 'src'
New-Item -ItemType Directory -Force $src | Out-Null
# 60 MB of DLL-like data: copy the real Swift runtime bits
Get-ChildItem 'F:\Futo\upstream\flutter\build\windows\x64\runner\Release\*.dll' | Select-Object -First 12 | ForEach-Object { Copy-Item $_.FullName (Join-Path $src $_.Name) }
$total=(Get-ChildItem $src -File | Measure-Object Length -Sum).Sum
foreach ($algo in @('lzms','xpress','mszip','store')) {
  $out = Join-Path $root ('pack-' + $algo + '.exe')
  $p = Measure-Command { & (Join-Path $bin 'fotofilm-pack.exe') --stub (Join-Path $bin 'fotofilm-launch.exe') --input $src --output $out --algo $algo | Out-Null }
  $rt = Join-Path $root ('rt-' + $algo)
  $e = Measure-Command { $proc = Start-Process -FilePath $out -ArgumentList '--extract-only','--runtime-dir',$rt -Wait -PassThru; if ($proc.ExitCode -ne 0) { throw 'extract failed' } }
  $e2 = Measure-Command { $proc = Start-Process -FilePath $out -ArgumentList '--extract-only','--runtime-dir',$rt -Wait -PassThru }
  '{0,-8} pack {1,7:N0} ms  size {2,12:N0}  ratio {3,5:N2}x  extract {4,7:N0} ms  rerun {5,6:N0} ms' -f $algo, $p.TotalMilliseconds, (Get-Item $out).Length, ($total/(Get-Item $out).Length), $e.TotalMilliseconds, $e2.TotalMilliseconds
}
'source bytes: {0:N0}' -f $total