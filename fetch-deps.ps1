<#
    fetch-deps.ps1 - resumable, retry-hardened fetch of everything the APK build
    needs that the connection keeps dropping.

      1. Android NDK r24 (663 MB)   -> sdk\ndk\24.0.8215888
      2. platforms;android-35 + build-tools;35.0.0 + platform-tools  (sdkmanager)
      3. winlator submodules: app, gladio, vortek (+ their own submodules)

    Every step is idempotent: re-running this script resumes/finishes, never
    restarts from zero. Safe to interrupt at any point.
#>

[CmdletBinding()]
param(
    [int]$MaxAttempts = 40,
    [string]$Root      = 'D:\ShaiyaAPK'
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

$sdkDir  = Join-Path $Root 'toolchain\android-sdk'
$dlDir   = Join-Path $Root 'downloads'
$srcDir  = Join-Path $Root 'winlator'
$tmpRoot = Join-Path $Root 'src-tmp'
$logFile = Join-Path $Root 'fetch-log.txt'

New-Item -ItemType Directory -Path $dlDir -Force | Out-Null
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null

# ---- sdkmanager dies instantly without a valid JAVA_HOME -------------------
$jdkDir = (Get-ChildItem (Join-Path $Root 'toolchain') -Directory -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -like 'jdk*' } | Select-Object -First 1).FullName
if (-not $jdkDir -or -not (Test-Path (Join-Path $jdkDir 'bin\javac.exe'))) {
    throw "No JDK found under $Root\toolchain - run setup-toolchain.ps1 first"
}
$env:JAVA_HOME = $jdkDir
$env:PATH      = "$jdkDir\bin;$env:PATH"

