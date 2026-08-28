# NovaOS one-command setup (Windows side).
#
#   Run AFTER rebooting Windows:
#       powershell -ExecutionPolicy Bypass -File .\setup.ps1
#
# This script:
#   1. Verifies WSL2 actually works (i.e. that the reboot happened)
#   2. Installs the Debian distro if it is not present
#   3. Installs build dependencies inside Debian
#   4. Copies this repo into the WSL Linux filesystem (NOT /mnt/c -- see below)
#   5. Runs the ISO build
#   6. Copies the finished ISO to C:\novaos-out (outside OneDrive, so it does
#      not sync a 1.5 GB file to the cloud)
#
# It is safe to re-run. Each step is skipped if already done.

$ErrorActionPreference = 'Stop'

$Distro   = 'Debian'
$RepoWin  = $PSScriptRoot
$RepoWsl  = '$HOME/novaos'
$OutDir   = 'C:\novaos-out'

function Info { param($m) Write-Host "==> $m" -ForegroundColor Cyan }
function Warn { param($m) Write-Host "[!] $m" -ForegroundColor Yellow }
function Die  { param($m) Write-Host "[x] $m" -ForegroundColor Red; exit 1 }

# --- Step 1: is WSL2 actually functional? ------------------------------------
Info 'Checking WSL2'

if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
    Die @'
Windows still has a reboot pending. WSL2 cannot start until you restart.

    Restart Windows, then run this script again.
'@
}

# `wsl --status` returns success even when broken, so probe for the specific
# virtualization failure text instead.
$status = (wsl.exe --status 2>&1 | Out-String) -replace "`0", ''
if ($status -match 'virtualization is not enabled') {
    Die @'
WSL2 reports that virtualization is not enabled.

If you have already rebooted, then AMD SVM is likely off in firmware:
  Restart -> press F2 or Del -> Advanced / CPU Configuration -> enable "SVM Mode"
  (on this Ryzen 5 5500U it is usually under Advanced > CPU Configuration)
'@
}

# --- Step 2: install the Debian distro ---------------------------------------
$installed = (wsl.exe --list --quiet 2>&1 | Out-String) -replace "`0", ''
if ($installed -notmatch [regex]::Escape($Distro)) {
    Info "Installing $Distro (this downloads ~500 MB)"
    Warn 'It will prompt for a UNIX username and password. Any values are fine -- note them down.'
    wsl.exe --install -d $Distro
    if ($LASTEXITCODE -ne 0) { Die "Failed to install $Distro" }
} else {
    Info "$Distro already installed"
}

# Confirm it actually runs.
$probe = (wsl.exe -d $Distro -- echo ok 2>&1 | Out-String).Trim()
if ($probe -notmatch 'ok') { Die "$Distro is installed but will not start. Output: $probe" }

# --- Step 3-6: hand off to the Linux side ------------------------------------
# Everything past this point must happen inside Linux. We convert the Windows
# repo path to its /mnt/... form and let the Linux bootstrap script drive.
$repoMnt = (wsl.exe -d $Distro -- wslpath -a "'$RepoWin'" 2>&1 | Out-String).Trim()
if (-not $repoMnt) { Die "Could not translate $RepoWin to a WSL path" }

Info "Repo visible to WSL at: $repoMnt"
Info 'Running Linux bootstrap (apt install, copy, build)'
Warn 'You will be asked for your Debian sudo password.'

wsl.exe -d $Distro --cd "$repoMnt" -- bash ./bootstrap.sh
if ($LASTEXITCODE -ne 0) { Die 'Linux bootstrap failed. Scroll up for the error.' }

# --- Collect the artifact ----------------------------------------------------
Info "Copying ISO to $OutDir"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$outMnt = (wsl.exe -d $Distro -- wslpath -a "'$OutDir'" 2>&1 | Out-String).Trim()
wsl.exe -d $Distro -- bash -lc "cp $RepoWsl/out/*.iso* '$outMnt'/"
if ($LASTEXITCODE -ne 0) { Die 'Build produced no ISO to copy.' }

Get-ChildItem $OutDir -Filter *.iso | ForEach-Object {
    Write-Host ''
    Write-Host "  ISO:  $($_.FullName)" -ForegroundColor Green
    Write-Host ("  Size: {0:N2} GB" -f ($_.Length / 1GB)) -ForegroundColor Green
}

Write-Host @'

Next: write it to a USB stick with Rufus or balenaEtcher in DD / image mode
(not ISO mode -- this is a hybrid image), then boot the target machine.

Remember: this Phase 1 image boots to a TEXT LOGIN. There is no desktop yet.
That is expected -- see docs/BUILD-PLAN.md.

'@ -f $null
