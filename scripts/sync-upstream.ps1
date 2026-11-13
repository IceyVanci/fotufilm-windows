<#
.SYNOPSIS
  Replays the port layer onto a new upstream release.
.DESCRIPTION
  vendor/upstream   the upstream checkout (git, read only)
  work/<version>    a clean copy with overlay, patches and the Chinese interface replayed
  Nothing here touches the upstream checkout, and no build runs; see scripts/build.ps1.
.EXAMPLE
  .\sync-upstream.ps1 -Tag v1.15
  .\sync-upstream.ps1 -Tag v1.16 -DryRun      # fetch and report, write nothing
#>
param(
  [Parameter(Mandatory = $true)][string]$Tag,
  [string]$Repo = 'DhaliwalX/fotufilm-engine',
  [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $PSCommandPath
$Root = Split-Path -Parent $Here
$Vendor = Join-Path $Root 'vendor\upstream'
$WorkRoot = Join-Path $Root 'work'
$Work = Join-Path $WorkRoot ($Tag -replace '^v', '')

function Say($m) { Write-Host ('  ' + $m) }
function Step($m) { Write-Host ''; Write-Host ('=== ' + $m + ' ===') -ForegroundColor Cyan }

# PowerShell 5.1 turns a native command's stderr into a terminating error whenever
# ErrorActionPreference is 'Stop' — even when the command succeeded, because git prints
# "HEAD is now at …" and "Note: switching to …" on stderr. Every native call in this script is
# judged by $LASTEXITCODE instead, so it runs with the preference relaxed; the streams are merged
# so nothing is lost either way.
function Invoke-Native([scriptblock]$Command) {
  $preference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try { & $Command 2>&1 | ForEach-Object { "$_" } }
  finally { $ErrorActionPreference = $preference }
}

# ---- 1. the upstream checkout ----------------------------------------------------------------
Step 'upstream'
New-Item -ItemType Directory -Force (Split-Path -Parent $Vendor) | Out-Null
if (-not (Test-Path (Join-Path $Vendor '.git'))) {
  Say "cloning $Repo"
  $null = Invoke-Native { git clone --filter=blob:none --no-checkout "https://github.com/$Repo.git" $Vendor }
  if ($LASTEXITCODE -ne 0) { throw 'clone failed' }
} else {
  $null = Invoke-Native { git -C $Vendor fetch --tags --force origin }
  if ($LASTEXITCODE -ne 0) { throw 'fetch failed' }
}
$null = Invoke-Native { git -C $Vendor checkout --force "tags/$Tag" }
if ($LASTEXITCODE -ne 0) { throw "no tag $Tag" }
$commit = ((Invoke-Native { git -C $Vendor rev-parse --short=8 HEAD }) -join '').Trim()
Say "$Tag = $commit"

# ---- 2. a clean work tree ---------------------------------------------------------------------
Step 'work tree'
if (Test-Path $Work) {
  if ($DryRun) { Say "$Work exists; a real run replaces it" }
  else { Remove-Item $Work -Recurse -Force }
}
if (-not $DryRun) {
  New-Item -ItemType Directory -Force $Work | Out-Null
  # Archive rather than copy: it never drags .git along. It is written to a file first, because
  # PowerShell 5.1 decodes a native command's stdout on its way through a pipeline, and a 40 MB
  # tar handed to tar.exe that way arrives corrupt ("Damaged tar archive", empty work tree).
  $archive = Join-Path ([System.IO.Path]::GetTempPath()) ("fotufilm-$Tag.tar")
  $null = Invoke-Native { git -C $Vendor archive --format=tar -o $archive "tags/$Tag" }
  if ($LASTEXITCODE -ne 0) { throw 'archive failed' }
  $null = Invoke-Native { tar -xf $archive -C $Work }
  if ($LASTEXITCODE -ne 0) { throw 'extract failed' }
  Remove-Item $archive -Force -ErrorAction SilentlyContinue
  Say "extracted to $Work"
}

# ---- 3. overlay -------------------------------------------------------------------------------
Step 'overlay'
$overlay = Join-Path $Root 'port\overlay'
$n = 0
Get-ChildItem $overlay -Recurse -File | ForEach-Object {
  $rel = $_.FullName.Substring($overlay.Length + 1)
  if ($rel -eq 'README.md' -or $rel -eq 'README.zh.md') { return }
  $dst = Join-Path $Work $rel
  if ($DryRun) { if (Test-Path $dst) { Say "would replace $rel" } } 
  else {
    New-Item -ItemType Directory -Force (Split-Path -Parent $dst) | Out-Null
    Copy-Item $_.FullName $dst -Force
  }
  $n++
}
Say "$n files"

# ---- 4. patches -------------------------------------------------------------------------------
Step 'patches'
# The work tree sits inside this repository, so git discovers this repository from it and resolves
# the patch paths against *this* root, where none of them exist — and rather than failing, git
# reports "Skipped patch" and exits 0. A ceiling stops the search above the work tree, so the
# patches apply to the work tree itself, as they do when it is unpacked outside any repository.
$previousCeiling = $env:GIT_CEILING_DIRECTORIES
$env:GIT_CEILING_DIRECTORIES = $Root
$failed = @()
Get-ChildItem (Join-Path $Root 'port\patches') -Filter '*.patch' | Sort-Object Name | ForEach-Object {
  if ($DryRun) {
    $null = Invoke-Native { git -C $Work apply --check $_.FullName }
    if ($LASTEXITCODE -ne 0) { $failed += $_.Name }
  } else {
    $null = Invoke-Native { git -C $Work apply --whitespace=nowarn $_.FullName }
    if ($LASTEXITCODE -ne 0) { $failed += $_.Name }
  }
}
$env:GIT_CEILING_DIRECTORIES = $previousCeiling
if ($failed.Count) {
  Write-Host ''
  Write-Host ('patches that no longer apply: ' + $failed.Count) -ForegroundColor Yellow
  $failed | ForEach-Object { Say $_ }
  Write-Host '  Upstream changed those files. Take its version, drop the stale overlay entry if there' 
  Write-Host '  is one, and let the rewriter regenerate the Chinese (see port/README.md rule 2).'
} else {
  Say 'all patches applied'
}

# ---- 5. the Chinese interface ------------------------------------------------------------------
Step 'Chinese interface'
if (-not $DryRun) {
  $tool = Join-Path $Root 'port\i18n\apply-zh.cjs'
  node $tool --root $Work --apply
  if ($LASTEXITCODE -ne 0) { throw 'the rewriter failed' }
  node (Join-Path $Root 'port\i18n\check-zh.cjs') --root $Work
  if ($LASTEXITCODE -ne 0) { throw 'the interface checks failed: a key literal was translated, or a slider group is missing' }
}

# ---- 6. record ----------------------------------------------------------------------------------
Step 'lock'
if (-not $DryRun) {
  $lockPath = Join-Path $Root 'upstream.lock'
  $lock = Get-Content $lockPath -Raw
  $lock = [regex]::Replace($lock, 'upstream_tag = "[^"]*"', 'upstream_tag = "' + $Tag + '"')
  $lock = [regex]::Replace($lock, 'upstream_commit = "[^"]*"', 'upstream_commit = "' + $commit + '"')
  Set-Content -Path $lockPath -Value $lock -NoNewline
  Say "upstream.lock -> $Tag ($commit)"
}

Write-Host ''
if ($failed.Count) {
  Write-Host 'Replay finished with patch conflicts; resolve them before building.' -ForegroundColor Yellow
  exit 1
}
Write-Host ('Next: scripts\build.ps1 -Source ' + $Work) -ForegroundColor Green
