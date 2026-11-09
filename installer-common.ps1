# Shared lifecycle helpers for the Ringtone Switcher installer.

$script:DiscordFlavors = [ordered]@{
    stable = [pscustomobject]@{ Branch = 'stable'; Directory = 'Discord'; Process = 'Discord' }
    canary = [pscustomobject]@{ Branch = 'canary'; Directory = 'DiscordCanary'; Process = 'DiscordCanary' }
    ptb    = [pscustomobject]@{ Branch = 'ptb'; Directory = 'DiscordPTB'; Process = 'DiscordPTB' }
}

function Get-DiscordInfo([string]$Branch) {
    $key = $Branch.ToLowerInvariant()
    if (-not $script:DiscordFlavors.Contains($key)) { throw "Unsupported Discord branch '$Branch'. Use stable, canary, or ptb." }
    $script:DiscordFlavors[$key]
}

function Get-DiscordRoot([string]$Branch) {
    Join-Path $env:LOCALAPPDATA (Get-DiscordInfo $Branch).Directory
}

function Resolve-RingtoneInstallDir {
    param([string]$PreferredPath)

    $candidates = @()
    if ($PreferredPath) { $candidates += $PreferredPath }
    if ($env:VENCORD_INSTALL_DIR) { $candidates += $env:VENCORD_INSTALL_DIR }
    $candidates += (Join-Path $env:LOCALAPPDATA 'OrionVencord')
    $candidates += (Join-Path $env:LOCALAPPDATA 'RingtoneSwitcherVencord')

    foreach ($candidate in $candidates) {
        if ((Test-Path -LiteralPath (Join-Path $candidate '.git') -PathType Container) -and
            (Test-Path -LiteralPath (Join-Path $candidate 'package.json') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $candidate 'src') -PathType Container)) {
            return $candidate
        }
    }

    return (Join-Path $env:LOCALAPPDATA 'RingtoneSwitcherVencord')
}

function Select-DiscordResources([string]$Root) {
    $apps = @(Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -like 'app-*' -and
            (Test-Path -LiteralPath (Join-Path $_.FullName 'resources') -PathType Container)
        } | Sort-Object Name)
    if ($apps.Count -eq 0) { return $null }
    Join-Path $apps[-1].FullName 'resources'
}

function Get-InstalledDiscordFlavors {
    foreach ($branch in $script:DiscordFlavors.Keys) {
        $root = Get-DiscordRoot $branch
        if ((Test-Path -LiteralPath (Join-Path $root 'Update.exe') -PathType Leaf) -and (Select-DiscordResources $root)) { $branch }
    }
}

function Get-RunningDiscordFlavors {
    foreach ($branch in $script:DiscordFlavors.Keys) {
        if (Get-Process -Name (Get-DiscordInfo $branch).Process -ErrorAction SilentlyContinue | Select-Object -First 1) { $branch }
    }
}

function Resolve-DiscordBranch([string[]]$Installed, [string[]]$Running, [string]$Preferred) {
    $installedSet = @($Installed | Where-Object { $_ } | Select-Object -Unique)
    $runningSet = @($Running | Where-Object { $_ -in $installedSet } | Select-Object -Unique)
    if ($Preferred) {
        if ($Preferred -notin $installedSet) { throw "Discord $Preferred is not installed or could not be located." }
        return $Preferred
    }
    if ($runningSet.Count -eq 1) { return $runningSet[0] }
    if ($runningSet.Count -gt 1) { throw "More than one Discord flavor is running: $($runningSet -join ', ')." }
    if ($installedSet.Count -eq 1) { return $installedSet[0] }
    if ($installedSet.Count -eq 0) { throw 'No supported Discord installation was found.' }
    throw "More than one Discord flavor is installed. Run with -DiscordBranch stable, canary, or ptb."
}

function Stop-DiscordClients {
    Get-Process Discord,DiscordCanary,DiscordPTB,DiscordSystemHelper -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $deadline = (Get-Date).AddSeconds(20)
    while ((Get-Date) -lt $deadline) {
        if (@(Get-Process Discord,DiscordCanary,DiscordPTB,DiscordSystemHelper -ErrorAction SilentlyContinue).Count -eq 0) { return }
        Start-Sleep -Milliseconds 500
    }
    throw 'Discord did not close within 20 seconds. Close it manually and try again.'
}

