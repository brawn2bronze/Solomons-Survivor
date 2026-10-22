<#
  check_all.ps1 - one command for every check in this project.

  Runs the tiers in the order that fails fastest:
    1. check_text.ps1          whitespace / encoding guard        (no engine, no python)
    2. check_project.py        static project checks + GDScript lint (python)
    3. check_evo.py            evolution option coverage          (no engine)
    4. check_black_market.py   black market data checks           (no engine)
    5. check_parse.ps1         the real Godot engine parse check  (needs Godot)

  Every tier prints its own verdict; this script adds the summary and the exit code.

  Usage:
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/check_all.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/check_all.ps1 -Strict
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/check_all.ps1 -Deep
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/check_all.ps1 -RequireGodot
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/check_all.ps1 -SelfTest

  -Strict       a tier's warnings count as failures
  -Deep         also run the headless smoke scene inside check_parse (slow)
  -RequireGodot treat a missing Godot as a failure instead of a skipped tier
  -SelfTest     verify the parse scanner itself (planted broken script) and stop

  Exit codes:
    0 = everything passed
    1 = at least one tier failed
    2 = a tier could not run (missing Godot / python) and -RequireGodot was given
#>
param(
  [switch]$Strict,
  [switch]$Deep,
  [switch]$RequireGodot,
  [switch]$SelfTest
)

$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot
if (Test-Path (Join-Path $root "survivor")) { $root = Join-Path $root "survivor" }

$results = New-Object System.Collections.Generic.List[object]

function Add-Result {
  param([string]$Tier, [int]$Code, [string]$Note = "")
  $results.Add([pscustomobject]@{ Tier = $Tier; Code = $Code; Note = $Note })
}

function Invoke-Tier {
  param([string]$Tier, [string]$Exe, [string[]]$TierArgs)
  Write-Output ""
  Write-Output ("=== {0} ===" -f $Tier)
  if (-not (Test-Path -LiteralPath $Exe)) {
    Write-Output ("{0}: NOT FOUND ({1})" -f $Tier, $Exe)
    Add-Result -Tier $Tier -Code 2 -Note "not found"
    return
  }
  $out = & $Exe @TierArgs 2>&1
  $code = $LASTEXITCODE
  $out | ForEach-Object { Write-Output ("  " + $_) }
  Add-Result -Tier $Tier -Code $code
}

$ps = (Get-Process -Id $PID).Path
$pyExe = (Get-Command python -ErrorAction SilentlyContinue)
$pyPath = if ($pyExe) { $pyExe.Source } else { $null }
$pyStrict = if ($Strict) { @("--strict") } else { @() }

# ---- 1. text ------------------------------------------------------------------------------
Invoke-Tier -Tier "check_text" -Exe $ps -TierArgs @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "check_text.ps1"))

# ---- 2. static project checks + GDScript lint ------------------------------------------------
if ($pyPath) {
  Invoke-Tier -Tier "check_project" -Exe $pyPath -TierArgs (@((Join-Path $PSScriptRoot "check_project.py")) + $pyStrict)
} else {
  Write-Output ""
  Write-Output "=== check_project ==="
  Write-Output "check_project: python not found - tier skipped"
  Add-Result -Tier "check_project" -Code 2 -Note "python not found"
}

# ---- 3. evolution coverage --------------------------------------------------------------------
if ($pyPath) {
  Invoke-Tier -Tier "check_evo" -Exe $pyPath -TierArgs @((Join-Path $PSScriptRoot "check_evo.py"))
} else {
  Write-Output ""
  Write-Output "=== check_evo ==="
  Write-Output "check_evo: python not found - tier skipped"
  Add-Result -Tier "check_evo" -Code 2 -Note "python not found"
}

# ---- 4. black market data --------------------------------------------------------------------
if ($pyPath) {
  Invoke-Tier -Tier "check_black_market" -Exe $pyPath -TierArgs (@((Join-Path $PSScriptRoot "check_black_market.py")) + $pyStrict)
} else {
  Write-Output ""
  Write-Output "=== check_black_market ==="
  Write-Output "check_black_market: python not found - tier skipped"
  Add-Result -Tier "check_black_market" -Code 2 -Note "python not found"
}

# ---- 5. the engine ----------------------------------------------------------------------------
$parseArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "check_parse.ps1"))
if ($Deep) { $parseArgs += "-Deep" }
if ($Strict) { $parseArgs += "-Strict" }
if ($SelfTest) { $parseArgs += "-SelfTest" }
Invoke-Tier -Tier "check_parse" -Exe $ps -TierArgs $parseArgs

# ---- summary ---------------------------------------------------------------------------------
Write-Output ""
Write-Output "=== summary ==="
$failed = 0
$skipped = 0
foreach ($r in $results) {
  $state = switch ($r.Code) {
    0 { "PASS" }
    2 { "SKIP" }
    default { "FAIL" }
  }
  if ($r.Code -eq 0) { } elseif ($r.Code -eq 2) { $skipped++ } else { $failed++ }
  Write-Output ("  {0,-5} {1} (exit {2}) {3}" -f $state, $r.Tier, $r.Code, $r.Note)
}

if ($skipped -gt 0) {
  Write-Output "check_all: $skipped tier(s) could not run (missing Godot or python)"
  if ($RequireGodot) { $failed++ }
}
if ($failed -gt 0) {
  Write-Output "check_all: FAIL ($failed tier(s) failed)"
  exit 1
}
Write-Output "check_all: PASS"
exit 0
