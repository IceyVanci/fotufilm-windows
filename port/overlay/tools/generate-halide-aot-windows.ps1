# Generates the Windows AOT kernels: the desktop graph compiled for Vulkan, and the one Halide
# runtime the set shares, from the Halide in HALIDE_ROOT and the generator in tools/.
#   tools/generate-halide-aot-windows.ps1 [-OutputDirectory build\halide-windows-x86_64]
#
# The kernels are the Vulkan set alone: Windows has no CUDA build in this port, so
# FotufilmHalideLinux.cpp (compiled with FOTUFILM_HALIDE_LINUX_AOT) picks Vulkan or the CPU.
# Halide compiles through temporary directories under GetTempPath; HL_WINDOWS_TMP_DIR points
# them somewhere writable, which a machine with a locked-down %TEMP% needs.
param([string]$OutputDirectory = "build\halide-windows-x86_64")
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$halide = $env:HALIDE_ROOT
if (-not $halide) { throw "set HALIDE_ROOT to the Halide build with Vulkan support" }
$libraryDirectory = if (Test-Path "$halide\lib\Release\Halide.lib") { "$halide\lib\Release" } else { "$halide\lib" }
$cli = if (Test-Path "$halide\bin\Release\Halide.dll") { "$halide\bin\Release" } else { "$halide\bin" }
$env:Path = "$cli;$env:Path"
if (-not $env:HL_WINDOWS_TMP_DIR) {
    $env:HL_WINDOWS_TMP_DIR = Join-Path ([System.IO.Path]::GetTempPath()) "fotufilm-halide\"
    New-Item -ItemType Directory -Force $env:HL_WINDOWS_TMP_DIR | Out-Null
}
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$generator = Join-Path $OutputDirectory "generate-halide-aot.exe"

"Building the Halide generator..."
$sources = @("$root\tools\generate_halide_ios.cpp")
& cl.exe /nologo /std:c++17 /O2 /EHsc /MD /D_USE_MATH_DEFINES /I "$halide\include" /I "$root\Sources\FotufilmHalide\include" $sources "/Fe:$generator" "/Fo:$OutputDirectory\generator.obj" "$libraryDirectory\Halide.lib" user32.lib gdi32.lib ole32.lib shell32.lib advapi32.lib
if ($LASTEXITCODE -ne 0) { throw "the generator did not build" }

$variants = [int](& $generator $OutputDirectory --windows-vulkan --count)
"Generating $variants Vulkan variants..."
$jobs = [Math]::Max(1, [Environment]::ProcessorCount - 6)
function New-Variant($index, $prefix) {
    Start-Process -FilePath $generator -NoNewWindow -PassThru -ArgumentList @(
        $OutputDirectory, "--windows-vulkan", "--prefix=$prefix", "--variant=$index")
}
function Complete-Variant($process, $index, $prefix) {
    # A variant that dies (most often out of memory next to its siblings) is retried on its own.
    $attempts = 0
    while ($process.ExitCode -ne 0 -and $attempts -lt 3) {
        $attempts++
        Write-Host ("variant $index exited $($process.ExitCode); retry $attempts")
        $process = New-Variant $index $prefix
        $process | Wait-Process
    }
    if ($process.ExitCode -ne 0) { throw "variant $index failed after $attempts retries" }
}
for ($start = 0; $start -lt $variants; $start += $jobs) {
    $batch = @()
    for ($i = $start; $i -lt [Math]::Min($start + $jobs, $variants); $i++) {
        $batch += [pscustomobject]@{ Index = $i; Process = (New-Variant $i 'fotufilm_aot_vulkan_') }
    }
    $batch | ForEach-Object { $_.Process | Wait-Process }
    foreach ($item in $batch) { Complete-Variant $item.Process $item.Index 'fotufilm_aot_vulkan_' }
}
& $generator $OutputDirectory --windows-vulkan --prefix=fotufilm_aot_ --extras
if ($LASTEXITCODE -ne 0) { throw "the extras did not build" }
# The shim compiles with -I<output directory> and includes the Halide runtime headers from there.
foreach ($header in @('HalideBuffer.h', 'HalideRuntime.h', 'HalideRuntimeCuda.h', 'HalideRuntimeVulkan.h')) {
    $from = Join-Path $halide "include\$header"
    if (Test-Path $from) { Copy-Item $from (Join-Path $OutputDirectory $header) -Force }
}
"Wrote kernels to $OutputDirectory"