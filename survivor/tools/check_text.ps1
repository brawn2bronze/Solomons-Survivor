<#
  check_text.ps1 - whitespace/encoding guard for Solomon's Survivor.
  Catches the three failure modes that repeatedly killed boot:
    1. mojibake (a UTF-8 file rewritten through CP1252: em-dash -> "a-euro-quote" etc.)
    2. indentation style drift (a tab line inside a spaces file, or vice versa)
    3. mixed leading whitespace (spaces after tabs) on one line
  Runs with no Godot and no Python: pure PowerShell 5.1.

  Usage:
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/check_text.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/check_text.ps1 -Classify
  Exit code 1 when any violation is found (CI/agent friendly).
#>
param(
  [switch]$Classify
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if (Test-Path (Join-Path $root "survivor")) { $root = Join-Path $root "survivor" }

# Expected leading-indent style per file. KEEP IN SYNC WITH workbench.md section 3.
# TAB = first non-empty char of every code line is 0x09
# SPACE = first non-empty char is 0x20, depth in multiples of 4
# FLAT = no indentation anywhere (data defs)
$TAB = @(
  "autoload/game.gd", "src/core/gem_manager.gd", "src/core/world.gd",
  "src/player/player.gd", "src/core/status_icons.gd", "src/core/fx_manager.gd",
  "src/core/fx_layer.gd", "src/core/critter_manager.gd", "src/core/enemy_manager.gd",
  "src/ui/dev_menu.gd", "src/ui/dev_overlay.gd", "src/main.gd", "src/ui/coin_icon.gd",
  "src/ui/pause_menu.gd", "src/core/act_ambient.gd", "tests/fx_gallery.gd",
  "src/abilities/ability.gd",
  "src/abilities/evo/evo_module.gd", "src/abilities/evo/evo_registry.gd",
  "src/abilities/evo/flash_bombs_evo.gd"
)
$SPACE = @(
  "autoload/audio_manager.gd", "autoload/db.gd", "autoload/meta.gd",
  "data/seal/global_seal_data.gd", "data/seal/hero_seal_data.gd",
  "src/abilities/evo_prims.gd",
  "src/abilities/evo/flailing_whip_evo.gd", "src/abilities/evo/katana_evo.gd",
  "src/abilities/evo/six_shooter_evo.gd", "src/abilities/evo/hand_cannon_evo.gd",
  "src/abilities/evo/pirate_crew_evo.gd", "src/abilities/evo/paladin_evo.gd",
  "src/abilities/passive_behaviors.gd", "src/abilities/weapon_behaviors.gd",
  "src/core/act_manager.gd", "src/core/chest_manager.gd", "src/core/coin_manager.gd",
  "src/core/descent.gd", "src/core/ground_layer.gd", "src/core/projectile_manager.gd",
  "src/ui/ability_art.gd", "src/ui/act_banner.gd", "src/ui/act_clear_screen.gd",
  "src/ui/black_market_screen.gd", "src/ui/character_select.gd",
  "src/ui/gameover_screen.gd", "src/ui/hud.gd", "src/ui/levelup_screen.gd",
  "src/ui/main_menu.gd", "src/ui/menu_music_curve.gd", "src/ui/options_panel.gd",
  "src/ui/seal_screen.gd", "src/ui/touch_controls.gd", "src/ui/ui.gd",
  "tests/smoke.gd", "tests/script_sweep.gd", "tests/_selftest_broken.gd",
  "tools/check_evo.gd"
)
$FLAT = @(
  "data/defs/ability_def.gd", "data/defs/act_def.gd", "data/defs/character_def.gd",
  "data/defs/enemy_def.gd", "data/defs/market_item_def.gd", "data/defs/passive_def.gd",
  "data/defs/upgrade_def.gd", "data/defs/weapon_def.gd"
)
# The only legal spaces inside a tab file: string literals (world.gd shader). Any line
# inside a triple-quoted block is skipped by the scanner, so nothing extra is needed here.

$mojiPatterns = @(
  ([string][char]0x00E2 + [char]0x20AC),
  ([string][char]0x00C2 + [char]0x00A7),
  ([string][char]0x00C3 + [char]0x00A9),
  ([string][char]0x00E2 + [char]0x201E),
  ([string][char]0x00E2 + [char]0x2019)
)

function Get-CodeLines {
  param([string[]]$Raw)
  $out = New-Object System.Collections.Generic.List[object]
  $inStr = $false
  for ($i = 0; $i -lt $Raw.Length; $i++) {
    $line = $Raw[$i]
    $q = ([regex]::Matches($line, '"""')).Count
    if ($inStr) {
      if ($q % 2 -eq 1) { $inStr = $false }
      continue
    }
    if ($q % 2 -eq 1) { $inStr = $true; continue }
    $out.Add([pscustomobject]@{ N = $i + 1; Text = $line })
  }
  return $out
}

$all = ($TAB + $SPACE + $FLAT) | ForEach-Object { $_ }
$violations = New-Object System.Collections.Generic.List[string]
$gdFiles = Get-ChildItem $root -Recurse -Include *.gd -File |
  Where-Object { $_.FullName -notmatch '\\\.godot\\' }

foreach ($f in $gdFiles) {
  $rel = $f.FullName.Substring($root.Length + 1).Replace('\', '/')
  $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
  $text = [System.Text.Encoding]::UTF8.GetString($bytes)

  foreach ($pat in $mojiPatterns) {
    $idx = $text.IndexOf($pat)
    if ($idx -ge 0) {
      $line = ($text.Substring(0, $idx) -split "`n").Count
      $violations.Add("MOJIBAKE ${rel}:$line (CP1252 round-trip)")
      break
    }
  }

  $expect = if ($TAB -contains $rel) { "TAB" } elseif ($SPACE -contains $rel) { "SPACE" } elseif ($FLAT -contains $rel) { "FLAT" } else { "?" }
  $lines = Get-CodeLines ($text -split "`r?`n")

  $t = 0; $s = 0
  foreach ($ln in $lines) {
    if ($ln.Text.Length -eq 0) { continue }
    $first = $ln.Text[0]
    if ($first -eq "`t") { $t++ } elseif ($first -eq " ") { $s++ }
  }
  $detected = if ($t -gt 0 -and $s -gt 0) { "MIXED" } elseif ($t -gt 0) { "TAB" } elseif ($s -gt 0) { "SPACE" } else { "FLAT" }

  if ($Classify) {
    Write-Output ("{0}`t{1}`t(t={2} s={3})" -f $detected, $rel, $t, $s)
    continue
  }

  if ($expect -eq "?") {
    $violations.Add("UNCLASSIFIED $rel (add it to check_text.ps1 + workbench.md section 3)")
  }

  foreach ($ln in $lines) {
    if ($ln.Text.Length -eq 0) { continue }
    $lead = 0
    $hasTab = $false; $hasSpace = $false
    while ($lead -lt $ln.Text.Length -and ($ln.Text[$lead] -eq "`t" -or $ln.Text[$lead] -eq " ")) {
      if ($ln.Text[$lead] -eq "`t") { $hasTab = $true } else { $hasSpace = $true }
      $lead++
    }
    if ($lead -eq 0) { continue }
    if ($hasTab -and $hasSpace) {
      $violations.Add("MIXED-WS ${rel}:$($ln.N)")
      continue
    }
    if ($expect -eq "TAB" -and $hasSpace) { $violations.Add("SPACE-IN-TAB ${rel}:$($ln.N)") }
    if ($expect -eq "SPACE" -and $hasTab) { $violations.Add("TAB-IN-SPACE ${rel}:$($ln.N)") }
    if ($expect -eq "SPACE" -and $hasSpace -and ($lead % 4) -ne 0) { $violations.Add("ODD-INDENT ${rel}:$($ln.N) ($lead spaces)") }
    if ($expect -eq "FLAT") { $violations.Add("INDENT-IN-FLAT ${rel}:$($ln.N)") }
  }

  # Depth sanity: catch a body line indented deeper than its previous code line
  # with no block opener (":") and no open ()/[]/{} continuation. This is the
  # 2026-10-18 enemy_manager bug class (parser: "Could not parse global class").
  $prevDepth = -1; $prevOpens = $true; $brace = 0
  foreach ($ln in $lines) {
    $trim = $ln.Text.Trim()
    if ($trim.Length -eq 0 -or $trim.StartsWith('#')) { continue }
    $lead = 0; $k = 0
    if ($detected -eq "TAB") {
      while ($k -lt $ln.Text.Length -and $ln.Text[$k] -eq "`t") { $lead++; $k++ }
    } else {
      $sp = 0
      while ($k -lt $ln.Text.Length -and $ln.Text[$k] -eq ' ') { $sp++; $k++ }
      $lead = [Math]::Floor($sp / 4)
    }
    $code = (($trim -replace '"[^"]*"', '""' -replace "'[^']*'", "''") -split '#')[0].TrimEnd()
    $opens = $code.EndsWith(':')
    if ($lead -gt $prevDepth -and -not $prevOpens -and $brace -le 0) {
      $violations.Add("OVER-INDENT ${rel}:$($ln.N) (depth $lead after depth $prevDepth)")
    }
    foreach ($ch in $code.ToCharArray()) {
      if ($ch -eq '(' -or $ch -eq '[' -or $ch -eq '{') { $brace++ }
      elseif ($ch -eq ')' -or $ch -eq ']' -or $ch -eq '}') { $brace-- }
    }
    if ($brace -lt 0) { $brace = 0 }
    $prevDepth = $lead
    $prevOpens = $opens
  }
}

if ($Classify) { exit 0 }

if ($violations.Count -eq 0) {
  Write-Output "check_text: OK ($($gdFiles.Count) .gd files clean)"
  exit 0
}
Write-Output "check_text: $($violations.Count) violation(s)"
$violations | Sort-Object -Unique | ForEach-Object { Write-Output "  $_" }
exit 1
