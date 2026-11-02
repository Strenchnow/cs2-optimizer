# optimize_cs2.ps1
# Deep diagnostics and deep optimization for CS2 (Counter-Strike 2)

$ErrorActionPreference = 'Continue'

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "===== $Title =====" -ForegroundColor Cyan
}

function Write-OK {
    param([string]$Msg)
    Write-Host "  [OK]   $Msg" -ForegroundColor Green
}

function Write-Info {
    param([string]$Msg)
    Write-Host "  [INFO] $Msg" -ForegroundColor Gray
}

function Write-WARN {
    param([string]$Msg)
    Write-Host "  [WARN] $Msg" -ForegroundColor Yellow
}

function Write-ERR {
    param([string]$Msg)
    Write-Host "  [ERR]  $Msg" -ForegroundColor Red
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-WARN "Script is running without admin rights. Run PowerShell as administrator for HKLM and powercfg writes."
}

$gameProc = Get-Process -Name CounterStrike2 -ErrorAction SilentlyContinue
if ($gameProc) {
    Write-WARN "CS2 (CounterStrike2.exe) is running. It is recommended to close the game before clearing the cache."
}

Write-Section "1. Shader cache clearing (D3DSCache / NVIDIA / AMD / Intel)"

$shaderCachePaths = @(
    "$env:LOCALAPPDATA\D3DSCache",
    "$env:LOCALAPPDATA\NVIDIA\DXCache",
    "$env:LOCALAPPDATA\NVIDIA\ComputeCache",
    "$env:APPDATA\NVIDIA\ComputeCache",
    "$env:LOCALAPPDATA\AMD\DxCache",
    "$env:LOCALAPPDATA\Intel\DxCache"
)

foreach ($p in $shaderCachePaths) {
    if (Test-Path -LiteralPath $p) {
        try {
            Get-ChildItem -LiteralPath $p -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -Recurse -ErrorAction Stop }
            Write-OK "Cache cleared: $p"
        } catch {
            Write-ERR "Failed to clear cache: $p -- $($_.Exception.Message)"
        }
    } else {
        Write-Info "Folder not found (normal): $p"
    }
}

Write-Section "2. Windows responsiveness tweaks (network / power)"

try {
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name 'NetworkThrottlingIndex' -Value 4294967295 -Type DWord -Force -ErrorAction Stop
    Write-OK "NetworkThrottlingIndex = 0xFFFFFFFF"
} catch {
    Write-ERR "NetworkThrottlingIndex: $($_.Exception.Message)"
}

try {
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name 'SystemResponsiveness' -Value 0 -Type DWord -Force -ErrorAction Stop
    Write-OK "SystemResponsiveness = 0"
} catch {
    Write-ERR "SystemResponsiveness: $($_.Exception.Message)"
}

try {
    $powerOut = & powercfg -setactive SCHEME_HIGH_PERFORMANCE 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-OK "Power plan: 'High performance'"
    } else {
        Write-WARN "powercfg -setactive returned code $($LASTEXITCODE): $powerOut"
    }
} catch {
    Write-ERR "powercfg: $($_.Exception.Message)"
}

Write-Section "3. GameBar / background recording (DVR / Xbox GameBar) disabling"

try {
    Set-ItemProperty -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Value 0 -Type DWord -Force -ErrorAction Stop
    Write-OK "GameDVR_Enabled = 0 (HKCU:\System\GameConfigStore)"
} catch {
    Write-ERR "GameDVR_Enabled: $($_.Exception.Message)"
}

foreach ($policyPath in @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR', 'HKLM:\SOFTWARE\WOW6432Node\Policies\Microsoft\Windows\GameDVR')) {
    try {
        New-Item -Path $policyPath -Force -ErrorAction SilentlyContinue | Out-Null
        Set-ItemProperty -Path $policyPath -Name 'AllowGameDVR' -Value 0 -Type DWord -Force -ErrorAction Stop
        Write-OK "AllowGameDVR = 0 ($policyPath)"
    } catch {
        Write-ERR "AllowGameDVR: $($_.Exception.Message)"
    }
}

Write-Section "4. Steam / CS2 audit"

$steamPath = $null
try { $steamPath = (Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -Name 'SteamPath' -ErrorAction Stop).SteamPath } catch { }
if (-not $steamPath) { try { $steamPath = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -Name 'SteamPath' -ErrorAction SilentlyContinue).SteamPath } catch { } }
if (-not $steamPath -and (Test-Path -LiteralPath 'C:\Program Files (x86)\Steam')) { $steamPath = 'C:\Program Files (x86)\Steam' }
if (-not $steamPath -and (Test-Path -LiteralPath 'C:\Program Files\Steam')) { $steamPath = 'C:\Program Files\Steam' }

if ($steamPath -and (Test-Path -LiteralPath $steamPath)) { Write-OK "Steam path: $steamPath" } else { Write-WARN "Steam path not found." }

