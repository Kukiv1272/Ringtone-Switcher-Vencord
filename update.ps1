[CmdletBinding()]
param([switch]$SkipRestart)

$ErrorActionPreference = 'Stop'
$env:COREPACK_ENABLE_DOWNLOAD_PROMPT = '0'
$InstallDir = Join-Path $env:LOCALAPPDATA 'RingtoneSwitcherVencord'
$PluginRepoUrl = 'https://github.com/Kukiv1272/Ringtone-Switcher-Vencord.git'
$Common = Join-Path $PSScriptRoot 'installer-common.ps1'

function Info($m) { Write-Host $m -ForegroundColor Cyan }
function Good($m) { Write-Host $m -ForegroundColor Green }
function Warn($m) { Write-Host $m -ForegroundColor Yellow }
function Fail($m) {
    Write-Host "`nERROR: $m`n" -ForegroundColor Red
    try { Read-Host 'Press Enter to close' } catch {}
    exit 1
}
function Step([string]$Name, [scriptblock]$Action) {
    try { & $Action } catch { Fail "$Name failed: $($_.Exception.Message)" }
    if ($LASTEXITCODE -ne 0) { Fail "$Name failed with exit code $LASTEXITCODE." }
}

if (-not (Test-Path -LiteralPath $Common -PathType Leaf)) { Fail 'installer-common.ps1 is missing. Extract the complete folder.' }
. $Common
if (-not (Test-Path -LiteralPath (Join-Path $InstallDir '.git') -PathType Container)) {
    Fail "No Ringtone Switcher installation found at $InstallDir. Run INSTALL-autoupdate.cmd first."
}

Write-Host '==============================================================' -ForegroundColor Magenta
Write-Host '   Ringtone Switcher - Vencord updater' -ForegroundColor Magenta
Write-Host '==============================================================' -ForegroundColor Magenta
Write-Host ''

Info '[1/4] Updating Vencord source...'
Step 'Updating Vencord' {
    git -C $InstallDir pull --ff-only --quiet
    if ($LASTEXITCODE -ne 0) {
        Warn 'Fast-forward update failed; resetting the managed clone to origin/main.'
        git -C $InstallDir fetch --depth 1 --quiet origin main
        git -C $InstallDir reset --hard --quiet origin/main
    }
}

Info '[2/4] Updating the plugin source...'
$pluginCheckout = Join-Path $InstallDir '.ringtone-switcher-source'
if (Test-Path -LiteralPath (Join-Path $pluginCheckout '.git') -PathType Container) {
    Step 'Updating plugin source' {
        git -C $pluginCheckout pull --ff-only --quiet
        if ($LASTEXITCODE -ne 0) {
            git -C $pluginCheckout fetch --quiet origin main
            git -C $pluginCheckout reset --hard --quiet origin/main
        }
    }
} elseif (-not (Test-Path -LiteralPath $pluginCheckout)) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    git clone --depth 1 --quiet $PluginRepoUrl $pluginCheckout 2>&1 | Out-Null
    $cloneCode = $LASTEXITCODE
    $ErrorActionPreference = $previous
    if ($cloneCode -ne 0) { Warn 'Could not clone the plugin repository; using the bundled plugin copy.' }
}

$pluginSource = if (Test-Path -LiteralPath (Join-Path $pluginCheckout 'plugin\index.tsx')) { $pluginCheckout } else { $PSScriptRoot }
Step 'Copying plugin' { Copy-RingtonePlugin $pluginSource $InstallDir }

Info '[3/4] Installing dependencies and rebuilding...'
Step 'pnpm install' { Invoke-Pnpm $InstallDir @('install') }
Step 'Vencord build' { Invoke-Pnpm $InstallDir @('run','build') }
Good 'Build completed.'

if ($SkipRestart) {
    Warn '[4/4] Restart skipped by -SkipRestart.'
} else {
    Info '[4/4] Restarting Discord...'
    $running = @(Get-RunningDiscordFlavors)
    if ($running.Count -gt 0) {
        try { Stop-DiscordClients } catch { Fail $_.Exception.Message }
        Start-Sleep -Seconds 2
        Start-DiscordClients $running
        Good "Restarted: $($running -join ', ')"
    } else {
        Warn 'Discord was not running; it was left closed.'
    }
}

Write-Host ''
Good 'Ringtone Switcher was updated.'
try { Read-Host 'Press Enter to close' } catch {}
