$ErrorActionPreference = 'Continue'
$InstallDir = Join-Path $env:LOCALAPPDATA 'RingtoneSwitcherVencord'
$Common = Join-Path $PSScriptRoot 'installer-common.ps1'

function Fail($m) {
    Write-Host "`nERROR: $m`n" -ForegroundColor Red
    try { Read-Host 'Press Enter to close' } catch {}
    exit 1
}

if (-not (Test-Path -LiteralPath $Common -PathType Leaf)) { Fail 'installer-common.ps1 is missing. Extract the complete folder.' }
. $Common

Write-Host '==============================================================' -ForegroundColor Magenta
Write-Host '   Ringtone Switcher - Vencord uninstaller' -ForegroundColor Magenta
Write-Host '==============================================================' -ForegroundColor Magenta
Write-Host ''
Write-Host 'Discord will be closed while its original app.asar is restored.' -ForegroundColor Yellow

$runningBefore = @(Get-RunningDiscordFlavors)
try { Stop-DiscordClients } catch { Fail $_.Exception.Message }

$restored = 0
$failed = @()
$patcher = Join-Path $InstallDir 'dist\patcher.js'
foreach ($branch in @('stable','canary','ptb')) {
    $asar = Get-CurrentAppAsar $branch
    if (-not $asar) { continue }
    if (-not (Test-Patched $asar $patcher)) { continue }
    if (Restore-AppAsar $asar $patcher) { $restored++ } else { $failed += $branch }
}

if ($failed.Count -gt 0) {
    Write-Host "Could not safely restore: $($failed -join ', ')." -ForegroundColor Red
    Write-Host 'Discord was left closed. Run the official Vencord installer and choose Repair before reopening it.' -ForegroundColor Red
    try { Read-Host 'Press Enter to close' } catch {}
    exit 1
}

if ($restored -gt 0) {
    Write-Host "Discord restored. Recovered $restored installation(s)." -ForegroundColor Green
} else {
    Write-Host 'No Ringtone Switcher patch was found. Discord was already clean.' -ForegroundColor Green
}

$failedStart = @()
try { $failedStart = @(Start-DiscordClients $runningBefore) } catch { $failedStart = $runningBefore }
if ($failedStart.Count -gt 0) {
    Write-Host "Start these Discord clients manually: $($failedStart -join ', ')." -ForegroundColor Yellow
}

Write-Host ''
Write-Host "The managed Vencord folder can now be deleted manually: $InstallDir" -ForegroundColor DarkGray
Write-Host 'Node.js and Git were not removed.' -ForegroundColor DarkGray
try { Read-Host 'Press Enter to close' } catch {}
