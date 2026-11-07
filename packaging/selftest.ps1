param([switch]$Keep)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$bin = Join-Path $here 'bin'
$root = Join-Path 'F:\Futo\tmp' ('selftest-' + [guid]::NewGuid().ToString('N').Substring(0,6))
$src = Join-Path $root 'src'
$out = Join-Path $root 'out'
New-Item -ItemType Directory -Force (Join-Path $src 'nested\deep') | Out-Null
'hello world' | Set-Content (Join-Path $src 'a.txt')
[IO.File]::WriteAllText((Join-Path $src 'nested\中文.txt'), '中文文件名测试')
New-Item -ItemType File (Join-Path $src 'empty.bin') | Out-Null
$bytes = New-Object byte[] (40MB)
(New-Object Random 42).NextBytes($bytes)
[IO.File]::WriteAllBytes((Join-Path $src 'big.bin'), $bytes)
$zeros = New-Object byte[] (5MB)
[IO.File]::WriteAllBytes((Join-Path $src 'nested\deep\zeros.bin'), $zeros)
for ($i = 0; $i -lt 12; $i++) { ('row {0}' -f $i) | Set-Content (Join-Path $src ('f{0:D2}.txt' -f $i)) }

$packed = Join-Path $root 'Fotufilm-test.exe'
& (Join-Path $bin 'fotofilm-pack.exe') --stub (Join-Path $bin 'fotofilm-launch.exe') --input $src --output $packed --name 'Fotufilm self test' --algo lzms
if ($LASTEXITCODE -ne 0) { throw 'pack failed' }
$packedSize = (Get-Item $packed).Length

$sw = [Diagnostics.Stopwatch]::StartNew()
$proc = Start-Process -FilePath $packed -ArgumentList '--extract-only','--runtime-dir',$out -Wait -PassThru
$sw.Stop()
if ($proc.ExitCode -ne 0) { throw ('extract failed: ' + $proc.ExitCode) }
Write-Host ('first extraction: {0} ms' -f $sw.ElapsedMilliseconds)

$srcFiles = Get-ChildItem $src -Recurse -File
$bad = 0
foreach ($f in $srcFiles) {
  $rel = $f.FullName.Substring($src.Length + 1)
  $dst = Join-Path $out $rel
  if (-not (Test-Path -LiteralPath $dst)) { Write-Host ('MISSING ' + $rel); $bad++; continue }
  $sa = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
  $sb = (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash
  if ($sa -ne $sb) { Write-Host ('DIFF ' + $rel); $bad++ }
}
if ($bad -ne 0) { throw ('{0} file(s) differ' -f $bad) }
Write-Host ('verified {0} files byte for byte' -f $srcFiles.Count)

$stamp = (Get-Item -LiteralPath (Join-Path $out 'a.txt')).LastWriteTimeUtc
$sw = [Diagnostics.Stopwatch]::StartNew()
$proc = Start-Process -FilePath $packed -ArgumentList '--extract-only','--runtime-dir',$out -Wait -PassThru
$sw.Stop()
if ($proc.ExitCode -ne 0) { throw 'second run failed' }
if ((Get-Item -LiteralPath (Join-Path $out 'a.txt')).LastWriteTimeUtc -ne $stamp) { throw 'fast path rewrote files' }
Write-Host ('second run: {0} ms' -f $sw.ElapsedMilliseconds)
if ($sw.ElapsedMilliseconds -gt 1500) { Write-Host 'WARN: fast path slow' }

Write-Host ('packed {0:N0} bytes from {1:N0} bytes' -f $packedSize, (($srcFiles | Measure-Object Length -Sum).Sum))
if (-not $Keep) { Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host 'SELFTEST PASSED'