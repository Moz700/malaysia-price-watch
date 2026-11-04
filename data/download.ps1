# Malaysia Price Watch - downloads all 15 data files into this folder.
# Run it from PowerShell, in the repo root (the malaysia-price-watch folder), with:
#   powershell -ExecutionPolicy Bypass -File data\download.ps1
# Files that are already downloaded are skipped, so it is safe to run again.

$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$dest = $PSScriptRoot
$base = "https://storage.data.gov.my/pricecatcher"

$files = @()
$months = "2025-10","2025-11","2025-12","2026-01","2026-02","2026-03","2026-04","2026-05","2026-06","2026-07","2026-08","2026-09"
foreach ($m in $months) { $files += ,@("$base/pricecatcher_$m.csv", "pricecatcher_$m.csv") }
$files += ,@("$base/lookup_item.csv", "lookup_item.csv")
$files += ,@("$base/lookup_premise.csv", "lookup_premise.csv")
$files += ,@("https://storage.dosm.gov.my/cpi/cpi_2d_state.csv", "cpi_2d_state.csv")

$failed = @()
$i = 0
foreach ($f in $files) {
  $i++
  $url = $f[0]; $out = Join-Path $dest $f[1]
  if ((Test-Path $out) -and ((Get-Item $out).Length -gt 0)) {
    Write-Host "[$i/15] Already have $($f[1]), skipping"
    continue
  }
  Write-Host "[$i/15] Downloading $($f[1]) ..."
  try {
    Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing
  } catch {
    Write-Host "    FAILED: $url" -ForegroundColor Red
    if (Test-Path $out) { Remove-Item $out }
    $failed += $url
  }
}

Write-Host ""
Write-Host "Files in the data folder:"
Get-ChildItem $dest -Filter *.csv | Select-Object Name, @{n='MB';e={[math]::Round($_.Length/1MB,1)}} | Format-Table -AutoSize

if ($failed.Count -eq 0) {
  Write-Host "All 15 files downloaded." -ForegroundColor Green
} else {
  Write-Host "$($failed.Count) file(s) failed. Open these links in your browser and save them into this folder:" -ForegroundColor Yellow
  $failed | ForEach-Object { Write-Host "  $_" }
}
