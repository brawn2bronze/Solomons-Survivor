<#
  get_godot.ps1 - portable, SHA512-verified Godot bootstrap for Solomon's Survivor.

  Downloads the official Godot release into tools/.godot-bin/ (repo-local, gitignored,
  no admin rights, no system install, no PATH change). Idempotent: re-running with the
  engine already present just prints the resolved path.

  The engine is what tools/check_parse.ps1 uses for the authoritative parse check
  (`godot --headless --path . --import` + `res://tests/smoke.tscn`).

  Usage:
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/get_godot.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/get_godot.ps1 -Force
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/get_godot.ps1 -Version 4.7.1-stable

  Exit codes:
    0 = engine present (installed now or already there)
    2 = download failed (network)
    3 = SHA512 mismatch (refusing to unpack a tampered/corrupt download)
    4 = unpack failed
#>
param(
  [string]$Version = "4.7.2-stable",
  [switch]$Force,
  [switch]$Quiet
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Pinned SHA512 digests, verified against the release's own SHA512-SUMS.txt.
# The remote sums file is the primary source; this table is the offline fallback so a
# download can still be verified if GitHub's release page is unreachable.
$KnownSha512 = @{
  "4.7.2-stable" = "83decd58fdf67b9d657958a1ae6bf1929c20785315a81effe245874cdc57acb709bf868e00778a96984338c1b29dafdb453c6847747694621c6ecf5da2259993"
  "4.7.1-stable" = ""
  "4.7-stable"   = ""
}

$binDir = Join-Path $PSScriptRoot ".godot-bin"
$exeName = "Godot_v$Version`_win64.exe"
$zipName = "Godot_v$Version`_win64.exe.zip"
$exePath = Join-Path $binDir $exeName
$baseUrl = "https://github.com/godotengine/godot/releases/download/$Version"

function Say([string]$m) { if (-not $Quiet) { Write-Output $m } }

# ---------------------------------------------------------------- already installed?
if ((Test-Path -LiteralPath $exePath) -and -not $Force) {
  Say "godot: already installed -> $exePath"
  & $exePath --version 2>&1 | ForEach-Object { Say "godot: $_" }
  exit 0
}

if (-not (Test-Path -LiteralPath $binDir)) {
  New-Item -ItemType Directory -Path $binDir -Force | Out-Null
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("godot-dl-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

try {
  $zipPath = Join-Path $tmp $zipName
  Say "godot: downloading $zipName ($Version) ..."
  try {
    Invoke-WebRequest -Uri "$baseUrl/$zipName" -OutFile $zipPath -UseBasicParsing
  } catch {
    Write-Output "godot: DOWNLOAD FAILED: $($_.Exception.Message)"
    exit 2
  }

  # ---- verify the digest before anything is unpacked -------------------------------
  $expected = ""
  try {
    $sumsPath = Join-Path $tmp "SHA512-SUMS.txt"
    Invoke-WebRequest -Uri "$baseUrl/SHA512-SUMS.txt" -OutFile $sumsPath -UseBasicParsing
    foreach ($line in [System.IO.File]::ReadAllLines($sumsPath)) {
      if ($line -match "^\s*([0-9a-fA-F]{128})\s+\*?\s*$( [regex]::Escape($zipName) )\s*$") {
        $expected = $Matches[1].ToLower()
        break
      }
    }
    if ($expected) { Say "godot: digest from release SHA512-SUMS.txt" }
  } catch {
    Say "godot: SHA512-SUMS.txt unavailable ($($_.Exception.Message)); using the pinned digest"
  }
  if (-not $expected -and $KnownSha512.ContainsKey($Version)) {
    $expected = $KnownSha512[$Version]
    Say "godot: digest from the pinned table"
  }
  if (-not $expected) {
    Write-Output "godot: NO TRUSTED DIGEST for $zipName - refusing to unpack an unverified download."
    exit 3
  }

  $actual = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA512).Hash.ToLower()
  if ($actual -ne $expected) {
    Write-Output "godot: SHA512 MISMATCH for $zipName"
    Write-Output "godot:   expected $expected"
    Write-Output "godot:   actual   $actual"
    exit 3
  }
  Say "godot: SHA512 verified"

  # ---- unpack ------------------------------------------------------------------------
  try {
    Expand-Archive -LiteralPath $zipPath -DestinationPath $tmp -Force
  } catch {
    Write-Output "godot: UNPACK FAILED: $($_.Exception.Message)"
    exit 4
  }
  $found = Get-ChildItem -LiteralPath $tmp -Recurse -Filter $exeName -File | Select-Object -First 1
  if (-not $found) {
    $found = Get-ChildItem -LiteralPath $tmp -Recurse -Filter "*.exe" -File | Select-Object -First 1
  }
  if (-not $found) {
    Write-Output "godot: no executable found inside $zipName"
    exit 4
  }
  if (Test-Path -LiteralPath $exePath) { Remove-Item -LiteralPath $exePath -Force }
  Move-Item -LiteralPath $found.FullName -Destination $exePath -Force
  $verFile = Join-Path $binDir "VERSION.txt"
  [System.IO.File]::WriteAllText($verFile, "version=$Version`nsha512=$actual`nexe=$exeName`n", (New-Object System.Text.UTF8Encoding($false)))

  Say "godot: installed -> $exePath"
  & $exePath --version 2>&1 | ForEach-Object { Say "godot: $_" }
  exit 0
} finally {
  if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
