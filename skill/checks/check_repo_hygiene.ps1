# =============================================================================
# check_repo_hygiene.ps1 -- repository hygiene check before submission
#
# Checks what the competition guide explicitly requires:
#   "All directory and file names must be purely English (lowercase letters,
#    digits, underscore or hyphen); no Chinese, no spaces, no special chars."
#
# Also checks that the required top-level entries exist.
#
# ASCII ONLY (PowerShell on zh-CN Windows reads .ps1 using the system code page).
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File check_repo_hygiene.ps1
#   powershell ... -File check_repo_hygiene.ps1 -Root C:\path\to\repo
# =============================================================================

param(
    [string]$Root = (Get-Location).Path
)

$fail = 0

Write-Host "=== repo hygiene check ==="
Write-Host ("root: {0}" -f $Root)
Write-Host ""

# ---------------------------------------------------------------- [1] required
Write-Host "[1] required top-level entries"
$required = @("README.md", "src", "sim", "build", "board", "data", "skill", "report")
foreach ($r in $required) {
    $p = Join-Path $Root $r
    if (Test-Path $p) {
        Write-Host ("    OK   {0}" -f $r)
    } else {
        Write-Host ("    MISS {0}" -f $r) -ForegroundColor Yellow
    }
}
Write-Host ""

# ------------------------------------------------------------- [2] charset
Write-Host "[2] filename charset (ASCII, lowercase, no spaces)"
$badPaths = @()
$badCase  = @()
$all = Get-ChildItem -Path $Root -Recurse -Force -ErrorAction SilentlyContinue |
       Where-Object { $_.FullName -notmatch '\\\.git\\' }

foreach ($item in $all) {
    $rel = $item.FullName.Substring($Root.Length).TrimStart('\')
    $leaf = $item.Name

    # non-ASCII bytes in the name
    $nonAscii = $false
    foreach ($ch in $leaf.ToCharArray()) {
        if ([int][char]$ch -gt 127) { $nonAscii = $true; break }
    }
    if ($nonAscii) { $badPaths += $rel; continue }

    # spaces or special chars
    if ($leaf -match '[ ]') { $badPaths += ($rel + "   (contains space)"); continue }

    # uppercase letters (guide asks for lowercase)
    if ($leaf -cmatch '[A-Z]') { $badCase += $rel }
}

if ($badPaths.Count -eq 0) {
    Write-Host ("    OK   all {0} paths are ASCII and space-free" -f $all.Count)
} else {
    Write-Host ("    FAIL {0} path(s) with non-ASCII or space:" -f $badPaths.Count) -ForegroundColor Red
    foreach ($b in $badPaths) { Write-Host ("         {0}" -f $b) }
    $fail = 1
}

if ($badCase.Count -eq 0) {
    Write-Host "    OK   no uppercase letters in filenames"
} else {
    Write-Host ("    WARN {0} path(s) contain uppercase (guide recommends lowercase):" -f $badCase.Count) -ForegroundColor Yellow
    foreach ($b in $badCase) { Write-Host ("         {0}" -f $b) }
}
Write-Host ""

# ------------------------------------------------------------- [3] skill pkg
Write-Host "[3] skill package contents"
$skillDir = Join-Path $Root "skill"
if (Test-Path $skillDir) {
    $need = @("README.md")
    foreach ($n in $need) {
        if (Test-Path (Join-Path $skillDir $n)) { Write-Host ("    OK   skill/{0}" -f $n) }
        else { Write-Host ("    MISS skill/{0}" -f $n) -ForegroundColor Yellow }
    }
    $subdirs = @("pitfalls", "templates", "prompts", "checks")
    foreach ($d in $subdirs) {
        if (Test-Path (Join-Path $skillDir $d)) { Write-Host ("    OK   skill/{0}/" -f $d) }
        else { Write-Host ("    MISS skill/{0}/" -f $d) -ForegroundColor Yellow }
    }
} else {
    Write-Host "    MISS skill/ (not created yet)"
}
Write-Host ""

# ------------------------------------------------------------- [4] leftovers
Write-Host "[4] leftover artifacts (should NOT be committed)"
$junk = @("*.jou", "*.log", "*.str", "*.Xil", "*.tmp", "*.bak", "*~")
$found = @()
foreach ($j in $junk) {
    $hits = Get-ChildItem -Path $Root -Recurse -Force -Include $j -ErrorAction SilentlyContinue
    foreach ($h in $hits) { $found += $h.FullName.Substring($Root.Length).TrimStart('\') }
}
if ($found.Count -eq 0) {
    Write-Host "    OK   no build logs or editor backups found"
} else {
    Write-Host ("    WARN {0} leftover file(s):" -f $found.Count) -ForegroundColor Yellow
    foreach ($x in ($found | Select-Object -First 15)) { Write-Host ("         {0}" -f $x) }
}
Write-Host ""

# ---------------------------------------------------------------- result
if ($fail -eq 0) {
    Write-Host "RESULT: PASS" -ForegroundColor Green
    Write-Host ""
    Write-Host "NOTE: this checks structure and naming only."
    Write-Host "      'Can it be reproduced from zero' must be verified by actually"
    Write-Host "      running the build in a clean environment. This script cannot replace that."
} else {
    Write-Host "RESULT: FAIL  (fix the FAIL items above)" -ForegroundColor Red
    exit 1
}