function Say([string]$msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $msg
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

function Find-7z {
    foreach ($p in @('C:\Program Files\7-Zip\7z.exe', 'C:\Program Files (x86)\7-Zip\7z.exe')) {
        if (Test-Path $p) { return $p }
    }
    $c = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    return $null
}
$sevenZip = Find-7z

# ---------------------------------------------------------------- robust fetch
# curl handles resume + its own retries; the outer loop covers hard drops where
# curl exits non-zero, and re-invokes with -C - so nothing already on disk is lost.
function Fetch([string]$url, [string]$outFile, [long]$expectedSize = 0) {
    for ($i = 1; $i -le $MaxAttempts; $i++) {
        if ($expectedSize -gt 0 -and (Test-Path $outFile)) {
            if ((Get-Item $outFile).Length -eq $expectedSize) {
                Say ("    already complete: {0:N1} MB" -f ($expectedSize / 1MB))
                return $true
            }
        }

        $have = if (Test-Path $outFile) { (Get-Item $outFile).Length } else { 0 }
        Say ("    attempt {0}: {1:N1} MB on disk, resuming" -f $i, ($have / 1MB))

        & curl.exe -L -C - --fail --retry 10 --retry-delay 3 --retry-all-errors `
                   --connect-timeout 20 --speed-limit 2048 --speed-time 120 `
                   -o $outFile $url 2>&1 | Out-Null

        $now = if (Test-Path $outFile) { (Get-Item $outFile).Length } else { 0 }
        if ($expectedSize -gt 0) {
            if ($now -eq $expectedSize) {
                Say ("    complete: {0:N1} MB" -f ($now / 1MB))
                return $true
            }
            Say ("    partial: {0:N1} / {1:N1} MB" -f ($now / 1MB), ($expectedSize / 1MB))
            # a server that ignores Range can leave us stuck; restart only if no progress
            if ($now -eq $have -and $now -gt 0) {
                Say '    no progress - restarting file'
                Remove-Item $outFile -Force -ErrorAction SilentlyContinue
            }
        }
        else {
            if ($now -gt 0 -and $now -eq $have) { Remove-Item $outFile -Force -ErrorAction SilentlyContinue }
        }
        Start-Sleep -Seconds (3 * [Math]::Min($i, 5))
    }
    Say '    FAILED after all attempts'
    return $false
}

# ------------------------------------------------------------------- 1. the NDK
Say '=== 1/3  Android NDK r24.0.8215888 ==='
$ndkZip  = Join-Path $dlDir 'android-ndk-r24-windows.zip'
$ndkSize = 663076813
$ndkDest = Join-Path $sdkDir 'ndk\24.0.8215888'

if ((Test-Path $ndkDest) -and (Get-ChildItem $ndkDest -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object).Count -gt 100) {
    Say '  NDK already extracted'
}
else {
    $ok = Fetch 'https://dl.google.com/android/repository/android-ndk-r24-windows.zip' $ndkZip $ndkSize
    if ($ok) {
        Say '  extracting NDK'
        $tmp = Join-Path $dlDir 'ndk-extract'
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null

        if ($sevenZip) { & $sevenZip x $ndkZip "-o$tmp" -y 2>&1 | Select-Object -Last 2 | Out-Null }
        else { Expand-Archive -Path $ndkZip -DestinationPath $tmp -Force }

        $inner = Get-ChildItem $tmp -Directory | Select-Object -First 1
        if ($inner) {
            New-Item -ItemType Directory -Path (Split-Path $ndkDest -Parent) -Force | Out-Null
            Remove-Item $ndkDest -Recurse -Force -ErrorAction SilentlyContinue
            Move-Item $inner.FullName $ndkDest
            $n = (Get-ChildItem $ndkDest -Recurse -File -Force | Measure-Object).Count
            Say "  NDK extracted: $n files"
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $ndkZip -Force -ErrorAction SilentlyContinue
        }
        else { Say '  NDK extract failed (no inner dir)' }
    }
}

# --------------------------------------------------- 2. platform-35/build-tools
Say '=== 2/3  platforms;android-35 + build-tools;35.0.0 + platform-tools ==='
$sdkmanager = Join-Path $sdkDir 'cmdline-tools\latest\bin\sdkmanager.bat'
$needs = @()
foreach ($p in @(@{id = 'platform-tools';          dir = 'platform-tools' },
                 @{id = 'platforms;android-35';    dir = 'platforms\android-35' },
                 @{id = 'build-tools;35.0.0';      dir = 'build-tools\35.0.0' })) {
    if (-not (Test-Path (Join-Path $sdkDir $p.dir))) { $needs += $p.id }
}

if ($needs.Count -eq 0) { Say '  already installed' }
else {
    Say ("  installing: {0}" -f ($needs -join ', '))
    Say ("  JAVA_HOME = {0}" -f $env:JAVA_HOME)
    $env:ANDROID_HOME     = $sdkDir
    $env:ANDROID_SDK_ROOT = $sdkDir
    for ($i = 1; $i -le 15; $i++) {
        Say "    sdkmanager attempt $i"
        & $sdkmanager @needs 2>&1 | Out-Null
        $missing = @($needs | Where-Object {
            $d = ($_ -replace '^platforms;', 'platforms\') -replace '^build-tools;', 'build-tools\'
            -not (Test-Path (Join-Path $sdkDir $d))
        })
        if ($missing.Count -eq 0) { Say '    all installed'; break }
        Say ("    still missing: {0}" -f ($missing -join ', '))
        Start-Sleep -Seconds (5 * $i)
    }
}

# --------------------------------------------------------- 3. winlator sources
Say '=== 3/3  winlator source trees ==='
$subs = @(
    @{ path = 'app';    url = 'https://github.com/brunodev85/winlator-app'; branch = 'main' },
    @{ path = 'gladio'; url = 'https://github.com/brunodev85/gladio';        branch = 'main' },
    @{ path = 'vortek'; url = 'https://github.com/brunodev85/vortek';        branch = 'main' }
)

foreach ($s in $subs) {
    $dest    = Join-Path $srcDir $s.path
    $staging = Join-Path $tmpRoot $s.path

    $count = 0
    if (Test-Path $dest) {
        $count = (Get-ChildItem $dest -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object).Count
    }
    if ($count -gt 10) { Say ("  {0}: already present ({1} files)" -f $s.path, $count); continue }

    # A submodule path cannot be cloned directly: git expects .git\modules\<name>
    # in the parent to already exist and aborts with "remote did not send all
    # necessary objects". Clone to a scratch path outside the superproject, then
    # move the tree into place.
    $done = $false
    for ($i = 1; $i -le 12; $i++) {
        Say ("  {0}: clone attempt {1}" -f $s.path, $i)
        Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
        $env:GIT_TERMINAL_PROMPT = '0'
        & git -c http.lowSpeedLimit=2000 -c http.lowSpeedTime=120 `
              clone --depth 1 --branch $s.branch $s.url $staging 2>&1 | Out-Null

        $got = (Get-ChildItem $staging -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object).Count
        if ($got -gt 10) {
            Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue
            # stale submodule gitdir pointer from the failed earlier attempts
            Remove-Item (Join-Path $srcDir ".git\modules\$($s.path)") -Recurse -Force -ErrorAction SilentlyContinue
            Move-Item $staging $dest
            Say ("    ok: {0} files" -f $got)
            $done = $true
            break
        }

        # fallback: tarball straight from codeload (no git metadata needed)
        if ($i -ge 4) {
            Say '    git failing - trying codeload tarball'
            $tgz = Join-Path $tmpRoot "$($s.path).tgz"
            & curl.exe -L --fail --retry 5 --retry-all-errors --retry-delay 3 `
                       --connect-timeout 20 --speed-limit 1024 --speed-time 120 `
                       -o $tgz ("https://codeload.github.com/brunodev85/{0}/tar.gz/refs/heads/{1}" -f `
                                ($s.url -replace '.*/',''), $s.branch) 2>&1 | Out-Null
            if ((Test-Path $tgz) -and (Get-Item $tgz).Length -gt 1MB) {
                $ex = Join-Path $tmpRoot "$($s.path)-ex"
                Remove-Item $ex -Recurse -Force -ErrorAction SilentlyContinue
                New-Item -ItemType Directory -Path $ex -Force | Out-Null
                & tar.exe -xzf $tgz -C $ex 2>&1 | Out-Null
                $inner = Get-ChildItem $ex -Directory | Select-Object -First 1
                if ($inner) {
                    Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue
                    Move-Item $inner.FullName $dest
                    Remove-Item $staging, $tgz, $ex -Recurse -Force -ErrorAction SilentlyContinue
                    Say ("    ok (tarball): {0} files" -f (Get-ChildItem $dest -Recurse -File -Force | Measure-Object).Count)
                    $done = $true
                    break
                }
            }
        }
        Say '    failed, retrying'
        Start-Sleep -Seconds (5 * $i)
    }
    if (-not $done) { Say ("  {0}: GAVE UP" -f $s.path) }
}

