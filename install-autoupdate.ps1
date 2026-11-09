[CmdletBinding()]
param(
    [switch]$SkipInject,
    [ValidateSet('stable','canary','ptb')][string]$DiscordBranch
)

$ErrorActionPreference = 'Stop'
$env:COREPACK_ENABLE_DOWNLOAD_PROMPT = '0'
$InstallDir = Join-Path $env:LOCALAPPDATA 'RingtoneSwitcherVencord'
$RepoUrl = 'https://github.com/Vendicated/Vencord.git'
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

Write-Host '==============================================================' -ForegroundColor Magenta
Write-Host '   Ringtone Switcher - Vencord auto-update installer' -ForegroundColor Magenta
Write-Host '==============================================================' -ForegroundColor Magenta
Write-Host ''
Write-Host "Vencord will be installed into: $InstallDir" -ForegroundColor Yellow
Write-Host 'The installer builds Vencord from source with Ringtone Switcher included.' -ForegroundColor Yellow
Write-Host ''

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail 'Git is required. Install Git for Windows and run this installer again.' }
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { Fail 'Node.js 22 or newer is required. Install Node.js and run this installer again.' }
$nodeMajor = [int]((node -v).TrimStart('v').Split('.')[0])
if ($nodeMajor -lt 22) { Fail "Node.js $nodeMajor detected. Vencord requires Node.js 22 or newer." }

$targetBranch = $null
if (-not $SkipInject) {
    try {
        $targetBranch = Resolve-DiscordBranch @(Get-InstalledDiscordFlavors) @(Get-RunningDiscordFlavors) $DiscordBranch
        Good "Target Discord: $targetBranch"
    } catch { Fail $_.Exception.Message }
}

Info '[1/5] Getting Vencord source...'
if (Test-Path -LiteralPath (Join-Path $InstallDir '.git') -PathType Container) {
    Step 'Updating Vencord source' {
        git -C $InstallDir pull --ff-only --quiet
        if ($LASTEXITCODE -ne 0) {
            git -C $InstallDir fetch --depth 1 --quiet origin main
            git -C $InstallDir reset --hard --quiet origin/main
        }
    }
} elseif (Test-Path -LiteralPath $InstallDir) {
    Fail "$InstallDir exists but is not a Git checkout. Move it aside and retry."
} else {
    Step 'Cloning Vencord' { git clone --depth 1 --quiet $RepoUrl $InstallDir }
}

Info '[2/5] Installing Ringtone Switcher source...'
Step 'Copying plugin' { Copy-RingtonePlugin $PSScriptRoot $InstallDir }

Push-Location $InstallDir
try {
    Info '[3/5] Installing dependencies...'
    Step 'pnpm install' { Invoke-Pnpm $InstallDir @('install') }
    Info '[4/5] Building Vencord with the plugin...'
    Step 'Vencord build' { Invoke-Pnpm $InstallDir @('run','build') }
} finally { Pop-Location }
Good 'Build completed.'

if ($SkipInject) {
    Warn "[5/5] Injection skipped. Build is ready at $InstallDir\dist."
} else {
    Info "[5/5] Patching Discord $targetBranch..."
    $runningBefore = @(Get-RunningDiscordFlavors)
    $reopen = @($runningBefore + $targetBranch | Select-Object -Unique)
    try { Stop-DiscordClients } catch { Fail $_.Exception.Message }
    Push-Location $InstallDir
    try { Step 'Discord injection' { node scripts\runInstaller.mjs -- --install -branch $targetBranch } }
    finally { Pop-Location }

    $asar = Get-CurrentAppAsar $targetBranch
    $patched = $false
    if ($asar) { $patched = Test-Patched $asar (Join-Path $InstallDir 'dist\patcher.js') }
    if (-not $patched) {
        Warn 'Injection could not be verified. Restoring Discord backup...'
        if (-not (Restore-AppAsar $asar (Join-Path $InstallDir 'dist\patcher.js'))) {
            Fail 'Injection failed and automatic rollback could not be verified. Run the official Vencord installer and choose Repair.'
        }
        Start-DiscordClients $reopen
        Fail 'Injection failed. Discord was restored.'
    }
    Good 'Discord patch verified.'
    Start-DiscordClients $reopen
}

Write-Host ''
Good 'Ringtone Switcher is installed.'
Write-Host 'Open Discord Settings -> Vencord -> Plugins and enable RingtoneSwitcher.' -ForegroundColor Cyan
Write-Host "Run UPDATE.cmd later to update Vencord and the plugin." -ForegroundColor DarkGray
Write-Host 'Run UNINSTALL.cmd to restore Discord and remove this installation.' -ForegroundColor DarkGray
try { Read-Host 'Press Enter to close' } catch {}
