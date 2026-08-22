param(
    [ValidateSet('apk', 'appbundle')]
    [string]$Format = 'apk',
    [string]$FlutterRoot = $env:FLUTTER_ROOT,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$appRoot = Join-Path $projectRoot 'app'

if ([string]::IsNullOrWhiteSpace($FlutterRoot)) {
    $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
    if ($null -eq $flutterCommand) {
        throw 'FLUTTER_ROOT is not set and flutter is not available on PATH.'
    }
    $FlutterRoot = Split-Path -Parent (Split-Path -Parent $flutterCommand.Source)
}

$flutterBin = Join-Path $FlutterRoot 'bin\flutter.bat'
if (-not (Test-Path -LiteralPath $flutterBin -PathType Leaf)) {
    throw "Flutter executable not found at $flutterBin"
}
$env:FLUTTER_ROOT = $FlutterRoot

if (-not $SkipBuild) {
    Push-Location $appRoot
    try {
        if ($Format -eq 'apk') {
            & $flutterBin build apk --release --target-platform android-arm64 --no-pub
        } else {
            & $flutterBin build appbundle --release --target-platform android-arm64 --no-pub
        }
        if ($LASTEXITCODE -ne 0) {
            throw "Flutter Android $Format build failed with exit code $LASTEXITCODE."
        }
    } finally {
        Pop-Location
    }
}

if ($Format -eq 'apk') {
    $artifact = Join-Path $appRoot 'build\app\outputs\flutter-apk\app-release.apk'
} else {
    $artifact = Join-Path $appRoot 'build\app\outputs\bundle\release\app-release.aab'
}
if (-not (Test-Path -LiteralPath $artifact -PathType Leaf)) {
    throw "Android artifact not found at $artifact"
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($artifact)
try {
    $entries = @($archive.Entries | ForEach-Object FullName)
    $prefix = if ($Format -eq 'apk') { '' } else { 'base/' }
    $requiredCore = "${prefix}lib/arm64-v8a/libai_usage_core.so"
    if ($requiredCore -notin $entries) {
        throw "Release artifact is missing $requiredCore. Check FLUTTER_ROOT and Cargokit output."
    }

    $forbidden = @(
        "${prefix}assets/flutter_assets/kernel_blob.bin",
        "${prefix}lib/arm64-v8a/libVkLayer_khronos_validation.so"
    )
    foreach ($entry in $forbidden) {
        if ($entry -in $entries) {
            throw "Debug-only artifact found in release output: $entry"
        }
    }

    $unexpectedAbi = @(
        $entries |
            Where-Object { $_ -like "${prefix}lib/*/*.so" } |
            Where-Object { $_ -notlike "${prefix}lib/arm64-v8a/*" }
    )
    if ($unexpectedAbi.Count -gt 0) {
        throw "Unexpected native ABI entries: $($unexpectedAbi -join ', ')"
    }
} finally {
    $archive.Dispose()
}

$file = Get-Item -LiteralPath $artifact
$sizeMiB = $file.Length / 1MB
if ($Format -eq 'apk' -and $sizeMiB -gt 30) {
    throw ('arm64 Release APK is {0:N2} MiB, exceeding the 30 MiB gate.' -f $sizeMiB)
}

[pscustomobject]@{
    Artifact = $file.FullName
    Bytes = $file.Length
    MiB = [math]::Round($sizeMiB, 2)
    Format = $Format
    Abi = 'arm64-v8a'
    RustCore = $requiredCore
}
