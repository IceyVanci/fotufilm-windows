# Stages what the Flutter editor reads from the rest of the repository into assets/generated:
# the control catalogue and glyphs, the Material Symbols and the Satoshi typeface.
# The Windows counterpart of tool/prepare.sh; nothing staged is committed.
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$repo = Split-Path -Parent $here
$out = Join-Path $here "assets\generated"
New-Item -ItemType Directory -Force (Join-Path $out "glyphs"), (Join-Path $out "fonts") | Out-Null

$web = ($repo -replace "\\", "/") + "/web/src/generated/controls.js"
$script = "import('file:///" + $web + "').then(m => process.stdout.write(JSON.stringify(m)))"
node --input-type=module -e $script | Set-Content -Path (Join-Path $out "controls.json") -NoNewline -Encoding utf8
Copy-Item (Join-Path $repo "web\src\material-symbols.json") $out -Force
Copy-Item (Join-Path $repo "web\src\assets\fotufilm-wordmark.svg") $out -Force
Copy-Item (Join-Path $repo "web\public\app-icon.png") $out -Force
Get-ChildItem (Join-Path $repo "web\public\glyphs") -Filter "fotu.*.svg" | Copy-Item -Destination (Join-Path $out "glyphs") -Force

$regular = Join-Path $out "fonts\Satoshi-Regular.otf"
if (-not (Test-Path $regular)) {
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("satoshi-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Force $tmp | Out-Null
    $zip = Join-Path $tmp "satoshi.zip"
    Invoke-WebRequest -Uri "https://api.fontshare.com/v2/fonts/download/satoshi" -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $wanted = @("Satoshi-Regular.otf", "Satoshi-Medium.otf", "Satoshi-Bold.otf")
    Get-ChildItem $tmp -Recurse -Filter "Satoshi-*.otf" | Where-Object { $wanted -contains $_.Name } |
        Copy-Item -Destination (Join-Path $out "fonts") -Force
    Remove-Item -Recurse -Force $tmp
}

$glyphs = (Get-ChildItem (Join-Path $out "glyphs") -Filter "*.svg" | Measure-Object).Count
"Staged $glyphs glyphs, the control catalogue and Satoshi in $out"