$cs2GameDir = $null
if ($steamPath -and (Test-Path -LiteralPath $steamPath)) {
    $commonDir = Join-Path -Path $steamPath -ChildPath 'steamapps\common'
    if (Test-Path -LiteralPath $commonDir) {
        $manifests = Get-ChildItem -LiteralPath $commonDir -Filter 'appmanifest_*.acf' -ErrorAction SilentlyContinue
        foreach ($m in $manifests) {
            $content = Get-Content -LiteralPath $m.FullName -Raw -ErrorAction SilentlyContinue
            if ($content -match '"name"\s*:\s*"([^"]+)"' -and $content -match '"installdir"\s*:\s*"([^"]+)"') {
                $gameName = $Matches[1]
                $installDir = $Matches[2]
                Write-Host "  App: $gameName -> $installDir"
                if ($gameName -like '*Counter-Strike 2*') { $cs2GameDir = Join-Path -Path $commonDir -ChildPath $installDir }
            }
        }
    }
}

if ($cs2GameDir -and (Test-Path -LiteralPath $cs2GameDir)) {
    Write-OK "CS2 folder: $cs2GameDir"
} else {
    Write-WARN "CS2 folder (game\csgo) was not found automatically."
    $cs2GameDirCandidates = @(
        'D:\Steam\steamapps\common\Counter-Strike Global Offensive\game',
        'D:\Steam\steamapps\common\Counter-Strike 2\game'
    )
    foreach ($cd in $cs2GameDirCandidates) {
        if (Test-Path -LiteralPath $cd) { $cs2GameDir = $cd; break }
    }
}

if ($cs2GameDir -and (Test-Path -LiteralPath $cs2GameDir)) {
    $autoexec = Join-Path -Path $cs2GameDir -ChildPath 'autoexec.cfg'
    if (Test-Path -LiteralPath $autoexec) {
        Write-Host "  autoexec.cfg found:" -ForegroundColor White
        Get-Content -LiteralPath $autoexec | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith(';') -and -not $_.StartsWith('#') } | ForEach-Object { Write-Host "    $_" }
    } else {
        Write-WARN "autoexec.cfg not found: $autoexec"
    }
}

$dumpRoots = @()
if ($cs2GameDir) { $dumpRoots += @($cs2GameDir, (Join-Path -Path $cs2GameDir -ChildPath '..')) }
if ($steamPath) {
    $dumpRoots += @(Join-Path -Path $steamPath -ChildPath 'steamapps\common')
    $dumpRoots += @(Join-Path -Path $steamPath -ChildPath 'steamapps')
}
$dumpRoots += @($env:LOCALAPPDATA)

$dumpFiles = @()
foreach ($root in $dumpRoots) {
    if (Test-Path -LiteralPath $root) {
        $dumpFiles += @(Get-ChildItem -LiteralPath $root -Filter 'cs2_*.dmp' -ErrorAction SilentlyContinue -Recurse)
    }
}

$dumpFiles = @($dumpFiles | Where-Object { $_ })

if ($dumpFiles.Count -eq 0) {
    Write-OK "No temporary cs2_*.dmp crash dumps found."
} else {
    foreach ($f in $dumpFiles) {
        try {
            Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
            Write-OK "Crash dump removed: $($f.FullName)"
        } catch {
            Write-ERR "Failed to remove crash dump: $($f.FullName) -- $($_.Exception.Message)"
        }
    }
}

if ($steamPath) {
    $workshopCache = Join-Path -Path $steamPath -ChildPath 'steamapps\workshop'
    if (Test-Path -LiteralPath $workshopCache) {
        try {
            Get-ChildItem -LiteralPath $workshopCache -Recurse -ErrorAction SilentlyContinue | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -Recurse -ErrorAction Stop }
            Write-OK "Workshop cache cleared: $workshopCache"
        } catch {
            Write-ERR "Failed to clear workshop cache: $workshopCache -- $($_.Exception.Message)"
        }
    }
}

$launchOptions = $null
try { $launchOptions = (Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam\Apps\730' -Name 'LaunchOptions' -ErrorAction SilentlyContinue).LaunchOptions } catch { }
if ($launchOptions) { Write-Host "  Steam launch options (CS2, AppID 730): $launchOptions" } else { Write-WARN "Steam launch options for CS2 not found (or not set)." }

Write-Section "5. Manual settings (cannot be changed programmatically)"

Write-Host "  NVIDIA Reflex: cannot be changed by script. Enable it via CS2 in-game settings (Performance / Reflex) or NVIDIA Control Panel (Low Latency Mode / Reflex). Requires supported GPU."
Write-Host "  Fullscreen mode: Exclusive Fullscreen is recommended. Switched via game, NVIDIA Control Panel or monitor settings; cannot be set by script."
Write-Host "  Steam launch options: remove outdated / harmful flags not supported by CS2: -threads*, -high, -useallavailablecores."
Write-Host "  Additional: update GPU drivers; enable VSync only if needed."

Write-Host ""
Write-Host "===== SCRIPT FINISHED =====" -ForegroundColor Green
Write-Host "  Start the game after clearing the shader cache (the cache will be rebuilt)."
Write-Host "  Restart the computer after applying network / power tweaks."
