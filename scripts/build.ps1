<#
.SYNOPSIS
  Builds the Fotufilm Windows editor and packs it into one executable.
.DESCRIPTION
  Steps: Swift engine (FotufilmHost.dll) -> Flutter editor -> staged runtime folder -> single exe.
  Needs an elevated shell for the Flutter plugin symlinks, so the script re-launches itself.
.EXAMPLE
  .\build.ps1
  .\build.ps1 -SkipEngine          # engine unchanged, rebuild the editor only
  .\build.ps1 -Algo lzms           # smaller download, slower first start
  .\build.ps1 -EditorOnly -NoElevate
#>
param(
  [switch]$SkipEngine,
  [switch]$SkipEditor,
  [switch]$SkipPackage,
  [ValidateSet('lzms','xpress','mszip','store')][string]$Algo = 'xpress',
  [switch]$NoElevate,
  [switch]$Elevate,
  # The tree to build. The port builds from F:\Futo\work\<upstream version>.
  [string]$Source = 'F:\Futo\upstream',
  # The upstream release this tree carries; version.env goes stale between the port's syncs.
  [string]$Version = '',
  [string]$AotDir = 'F:\Futo\m0\aot-windows',
  [string]$HalideRoot = 'F:\Futo\toolchain\halide-build',
  [string]$Revision = '1'
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Root      = 'F:\Futo'
$Upstream  = $Source
$Flutter   = Join-Path $Upstream 'flutter'
$Release   = Join-Path $Flutter 'build\windows\x64\runner\Release'
$EngineOut = Join-Path $Upstream '.build\x86_64-unknown-windows-msvc\release'
$Dist      = Join-Path $Root 'dist'
$App       = Join-Path $Dist 'app'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($Elevate -and -not $isAdmin) {
  $argv = @('-NoProfile','-ExecutionPolicy','Bypass','-File', ('"' + $PSCommandPath + '"'), '-NoElevate')
  if ($SkipEngine) { $argv += '-SkipEngine' }
  if ($SkipEditor) { $argv += '-SkipEditor' }
  if ($SkipPackage) { $argv += '-SkipPackage' }
  if ($Algo -ne 'xpress') { $argv += @('-Algo', $Algo) }
  if ($Source -ne 'F:\Futo\upstream') { $argv += @('-Source', $Source) }
  if ($Version) { $argv += @('-Version', $Version) }
  if ($AotDir -ne 'F:\Futo\m0\aot-windows') { $argv += @('-AotDir', $AotDir) }
  if ($HalideRoot -ne 'F:\Futo\toolchain\halide-build') { $argv += @('-HalideRoot', $HalideRoot) }
  if ($Revision -ne '1') { $argv += @('-Revision', $Revision) }
  Write-Host 'Re-launching elevated (SSD build caches are safer when owned by one account).' -ForegroundColor Yellow
  $p = Start-Process powershell -Verb RunAs -ArgumentList $argv -Wait -PassThru
  exit $p.ExitCode
}
New-Item -ItemType Directory -Force $Dist, 'F:\Futo\tmp' | Out-Null
$log = Join-Path $Dist ('build-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
try { Start-Transcript -Path $log -Force | Out-Null } catch { }
$script:started = Get-Date

function Step($name) {
  $script:current = $name
  Write-Host ''
  Write-Host ('=== ' + $name + ' ===') -ForegroundColor Cyan
  $script:sw = [Diagnostics.Stopwatch]::StartNew()
}
function Done {
  $script:sw.Stop()
  Write-Host ('    done in {0:N1} s' -f ($script:sw.Elapsed.TotalSeconds)) -ForegroundColor Green
  $script:timings += [pscustomobject]@{ Step = $script:current; Seconds = [math]::Round($script:sw.Elapsed.TotalSeconds, 1) }
}
function Fail($message) {
  Write-Host ''
  Write-Host ('BUILD FAILED in ' + $script:current + ': ' + $message) -ForegroundColor Red
  exit 1
}
$script:timings = @()

# ---- toolchain -------------------------------------------------------------------------------
Step 'toolchain'
$swiftRoot = 'F:\Futo\toolchain\swift'
$swiftBin  = Join-Path $swiftRoot 'LocalApp\Programs\Swift\Toolchains\6.2.0+Asserts\usr\bin'
$swiftSdk  = Join-Path $swiftRoot 'LocalApp\Programs\Swift\Platforms\6.2.0\Windows.platform\Developer\SDKs\Windows.sdk'
$flutterBat = 'F:\Futo\toolchain\sdks\flutter\bin\flutter.bat'
$vswhere = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
foreach ($p in @($swiftBin, $swiftSdk, $flutterBat, $vswhere, $AotDir, $Upstream)) {
  if (-not (Test-Path $p)) { Fail "missing $p" }
}
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { Fail 'Visual Studio build tools not found' }
$vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'

# Keep every build cache on the build drive. Elevated runs make %LOCALAPPDATA% caches unreadable
# to later unelevated runs, and child processes here cannot always write under the user profile.
$env:LOCALAPPDATA = 'F:\Futo\home\LocalAppData'
$env:APPDATA      = 'F:\Futo\home\Roaming'
$env:USERPROFILE  = 'F:\Futo\home'
$env:HOME         = 'F:\Futo\home'
New-Item -ItemType Directory -Force $env:LOCALAPPDATA, $env:APPDATA, 'F:\Futo\home\.swiftpm' | Out-Null
$env:TEMP = 'F:\Futo\tmp'
$env:TMP  = 'F:\Futo\tmp'
$env:PUB_CACHE = 'F:\Futo\home\AppData\Local\Pub\Cache'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:DART_SUPPRESS_ANALYTICS = 'true'
$env:HL_WINDOWS_TMP_DIR = 'F:\Futo\tmp'
$env:FOTOFILM_AOT_DIR = $AotDir
$env:HALIDE_ROOT = $HalideRoot
$stageHeaders = Join-Path $Upstream 'Sources\FotufilmHalide'
$newestStage = Get-ChildItem $stageHeaders -Recurse -Include '*.h','*.cpp' -File -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1
$newestAot = Get-ChildItem $AotDir -Filter '*.lib' -File -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $newestAot) { Fail "no AOT kernels in $AotDir; run tools\generate-halide-aot-windows.ps1" }
if ($newestStage -and $newestStage.LastWriteTime -gt $newestAot.LastWriteTime) {
  Fail ('the Halide stages are newer than the AOT kernels (' + $newestStage.Name + ' ' + $newestStage.LastWriteTime +
        ' > ' + $newestAot.LastWriteTime + '); regenerate them into ' + $AotDir)
}
Done

# ---- engine ----------------------------------------------------------------------------------
if (-not $SkipEngine) {
  Step 'swift engine'
  # The manifest reads FOTOFILM_AOT_DIR and HALIDE_ROOT from the environment; when that read comes
  # back empty the package silently builds without the Vulkan kernels and fails to link. The same
  # settings are passed as flags so the engine is correct either way.
  $halideLib = Join-Path $env:HALIDE_ROOT 'lib\Release'
  if (-not (Test-Path $halideLib)) { $halideLib = Join-Path $env:HALIDE_ROOT 'lib' }
  $engineFlags = @()
  if (Test-Path $env:HALIDE_ROOT) {
    $engineFlags += @('-Xcxx', '-DFOTUFILM_HALIDE_ENABLED', '-Xcxx', ('-I' + (Join-Path $env:HALIDE_ROOT 'include')), '-Xcxx', '-D_USE_MATH_DEFINES')
    $engineFlags += @('-Xlinker', ('/LIBPATH:' + $halideLib), '-Xlinker', 'Halide.lib')
  }
  $engineFlags += @('-Xcxx', '-DFOTUFILM_HALIDE_LINUX_AOT', '-Xcxx', ('-I' + $AotDir), '-Xlinker', ('/LIBPATH:' + $AotDir))
  foreach ($aotLib in (Get-ChildItem $AotDir -Filter 'fotufilm_aot_*.lib' | Sort-Object Name)) {
    $engineFlags += @('-Xlinker', $aotLib.Name)
  }
  $runtime = Join-Path $AotDir 'fotufilm_aot_runtime.a'
  if (Test-Path $runtime) { $engineFlags += @('-Xlinker', $runtime) }
  $flagLine = ($engineFlags | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
  $cmd = 'call "' + $vcvars + '" >nul && set "PATH=' + $swiftBin + ';' + $swiftRoot + ';%PATH%" && set "SDKROOT=' + $swiftSdk + '" && swift build -c release --package-path "' + $Upstream + '" --product FotufilmHost ' + $flagLine
  cmd /c $cmd
  if ($LASTEXITCODE -ne 0) { Fail ('swift build exited ' + $LASTEXITCODE) }
  if (-not (Test-Path (Join-Path $EngineOut 'FotufilmHost.dll'))) { Fail 'FotufilmHost.dll was not produced' }
  Done
} else { Write-Host 'skipping the engine' -ForegroundColor DarkGray }

# ---- build stamp -----------------------------------------------------------------------------
Step 'stamp build info'
$versionFile = Join-Path $Upstream 'version.env'
$upstreamVersion = '0.0'
if (Test-Path $versionFile) {
  $found = Select-String -Path $versionFile -Pattern '^MARKETING_VERSION=(\S+)'
  if ($found) { $upstreamVersion = $found.Matches.Groups[1].Value }
}
if ($Version) { $upstreamVersion = $Version }
$revision = $Revision
$portVersion = '{0}.0-w{1}' -f $upstreamVersion, $revision
$buildDate = (Get-Date).ToString('yyyy-MM-dd')
$infoLines = @(
  '// Stamped by build.ps1 before every build. The checked-in values are what a bare checkout compiles.',
  ('const String kBuildPortVersion = ' + [char]39 + $portVersion + [char]39 + ';'),
  ('const String kBuildUpstreamVersion = ' + [char]39 + $upstreamVersion + [char]39 + ';'),
  ('const String kBuildDate = ' + [char]39 + $buildDate + [char]39 + ';'),
  ''
)
$rcPath = Join-Path $Flutter 'windows\runner\Runner.rc'
$rcVersion = $upstreamVersion + '.0.' + $revision
$rcText = [IO.File]::ReadAllText($rcPath)
$rcText = [regex]::Replace($rcText, '#define PORT_VERSION_STRING "[^"]*"', '#define PORT_VERSION_STRING "' + $rcVersion + '"')
[IO.File]::WriteAllText($rcPath, $rcText, (New-Object Text.UTF8Encoding($false)))
$infoPath = Join-Path $Flutter 'lib\app\build_info.dart'
[IO.File]::WriteAllText($infoPath, [string]::Join([char]10, $infoLines), (New-Object Text.UTF8Encoding($false)))
Write-Host ('    Fotufilm ' + $upstreamVersion + ' · port ' + $portVersion + ' · file ' + $rcVersion + ' · ' + $buildDate)
Done

# ---- editor ----------------------------------------------------------------------------------
if (-not $SkipEditor) {
  Step 'flutter editor'
  Push-Location $Flutter
  try { & $flutterBat build windows --release --no-pub } finally { Pop-Location }
  if ($LASTEXITCODE -ne 0) { Fail ('flutter build exited ' + $LASTEXITCODE) }
  Done
} else { Write-Host 'skipping the editor' -ForegroundColor DarkGray }

if ($SkipPackage) {
  Write-Host ''
  $script:timings | Format-Table -AutoSize | Out-String -Width 120 | Write-Host
  Write-Host 'Stopped before packaging.' -ForegroundColor Yellow
  exit 0
}

# ---- stage -----------------------------------------------------------------------------------
Step 'stage runtime'
if (-not (Test-Path $Release)) { Fail "no release build at $Release" }
if (Test-Path $App) { Remove-Item $App -Recurse -Force }
New-Item -ItemType Directory -Force $App | Out-Null
$skip = @('debug.log', 'run-editor.cmd', 'native_assets.json')
Get-ChildItem $Release -Force | Where-Object { $skip -notcontains $_.Name -and $_.Extension -ne '.pdb' } | ForEach-Object {
  Copy-Item $_.FullName -Destination $App -Recurse -Force
}
$engineDll = Join-Path $EngineOut 'FotufilmHost.dll'
if (-not (Test-Path $engineDll)) { Fail 'the engine build is missing' }
Copy-Item $engineDll (Join-Path $App 'libfotufilm.dll') -Force
Get-ChildItem 'F:\Futo\toolchain\swift\*.dll' | Copy-Item -Destination $App -Force
$resources = Join-Path $EngineOut 'Fotufilm_FotufilmCore.resources'
if (Test-Path $resources) { Copy-Item $resources $App -Recurse -Force }
$count = (Get-ChildItem $App -Recurse -File).Count
Done

# ---- package ---------------------------------------------------------------------------------
Step 'single executable'
$tools = Join-Path $Root 'packaging'
$packer = Join-Path $tools 'bin\fotufilm-pack.exe'
$stub   = Join-Path $tools 'bin\fotufilm-launch.exe'
if (-not (Test-Path $packer) -or -not (Test-Path $stub)) {
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $tools 'build-tools.ps1')
  if ($LASTEXITCODE -ne 0) { Fail 'could not build the packaging tools' }
}
$out = Join-Path $Dist ('Fotufilm-' + $portVersion + '-win64.exe')
& $packer --stub $stub --input $App --output $out --name ('Fotufilm ' + $portVersion) --algo $Algo
if ($LASTEXITCODE -ne 0) { Fail 'packing failed' }
Done

# ---- summary ---------------------------------------------------------------------------------
$exe = Get-Item $out
$raw = (Get-ChildItem $App -Recurse -File | Measure-Object Length -Sum).Sum
Write-Host ''
Write-Host 'Build complete' -ForegroundColor Green
Write-Host ('  single exe : {0}' -f $exe.FullName)
Write-Host ('  size       : {0:N1} MB from {1:N1} MB of files ({2:N2}x, {3})' -f ($exe.Length/1MB), ($raw/1MB), ($raw/$exe.Length), $Algo)
Write-Host ('  files      : {0} in the staged runtime' -f $count)
Write-Host ('  elapsed    : {0:N1} s' -f ((Get-Date) - $script:started).TotalSeconds)
$script:timings | Format-Table -AutoSize | Out-String -Width 120 | Write-Host
Write-Host ('  log        : {0}' -f $log)