function Start-DiscordClients([string[]]$Branches) {
    foreach ($branch in @($Branches | Select-Object -Unique)) {
        $info = Get-DiscordInfo $branch
        $update = Join-Path (Get-DiscordRoot $branch) 'Update.exe'
        if (Test-Path -LiteralPath $update -PathType Leaf) { Start-Process $update -ArgumentList '--processStart', "$($info.Process).exe" }
    }
}

function Get-PnpmCommand([string]$InstallDir) {
    $package = Get-Content -LiteralPath (Join-Path $InstallDir 'package.json') -Raw | ConvertFrom-Json
    if ($package.packageManager -match '^pnpm@([^+\s]+)') { $version = $Matches[1] } else { throw 'Vencord package.json does not declare a pnpm version.' }
    if (Get-Command corepack -ErrorAction SilentlyContinue) { return @('corepack','pnpm') }
    if (Get-Command npx -ErrorAction SilentlyContinue) { return @('npx','--yes',"pnpm@$version") }
    throw 'Node.js with Corepack or npx is required.'
}

function Invoke-Pnpm([string]$InstallDir, [string[]]$Arguments) {
    $command = Get-PnpmCommand $InstallDir
    Push-Location $InstallDir
    try { & $command[0] @($command[1..($command.Count - 1)] + $Arguments) } finally { Pop-Location }
    if ($LASTEXITCODE -ne 0) { throw "pnpm command failed with exit code $LASTEXITCODE." }
}

function Copy-RingtonePlugin([string]$SourceDir, [string]$InstallDir) {
    $source = if (Test-Path -LiteralPath (Join-Path $SourceDir 'plugin\index.tsx')) { Join-Path $SourceDir 'plugin' } else { $SourceDir }
    foreach ($file in @('index.tsx','ringtones.ts')) {
        if (-not (Test-Path -LiteralPath (Join-Path $source $file) -PathType Leaf)) { throw "Plugin file '$file' is missing." }
    }
    $dest = Join-Path $InstallDir 'src\userplugins\ringtoneSwitcher'
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $source 'index.tsx'),(Join-Path $source 'ringtones.ts') -Destination $dest -Force
}

function Test-Patched([string]$AppAsar, [string]$PatcherPath) {
    if (-not (Test-Path -LiteralPath $AppAsar -PathType Leaf)) { return $false }
    try {
        $text = [IO.File]::ReadAllText($AppAsar)
        $needle = '"' + ([IO.Path]::GetFullPath($PatcherPath)).Replace('\','\\') + '"'
        return $text.IndexOf($needle, [StringComparison]::OrdinalIgnoreCase) -ge 0
    } catch { return $false }
}

function Restore-AppAsar([string]$AppAsar, [string]$PatcherPath) {
    $backup = Join-Path (Split-Path -Parent $AppAsar) '_app.asar'
    if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) { return $false }
    $temporary = "$AppAsar.ringtone-rollback-$([guid]::NewGuid().ToString('N'))"
    try {
        if (Test-Path -LiteralPath $AppAsar -PathType Leaf) {
            Move-Item -LiteralPath $AppAsar -Destination $temporary -Force
        }
        Move-Item -LiteralPath $backup -Destination $AppAsar -Force
        if (Test-Path -LiteralPath $temporary -PathType Leaf) {
            Remove-Item -LiteralPath $temporary -Force
        }
        return -not (Test-Patched $AppAsar $PatcherPath)
    } catch {
        if ((Test-Path -LiteralPath $temporary -PathType Leaf) -and -not (Test-Path -LiteralPath $AppAsar -PathType Leaf)) {
            Move-Item -LiteralPath $temporary -Destination $AppAsar -Force -ErrorAction SilentlyContinue
        }
        return $false
    }
}

function Get-CurrentAppAsar([string]$Branch) {
    $resources = Select-DiscordResources (Get-DiscordRoot $Branch)
    if ($resources) { Join-Path $resources 'app.asar' }
}
