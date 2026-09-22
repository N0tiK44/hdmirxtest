param(
    [string]$PiHost = "192.168.20.35",
    [string]$PiUser = "visionseek",
    [string]$RemoteDir = "~/src/rk3588-hdmi-lowlatency",
    [string]$RepoUrl = ""
)

$ErrorActionPreference = "Stop"
$HostCycle = Join-Path $PSScriptRoot "host-cycle.ps1"

Write-Host ""
Write-Host "=== 1080p240 LAB WIZARD ===" -ForegroundColor Cyan
Write-Host "Step 1/2: back up the RX EDID and forward the connected Zowie EDID."
& powershell -NoProfile -ExecutionPolicy Bypass -File $HostCycle -Mode prepare240 -PiHost $PiHost -PiUser $PiUser -RemoteDir $RemoteDir -RepoUrl $RepoUrl
if ($LASTEXITCODE -ne 0) {
    throw "prepare240 failed. Check the downloaded hdmirx-latest.tar.gz before continuing."
}

Write-Host ""
Write-Host "NOW CHANGE THE WINDOWS CPU/iGPU HDMI OUTPUT TO:" -ForegroundColor Yellow
Write-Host "    1920 x 1080 @ 240 Hz (or the closest ~239.7/239.8 Hz mode)"
Write-Host "Do not choose a refresh rate above 240 Hz."
Write-Host "If Windows did not refresh the mode list, disable/re-enable that display or replug the HDMI source cable."
Write-Host ""
Read-Host "Press ENTER only after the Zowie/test output is set to 1080p240"

Write-Host ""
Write-Host "Step 2/2: verify HDMI-RX really locked to ~240 fps, then run the full diagnostic if it did."
& powershell -NoProfile -ExecutionPolicy Bypass -File $HostCycle -Mode 240 -PiHost $PiHost -PiUser $PiUser -RemoteDir $RemoteDir -RepoUrl $RepoUrl
exit $LASTEXITCODE
