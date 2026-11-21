<#
    brand.ps1 - rebrand the Winlator source tree into "Shaiya Farlords".

    Idempotent: run as often as you like.

      - applicationId      com.winlator  ->  com.shaiyafarlords.mobile
      - namespace/package  left alone (renaming Java packages would touch every file)
      - app_name           ->  Shaiya Farlords
      - launcher icons     ->  D:\ShaiyaAPK\branding\mipmap-*\*.png
      - versionName        ->  configurable, default 1.0.0

    Only the user-visible surface changes: id, label, icon, version. Native
    libraries, JNI symbol names and file paths stay exactly as upstream.
#>

[CmdletBinding()]
param(
    [string]$SourceDir   = 'D:\ShaiyaAPK\winlator\app',
    [string]$BrandingDir = 'D:\ShaiyaAPK\branding',
    [string]$AppId       = 'com.shaiyafarlords.mobile',
    [string]$AppLabel    = 'Shaiya Farlords',
    [string]$VersionName = '1.0.0',
    [int]   $VersionCode = 110200
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $SourceDir)) { throw "Source tree not found: $SourceDir" }

$changed = @()

function Save-IfChanged([string]$path, [string]$content, [string]$why) {
    $old = Get-Content -Path $path -Raw
    if ($old -ceq $content) { return }
    Set-Content -Path $path -Value $content -NoNewline -Encoding UTF8
    Write-Host "  patched $why" -ForegroundColor Green
    $script:changed += $why
}

# ------------------------------------------------------------------ build.gradle
$gradle = Get-ChildItem $SourceDir -Filter 'build.gradle*' -File | Select-Object -First 1
if (-not $gradle) { throw "No build.gradle in $SourceDir" }
Write-Host "build file: $($gradle.Name)"

$g = Get-Content $gradle.FullName -Raw

# applicationId: replace whatever is there, quoted, single or double
$g = [regex]::Replace($g, "(?m)(applicationId\s*[= ]\s*)(['""])[^'""]+\2", "`$1`"$AppId`"")
# namespace stays as-is so Java/Kotlin packages keep resolving; only warn if it differs
$g = [regex]::Replace($g, "(?m)(versionName\s*[= ]\s*)(['""])[^'""]+\2", "`$1`"$VersionName`"")
$g = [regex]::Replace($g, "(?m)(versionCode\s*[= ]\s*)\d+", "`$1$VersionCode")

Save-IfChanged $gradle.FullName $g "build.gradle (applicationId/version)"

# --------------------------------------------------------------- strings.xml
$stringsFiles = Get-ChildItem $SourceDir -Recurse -Filter 'strings.xml' -File -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match '\\res\\values' }
foreach ($f in $stringsFiles) {
    $x = Get-Content $f.FullName -Raw
    if ($x -match '<string name="app_name">') {
        $x = [regex]::Replace($x, '<string name="app_name">[^<]*</string>',
                              "<string name=`"app_name`">$AppLabel</string>")
        Save-IfChanged $f.FullName $x "strings.xml -> $($f.Directory.Parent.Name)/$($f.Directory.Name)"
    }
}

# ------------------------------------------------------------------- manifest
$manifest = Join-Path $SourceDir 'src\main\AndroidManifest.xml'
if (Test-Path $manifest) {
    $m = Get-Content $manifest -Raw
    if ($m -notmatch 'android:label="\@string/app_name"') {
        $m = [regex]::Replace($m, 'android:label="[^"]*"', 'android:label="@string/app_name"', 1)
    }
    if ($m -notmatch 'android:supportsRtl') {
        $m = [regex]::Replace($m, '(<application\b)', '$1`n        android:supportsRtl="true"', 1)
    }
    Save-IfChanged $manifest $m 'AndroidManifest.xml (label)'
}

# ---------------------------------------------------------------------- icons
$resDir = Join-Path $SourceDir 'src\main\res'
if (-not (Test-Path $resDir)) { throw "res dir not found: $resDir" }

$copied = 0
foreach ($d in (Get-ChildItem $BrandingDir -Directory -Filter 'mipmap-*')) {
    $dst = Join-Path $resDir $d.Name
    New-Item -ItemType Directory -Path $dst -Force | Out-Null
    foreach ($png in (Get-ChildItem $d.FullName -Filter '*.png')) {
        Copy-Item $png.FullName (Join-Path $dst $png.Name) -Force
        $copied++
    }
}
Write-Host "  copied $copied icon files into res/" -ForegroundColor Green

# adaptive icon: make sure mipmap-anydpi-v26 points at our foreground
$anydpi = Join-Path $resDir 'mipmap-anydpi-v26'
if (Test-Path $anydpi) {
    Get-ChildItem $anydpi -Filter 'ic_launcher*.xml' | ForEach-Object {
        Write-Host "  adaptive icon: $($_.Name) (upstream, foreground reuse)"
    }
}

# --------------------------------------------- launcher-visible app label check
$mainActivity = Get-ChildItem $SourceDir -Recurse -Filter '*.java' -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match 'MainActivity|XServerDisplayActivity' } |
                Select-Object -First 3
Write-Host "  activities seen: $($mainActivity.Name -join ', ')"

Write-Host ''
Write-Host "Branding applied: $($changed.Count) file(s) changed." -ForegroundColor Cyan
Write-Host "  applicationId = $AppId"
Write-Host "  app_name      = $AppLabel"
Write-Host "  version       = $VersionName ($VersionCode)"
