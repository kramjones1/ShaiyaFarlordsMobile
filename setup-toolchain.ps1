<#
    setup-toolchain.ps1 - one-time Android build toolchain for the
    Shaiya Farlords app (Winlator fork, v11.2.0).

    Installs everything under D:\ShaiyaAPK (no admin, no PATH changes):
      toolchain\jdk            Temurin JDK 17
      toolchain\android-sdk    cmdline-tools + platform-tools + android-35
                               + build-tools 35.0.0 + NDK 24.0.8215888
                               + CMake 3.22.1
      winlator\                source (with submodules) at tag v11.2.0

    Re-runnable: existing pieces are skipped.
#>

[CmdletBinding()]
param(
    [string]$Root = 'D:\ShaiyaAPK'
)

$ErrorActionPreference = 'Continue'   # native tools write to stderr; Stop would kill the script
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is ~10x faster without it

$jdkDir  = Join-Path $Root 'toolchain\jdk'
$sdkDir  = Join-Path $Root 'toolchain\android-sdk'
$srcDir  = Join-Path $Root 'winlator'
$dlDir   = Join-Path $Root 'downloads'

function Say($m) { Write-Host "==> $m" -ForegroundColor Cyan }

New-Item -ItemType Directory -Path $Root, $dlDir -Force | Out-Null

# ------------------------------------------------------------------ JDK 17
if (-not (Test-Path (Join-Path $jdkDir 'bin\javac.exe'))) {
    Say 'Downloading JDK 17 (Temurin)'
    $zip = Join-Path $dlDir 'jdk17.zip'
    if (-not (Test-Path $zip)) {
        Invoke-WebRequest -Uri 'https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse' -OutFile $zip
    }
    Say "Extracting JDK ($([math]::Round((Get-Item $zip).Length/1MB)) MB)"
    $tmp = Join-Path $dlDir 'jdk_tmp'
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $inner = Get-ChildItem $tmp -Directory | Select-Object -First 1
    if (Test-Path $jdkDir) { Remove-Item $jdkDir -Recurse -Force }
    New-Item -ItemType Directory -Path (Split-Path $jdkDir -Parent) -Force | Out-Null
    Move-Item $inner.FullName $jdkDir
    Remove-Item $tmp -Recurse -Force
} else { Say 'JDK already installed' }

$env:JAVA_HOME = $jdkDir
$env:PATH = "$jdkDir\bin;$env:PATH"
if (-not (Test-Path (Join-Path $jdkDir 'bin\javac.exe'))) { throw "JDK install failed: $jdkDir" }
$javaVer = ((& "$jdkDir\bin\java.exe" -version 2>&1 | Out-String) -split "`r?`n")[0]
Say "java: $javaVer"

# ------------------------------------------------------------------ cmdline-tools
if (-not (Test-Path (Join-Path $sdkDir 'cmdline-tools\latest\bin\sdkmanager.bat'))) {
    Say 'Downloading Android cmdline-tools'
    $zip = Join-Path $dlDir 'cmdline-tools.zip'
    if (-not (Test-Path $zip)) {
        Invoke-WebRequest -Uri 'https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip' -OutFile $zip
    }
    $tmp = Join-Path $dlDir 'cmdtools_tmp'
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    New-Item -ItemType Directory -Path (Join-Path $sdkDir 'cmdline-tools') -Force | Out-Null
    $target = Join-Path $sdkDir 'cmdline-tools\latest'
    if (Test-Path $target) { Remove-Item $target -Recurse -Force }
    Move-Item (Join-Path $tmp 'cmdline-tools') $target
    Remove-Item $tmp -Recurse -Force
} else { Say 'cmdline-tools already installed' }

$env:ANDROID_HOME = $sdkDir
$env:ANDROID_SDK_ROOT = $sdkDir
$sdkmanager = Join-Path $sdkDir 'cmdline-tools\latest\bin\sdkmanager.bat'
if (-not (Test-Path $sdkmanager)) { throw "sdkmanager missing: $sdkmanager" }

# ------------------------------------------------------------------ SDK packages
Say 'Accepting SDK licences'
1..30 | ForEach-Object { 'y' } | & $sdkmanager --licenses 2>&1 | Out-Null

$packages = @(
    'platform-tools',
    'platforms;android-35',
    'build-tools;35.0.0',
    'ndk;24.0.8215888',
    'cmake;3.22.1'
)
Say "Installing SDK packages: $($packages -join ', ')"
& $sdkmanager @packages 2>&1 | Select-Object -Last 5

foreach ($p in @('platforms\android-35', 'build-tools\35.0.0', 'ndk\24.0.8215888', 'cmake\3.22.1')) {
    if (-not (Test-Path (Join-Path $sdkDir $p))) { Write-Host "    MISSING: $p" -ForegroundColor Red }
    else { Write-Host "    ok: $p" -ForegroundColor Green }
}

# ------------------------------------------------------------------ source
if (-not (Test-Path (Join-Path $srcDir '.git'))) {
    Say 'Cloning winlator v11.2.0 with submodules (this is the long one)'
    git clone --depth 1 --branch v11.2.0 --recurse-submodules --shallow-submodules `
        https://github.com/brunodev85/winlator $srcDir
} else { Say 'source already cloned' }

Say 'Updating submodules'
Push-Location $srcDir
git submodule update --init --recursive --depth 1 2>&1 | Select-Object -Last 10
Pop-Location

Say '--- toolchain summary ---'
$javaVer = ((& "$jdkDir\bin\java.exe" -version 2>&1 | Out-String) -split "`r?`n")[0]
"JDK    : $javaVer"
"SDK    : $sdkDir"
"NDK    : $(Test-Path (Join-Path $sdkDir 'ndk\24.0.8215888'))"
"CMake  : $(Test-Path (Join-Path $sdkDir 'cmake\3.22.1'))"
"Source : $srcDir"
Get-ChildItem $srcDir -Force | Select-Object Name | Format-Table -AutoSize
Say 'Toolchain ready.'