Say '  resolving nested submodules inside app/gladio/vortek'
foreach ($d in @('app', 'gladio', 'vortek')) {
    $dir = Join-Path $srcDir $d
    if (-not (Test-Path (Join-Path $dir '.gitmodules'))) { continue }
    for ($i = 1; $i -le 8; $i++) {
        Say ("    {0}: nested submodule attempt {1}" -f $d, $i)
        Push-Location $dir
        & git submodule update --init --recursive --depth 1 2>&1 | Out-Null
        Pop-Location
        $empty = & git -C $dir submodule status 2>$null | Select-String -Pattern '^-'
        if (-not $empty) { Say ("    {0}: nested submodules present" -f $d); break }
        Start-Sleep -Seconds (5 * $i)
    }
}

# ---------------------------------------------------------------------- report
Say '=== summary ==='
foreach ($p in @('platform-tools', 'platforms\android-35', 'build-tools\35.0.0', 'ndk\24.0.8215888', 'cmake\3.22.1')) {
    $full = Join-Path $sdkDir $p
    if (Test-Path $full) {
        $m = Get-ChildItem $full -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum
        Say ("  ok  {0,-24} {1,7:N1} MB  {2} files" -f $p, ($m.Sum / 1MB), $m.Count)
    }
    else { Say ("  MISSING  {0}" -f $p) }
}
foreach ($d in @('app', 'gladio', 'vortek')) {
    $m = Get-ChildItem (Join-Path $srcDir $d) -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum
    Say ("  src {0,-8} {1,7:N1} MB  {2} files" -f $d, ($m.Sum / 1MB), $m.Count)
}
Say 'Done.'
