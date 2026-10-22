<#
  check_parse.ps1 - the authoritative parse check for Solomon's Survivor.

  This is the tier that cannot lie: it runs the real Godot engine over the project and
  reports what the engine says. Everything else in tools/ is a fast approximation; this
  is the ground truth.

  It runs three engine passes:
    1. --headless --path . --import
         Import pass. Catches scripts the editor reloads on import.
    2. --headless --path . res://tests/script_sweep.tscn
         Loads EVERY .gd script in the project (including ones no scene references) so
         the engine parses and analyses all of them. This is the pass that catches the
         bulk of the errors.
    3. --headless --path . res://tests/smoke.tscn          (-Deep only, ~50s)
         Boots the actual game and runs the headless smoke test.

  The engine always exits 0, even with parse errors, so the EXIT CODE IS IGNORED and the
  output is scanned instead.

  Godot prints warnings (unused_parameter, unused_variable) only in the editor UI, never
  on the command line, so the unused-parameter warnings are filled in from the static
  rule in tools/gdscript_lint.py - the single owner of that rule - for the same files.

  Usage:
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/check_parse.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/check_parse.ps1 -Strict
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/check_parse.ps1 -Deep
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/check_parse.ps1 -SelfTest
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/check_parse.ps1 -KeepCache

  Exit codes:
    0 = clean
    1 = script errors (or warnings, with -Strict)
    2 = GODOT_MISSING (run tools/get_godot.ps1)
    3 = the engine could not run
    4 = self-test failed (only with -SelfTest)
