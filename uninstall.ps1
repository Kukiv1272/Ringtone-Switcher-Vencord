$ErrorActionPreference = 'Stop'
$InstallDir = $null
$Common = Join-Path $PSScriptRoot 'installer-common.ps1'

function Fail($m) {
    Write-Host "`nERROR: $m`n" -ForegroundColor Red
    try { Read-Host 'Press Enter to close' } catch {}
    exit 1
}

if (-not (Test-Path -LiteralPath $Common -PathType Leaf)) { Fail 'installer-common.ps1 is missing. Extract the complete folder.' }
. $Common
$InstallDir = Resolve-RingtoneInstallDir

Write-Host '==============================================================' -ForegroundColor Magenta
Write-Host '   Ringtone Switcher - Vencord uninstaller' -ForegroundColor Magenta
Write-Host '==============================================================' -ForegroundColor Magenta
Write-Host ''
Write-Host 'Only RingtoneSwitcher will be removed. Other Vencord plugins will be preserved.' -ForegroundColor Yellow

$pluginDir = Join-Path $InstallDir 'src\userplugins\ringtoneSwitcher'
if (-not (Test-Path -LiteralPath $pluginDir -PathType Container)) {
    Write-Host 'RingtoneSwitcher is not installed in this Vencord checkout.' -ForegroundColor Yellow
    try { Read-Host 'Press Enter to close' } catch {}
    exit 0
}

$otherPlugins = @(Get-ChildItem -LiteralPath (Split-Path -Parent $pluginDir) -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne 'ringtoneSwitcher' } | Select-Object -ExpandProperty Name)
if ($otherPlugins.Count -gt 0) {
    Write-Host "Preserving plugins: $($otherPlugins -join ', ')" -ForegroundColor Cyan
}

$runningBefore = @(Get-RunningDiscordFlavors)
try { Stop-DiscordClients } catch { Fail $_.Exception.Message }

$backup = Join-Path ([IO.Path]::GetTempPath()) ("ringtone-switcher-uninstall-" + [guid]::NewGuid().ToString('N'))
try {
    Copy-Item -LiteralPath $pluginDir -Destination $backup -Recurse -Force
    Remove-Item -LiteralPath $pluginDir -Recurse -Force

    Write-Host 'Rebuilding Vencord without RingtoneSwitcher...' -ForegroundColor Cyan
    Invoke-Pnpm $InstallDir @('install')
    Invoke-Pnpm $InstallDir @('run','build')

    $target = Resolve-DiscordBranch @(Get-InstalledDiscordFlavors) $runningBefore $null
    Push-Location $InstallDir
    try { node scripts\runInstaller.mjs -- --install -branch $target } finally { Pop-Location }

    Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host 'RingtoneSwitcher removed. Other plugins were preserved.' -ForegroundColor Green
} catch {
    Write-Host "Uninstall failed: $($_.Exception.Message)" -ForegroundColor Red
    if (-not (Test-Path -LiteralPath $pluginDir) -and (Test-Path -LiteralPath $backup)) {
        Copy-Item -LiteralPath $backup -Destination $pluginDir -Recurse -Force
        Write-Host 'RingtoneSwitcher source was restored after the failed operation.' -ForegroundColor Yellow
    }
    try { Start-DiscordClients $runningBefore } catch {}
    try { Read-Host 'Press Enter to close' } catch {}
    exit 1
} finally {
    if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue }
}

try { Start-DiscordClients $runningBefore } catch {}
Write-Host ''
Write-Host "Vencord remains installed at: $InstallDir" -ForegroundColor DarkGray
Write-Host 'Node.js, Git and other userplugins were not removed.' -ForegroundColor DarkGray
try { Read-Host 'Press Enter to close' } catch {}
