# Generates the CPU fallback's kernels for Windows: the reference CPU pipeline compiled for
# x86-64-windows-avx2, the same schedules the browser's CPU fallback links.
#   tools/generate-halide-cpu-windows.ps1 [-OutputDirectory <aot dir>] [-Target x86-64-windows-avx2]
#
# The modules are compiled with Halide::Target::NoRuntime: FotufilmHalideLinux.cpp links the one
# standalone runtime the Vulkan AOT step writes (fotufilm_aot_runtime.a), and a second copy of the
# runtime would collide with it. Run tools/generate-halide-aot-windows.ps1 first.
param(
    [string]$OutputDirectory = "build\halide-windows-x86_64",
    [string]$Target = "x86-64-windows-avx2"
)
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
$generator = Join-Path $OutputDirectory "generate-halide-cpu.exe"

"Building the CPU generator..."
$sources = @("$root\tools\generate_halide_cpu_windows.cpp")
& cl.exe /nologo /std:c++17 /O2 /EHsc /MD /D_USE_MATH_DEFINES /I "$halide\include" /I "$root\Sources\FotufilmHalide\include" $sources "/Fe:$generator" "/Fo:$OutputDirectory\generator-cpu.obj" "$libraryDirectory\Halide.lib" user32.lib gdi32.lib ole32.lib shell32.lib advapi32.lib
if ($LASTEXITCODE -ne 0) { throw "the generator did not build" }

"Generating the CPU kernels for $Target..."
& $generator $OutputDirectory $Target
if ($LASTEXITCODE -ne 0) { throw "the CPU kernels did not build" }
"Wrote CPU kernels to $OutputDirectory"
