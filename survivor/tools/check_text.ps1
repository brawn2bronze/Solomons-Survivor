<#
  check_text.ps1 - thin wrapper kept so check_all.ps1, the pre-commit hook and old habits keep working.
  The real checker is tools/check_text.py: a file's expected indent style is whatever it has at git HEAD,
  so there is no per-file list to maintain. Line endings only have to be internally consistent.

  powershell -NoProfile -ExecutionPolicy Bypass -File survivor/tools/check_text.ps1            check every .gd file
  powershell -NoProfile -ExecutionPolicy Bypass -File survivor/tools/check_text.ps1 --fix      repair whitespace damage
  Exit code 1 when anything is left unfixed.
#>
$script = Join-Path $PSScriptRoot "check_text.py"
$exe = $null
foreach ($name in @("python", "py")) {
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if ($cmd) {
    & $cmd.Source --version *> $null
    if ($LASTEXITCODE -eq 0) { $exe = $cmd.Source; break }
  }
}
if (-not $exe) {
  Write-Output "check_text: no working python found (tried python, py). Install Python 3."
  exit 2
}
& $exe $script @args
exit $LASTEXITCODE
