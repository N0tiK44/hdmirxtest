param(
    [ValidateSet("baseline", "probe240", "prepare240", "240")]
    [string]$Mode = "baseline",
    [string]$PiHost = "192.168.20.35",
    [string]$PiUser = "visionseek",
    [ValidatePattern("^[A-Za-z0-9_./~\-]+$")]
    [string]$RemoteDir = "~/src/rk3588-hdmi-lowlatency",
    [string]$RepoUrl = "",
    [string]$Destination = ""
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($RepoUrl)) {
    try {
        $RepoUrl = (& git -C $RepoRoot remote get-url origin 2>$null).Trim()
    } catch {
        $RepoUrl = ""
    }
}

if ([string]::IsNullOrWhiteSpace($RepoUrl)) {
    throw "RepoUrl could not be detected. Clone the new GitHub repo on Windows first, or pass -RepoUrl https://github.com/USER/REPO.git"
}

if ([string]::IsNullOrWhiteSpace($Destination)) {
    $Destination = Join-Path $HOME "Downloads\hdmirx-latest.tar.gz"
}

$remote = "${PiUser}@${PiHost}"
$repoForShell = $RepoUrl.Replace("'", "'\"'\"'")
$dirForShell = $RemoteDir
$modeForShell = $Mode.Replace("'", "'\"'\"'")

$remoteCommand = @"
set -e
mkdir -p ~/src
if [ ! -d $dirForShell/.git ]; then
  echo 'First SBC checkout: cloning repository...'
  git clone '$repoForShell' $dirForShell
fi
cd $dirForShell
if ! command -v pkg-config >/dev/null 2>&1 || ! pkg-config --exists libdrm 2>/dev/null || ! command -v v4l2-ctl >/dev/null 2>&1; then
  echo 'First-run dependencies are missing; installing them now...'
  bash scripts/install-deps.sh
fi
bash scripts/pi-cycle.sh '$modeForShell'
"@

Write-Host ""
Write-Host "=== RK3588 HDMI LAB ===" -ForegroundColor Cyan
Write-Host "Mode: $Mode"
Write-Host "Pi:   $remote"
Write-Host "Repo: $RepoUrl"
Write-Host ""

# -t lets sudo request a password on the Pi when required.
& ssh -t $remote $remoteCommand
$remoteRc = $LASTEXITCODE

Write-Host ""
Write-Host "Fetching result archive (also attempted after a failed 240-Hz gate)..."
$source = "${remote}:~/hdmirx-latest.tar.gz"
& scp $source $Destination
$scpRc = $LASTEXITCODE

if ($scpRc -eq 0 -and (Test-Path -LiteralPath $Destination)) {
    Write-Host ""
    Write-Host "RESULT READY:" -ForegroundColor Green
    Get-Item -LiteralPath $Destination | Format-List FullName, Length, LastWriteTime
} else {
    throw "Could not fetch $source"
}

if ($remoteRc -ne 0) {
    Write-Warning "The Pi test returned exit code $remoteRc. This can be expected for probe240/240 when 1080p240 is not yet accepted. The archive was still fetched; send it back for review."
    exit $remoteRc
}