#>
param(
  [switch]$Strict,
  [switch]$Deep,
  [switch]$KeepCache,
  [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if (Test-Path (Join-Path $root "survivor")) { $root = Join-Path $root "survivor" }

# ------------------------------------------------------------------ locate the engine
function Resolve-Godot {
  if ($env:GODOT_EXE -and (Test-Path -LiteralPath $env:GODOT_EXE)) { return (Resolve-Path -LiteralPath $env:GODOT_EXE).Path }
  $binDir = Join-Path $PSScriptRoot ".godot-bin"
  if (Test-Path -LiteralPath $binDir) {
    $local = Get-ChildItem -LiteralPath $binDir -Filter "*.exe" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($local) { return $local.FullName }
  }
  $cmd = Get-Command godot -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}

# ------------------------------------------------------------------ run the engine
function Invoke-Godot {
  param([string]$Exe, [string[]]$GodotArgs)
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $Exe
  $psi.WorkingDirectory = $root
  $psi.Arguments = ($GodotArgs | ForEach-Object { '"' + $_ + '"' }) -join " "
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $p = [System.Diagnostics.Process]::Start($psi)
  $tOut = $p.StandardOutput.ReadToEndAsync()
  $tErr = $p.StandardError.ReadToEndAsync()
  $p.WaitForExit()
  $out = $tOut.Result
  $err = $tErr.Result
  return @{ Code = $p.ExitCode; Text = ($out + "`n" + $err) }
}

# ------------------------------------------------------------------ scan the output
function Get-GodotFindings {
  param([string]$Text)
  $findings = New-Object System.Collections.Generic.List[object]
  $cascades = 0
  $severity = $null
  $message = $null
  foreach ($raw in ($Text -split "`r?`n")) {
    $line = ($raw -replace "`e\[[0-9;]*[A-Za-z]", "").Trim()
    if (-not $line) { continue }
    if ($line -match '^(SCRIPT ERROR|SCRIPT WARNING|USER ERROR|USER WARNING|ERROR|WARNING)\s*:\s*(.*)$') {
      $severity = $Matches[1]
      $message = $Matches[2]
      continue
    }
    if ($line -match '^at:\s+.*\((res://[^()]+):(\d+)\)') {
      $file = $Matches[1]
      $lineNo = [int]$Matches[2]
      if ($message -eq $null) { continue }
      # A location on line 0, or a "depended scripts" failure, is the engine telling us
      # that a dependency failed - not a new problem. Count it, do not report it twice.
      if ($lineNo -eq 0 -or $message -match 'Failed to compile depended scripts|Failed to load script') {
        $cascades++
        $message = $null
        continue
      }
      $sev = "error"
      if ($severity -match 'WARNING') { $sev = "warning" }
      $findings.Add([pscustomobject]@{
        Severity = $sev
        File = $file
        Line = $lineNo
        Message = $message
      })
      $message = $null
      continue
    }
  }
  return @{ Findings = $findings; Cascades = $cascades }
}

# ------------------------------------------------------------------ restore the cache
function Restore-GodotCache {
  if ($KeepCache) { return }
  $git = Get-Command git -ErrorAction SilentlyContinue
  if (-not $git) { return }
  $cache = Join-Path $root ".godot"
  if (-not (Test-Path -LiteralPath $cache)) { return }
  Push-Location (Split-Path -Parent $root)
  try {
    & git checkout -- "survivor/.godot/" 2>&1 | Out-Null
  } catch {
    # a dirty cache is not worth failing the run over
  } finally {
    Pop-Location
  }
}

# ------------------------------------------------------------------ self test
function Invoke-SelfTest {
  param([string]$Exe)
  $fixture = Join-Path $root "tests/_selftest_broken.gd"
  $expectLine = 4
  try {
    $body = "extends RefCounted`n`nfunc broken() -> void:`n`tvar x := {}.get(`"k`")`n`tprint(x)`n"
    [System.IO.File]::WriteAllText($fixture, $body, (New-Object System.Text.UTF8Encoding($false)))
    $run = Invoke-Godot -Exe $Exe -GodotArgs @("--headless", "--path", $root, "res://tests/script_sweep.tscn")
    $scan = Get-GodotFindings -Text $run.Text
    $hit = $scan.Findings | Where-Object { $_.File -eq "res://tests/_selftest_broken.gd" -and $_.Line -eq $expectLine }
    if ($hit) {
      return @{ Code = 0; Message = "check_parse self-test: OK (the scanner caught the planted error at tests/_selftest_broken.gd:$expectLine)" }
    }
    $detail = ($scan.Findings | ForEach-Object { "  {0} {1}:{2} {3}" -f $_.Severity, $_.File, $_.Line, $_.Message }) -join "`n"
    return @{ Code = 4; Message = ("check_parse self-test: FAILED - the planted parse error was not reported`n" + $detail) }
  } catch {
    return @{ Code = 4; Message = ("check_parse self-test: FAILED - " + $_.Exception.Message) }
  } finally {
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Force -ErrorAction SilentlyContinue }
  }
}

# ================================================================== main
$exe = Resolve-Godot
if (-not $exe) {
  Write-Output "check_parse: GODOT_MISSING"
  Write-Output "  The engine is not installed. Run:  powershell -NoProfile -ExecutionPolicy Bypass -File tools/get_godot.ps1"
  Write-Output "  (or set GODOT_EXE to a Godot 4.7 executable)"
  exit 2
}

if ($SelfTest) {
  $result = Invoke-SelfTest -Exe $exe
  Write-Output $result.Message
  Restore-GodotCache
  exit $result.Code
}

Write-Output "check_parse: godot -> $exe"

$passes = @(
  @{ Label = "import"; Args = @("--headless", "--path", $root, "--import") },
  @{ Label = "sweep";  Args = @("--headless", "--path", $root, "res://tests/script_sweep.tscn") }
)
if ($Deep) {
  $passes += @{ Label = "smoke"; Args = @("--headless", "--path", $root, "res://tests/smoke.tscn") }
}

$all = New-Object System.Collections.Generic.List[object]
$cascades = 0
$failedPass = $false
foreach ($pass in $passes) {
  $run = Invoke-Godot -Exe $exe -GodotArgs $pass.Args
  if (-not $run.Text) { $failedPass = $true }
  $scan = Get-GodotFindings -Text $run.Text
  foreach ($f in $scan.Findings) {
    $all.Add([pscustomobject]@{ Severity = $f.Severity; File = $f.File; Line = $f.Line; Message = $f.Message; Pass = $pass.Label })
  }
  $cascades += $scan.Cascades
}

# Dedupe: the same location can be reported by more than one pass.
$seen = @{}
$unique = New-Object System.Collections.Generic.List[object]
foreach ($f in $all) {
  $key = "{0}|{1}|{2}" -f $f.File, $f.Line, $f.Message
  if ($seen.ContainsKey($key)) { continue }
  $seen[$key] = $true
  $unique.Add($f)
}

# The engine never prints WARN-level diagnostics on the command line, so the
# unused-parameter warnings come from the static rule that owns them.
$staticCount = 0
$py = Get-Command python -ErrorAction SilentlyContinue
if ($py) {
  $lint = Join-Path $PSScriptRoot "gdscript_lint.py"
  if (Test-Path -LiteralPath $lint) {
    try {
      $json = (& $py.Source $lint --json 2>$null | Out-String).Trim()
      $items = ConvertFrom-Json -InputObject $json
      foreach ($item in @($items)) {
        if ($item.code -ne "GDS201") { continue }
        $staticCount++
        $key = "{0}|{1}|{2}" -f ("res://" + $item.path), $item.line, $item.message
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $unique.Add([pscustomobject]@{
          Severity = "warning"; File = ("res://" + $item.path); Line = $item.line
          Message = ("[static rule] " + $item.message); Pass = "static"
        })
      }
    } catch {
      Write-Output "check_parse: could not run the static lint rule ($($_.Exception.Message))"
    }
  }
}

Restore-GodotCache

if ($failedPass) {
  Write-Output "check_parse: the engine produced no output - treat this run as failed"
  exit 3
}

$errors = @($unique | Where-Object { $_.Severity -eq "error" })
$warnings = @($unique | Where-Object { $_.Severity -eq "warning" })

foreach ($f in ($unique | Sort-Object File, Line)) {
  $rel = $f.File -replace '^res://', ''
  Write-Output ("  {0,-7} {1}:{2}  {3}" -f $f.Severity.ToUpper(), $rel, $f.Line, $f.Message)
}

Write-Output ("check_parse: {0} error(s), {1} warning(s){2}" -f `
  $errors.Count, $warnings.Count, $(if ($cascades -gt 0) { " ($cascades cascade(s) suppressed)" } else { "" }))
if ($staticCount -gt 0) {
  Write-Output "check_parse: $staticCount unused-parameter warning(s) come from the static rule (the engine prints those only in the editor)"
}

if ($errors.Count -gt 0) { exit 1 }
if ($Strict -and $warnings.Count -gt 0) { exit 1 }
exit 0
