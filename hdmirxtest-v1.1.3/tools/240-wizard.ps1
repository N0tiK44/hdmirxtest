param(
    [string]$PiHost = "192.168.20.35",
    [string]$PiUser = "visionseek",
    [string]$RemoteDir = "~/src/hdmirxtest",
    [string]$RepoUrl = ""
)

$ErrorActionPreference = "Stop"
$HostCycle = Join-Path $PSScriptRoot "host-cycle.ps1"

Write-Host ""
Write-Host "=== 1080p240 LAB WIZARD ===" -ForegroundColor Cyan
Write-Host "Step 1/2: back up RK-UHD and load the verified RK-1080P240 bridge EDID."
& powershell -NoProfile -ExecutionPolicy Bypass -File $HostCycle -Mode prepare240 -PiHost $PiHost -PiUser $PiUser -RemoteDir $RemoteDir -RepoUrl $RepoUrl
if ($LASTEXITCODE -ne 0) {
    throw "prepare240 failed. Check hdmirxtest-prepare240-latest.tar.gz. Use RUN-RESTORE-EDID.cmd if needed."
}

Write-Host ""
Write-Host "NOW CHANGE THE WINDOWS CPU/iGPU HDMI OUTPUT TO:" -ForegroundColor Yellow
Write-Host "    EXTEND THESE DISPLAYS"
Write-Host "    RK-1080P240: 1920 x 1080 @ 240 Hz"
Write-Host "Keep 8-bit SDR. Do not enable HDR, VRR, or a mode above 240 Hz."
Write-Host "If RK-1080P240 is not visible, disable/re-enable that display or replug the CPU/iGPU HDMI source cable."
Write-Host "Emergency rollback: double-click RUN-RESTORE-EDID.cmd."
Write-Host ""
Read-Host "Press ENTER only after the Zowie/test output is set to 1080p240"

Write-Host ""
Write-Host "Step 2/2: verify HDMI-RX really locked to ~240 fps, then run the full diagnostic if it did."
& powershell -NoProfile -ExecutionPolicy Bypass -File $HostCycle -Mode 240 -PiHost $PiHost -PiUser $PiUser -RemoteDir $RemoteDir -RepoUrl $RepoUrl
exit $LASTEXITCODE
