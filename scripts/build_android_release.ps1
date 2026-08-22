param(
    [ValidateSet('apk', 'appbundle')]
    [string]$Format = 'apk',
    [string]$FlutterRoot = $env:FLUTTER_ROOT,
    [string]$ExpectedCertSha256 = $env:AIUSAGE_ANDROID_CERT_SHA256,
    [switch]$RequireSignature,
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

$flutterExecutable = if ($IsWindows) { 'flutter.bat' } else { 'flutter' }
$flutterBin = Join-Path (Join-Path $FlutterRoot 'bin') $flutterExecutable
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

$certificateSha256 = $null
if ($RequireSignature) {
    if ([string]::IsNullOrWhiteSpace($ExpectedCertSha256)) {
        throw 'Expected certificate SHA-256 is required for signature verification.'
    }

    if ($Format -eq 'apk') {
        $androidSdkRoot = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } else { $env:ANDROID_HOME }
        if ([string]::IsNullOrWhiteSpace($androidSdkRoot)) {
            $localProperties = Join-Path $appRoot 'android\local.properties'
            if (Test-Path -LiteralPath $localProperties -PathType Leaf) {
                $sdkProperty =
                    Get-Content -LiteralPath $localProperties |
                        Where-Object { $_ -match '^sdk\.dir=' } |
                        Select-Object -First 1
                if ($sdkProperty) {
                    $androidSdkRoot = ($sdkProperty -replace '^sdk\.dir=', '') -replace '\\\\', '\'
                }
            }
        }
        if ([string]::IsNullOrWhiteSpace($androidSdkRoot)) {
            throw 'ANDROID_SDK_ROOT or ANDROID_HOME is required to locate apksigner.'
        }
        $apksignerName = if ($IsWindows) { 'apksigner.bat' } else { 'apksigner' }
        $apksigner =
            Get-ChildItem -LiteralPath (Join-Path $androidSdkRoot 'build-tools') -Recurse -File -Filter $apksignerName |
                Sort-Object { [version]$_.Directory.Name } -Descending |
                Select-Object -First 1
        if ($null -eq $apksigner) {
            throw "Unable to locate $apksignerName under the Android SDK."
        }
        $signatureOutput = (& $apksigner.FullName verify --verbose --print-certs $artifact 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0) {
            throw "APK signature verification failed: $signatureOutput"
        }
        $certificateMatch = [regex]::Match(
            $signatureOutput,
            'certificate SHA-256 digest:\s*([0-9A-Fa-f:]+)',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
    } else {
        $jarsigner = Get-Command jarsigner -ErrorAction Stop
        $signatureOutput = (& $jarsigner.Source -verify $artifact 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0) {
            throw "AAB signature verification failed: $signatureOutput"
        }
        $keytool = Get-Command keytool -ErrorAction Stop
        $certificateOutput = (& $keytool.Source -printcert -jarfile $artifact 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to read the AAB signing certificate: $certificateOutput"
        }
        $certificateMatch = [regex]::Match(
            $certificateOutput,
            'SHA256:\s*([0-9A-Fa-f:]+)',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
    }

    if (-not $certificateMatch.Success) {
        throw 'Unable to read the signing certificate SHA-256 fingerprint.'
    }
    $certificateSha256 = $certificateMatch.Groups[1].Value.Replace(':', '').ToLowerInvariant()
    $expected = $ExpectedCertSha256.Replace(':', '').Replace(' ', '').ToLowerInvariant()
    if ($certificateSha256 -ne $expected) {
        throw "Signing certificate mismatch. Expected $expected, found $certificateSha256."
    }
}

[pscustomobject]@{
    Artifact = $file.FullName
    Bytes = $file.Length
    MiB = [math]::Round($sizeMiB, 2)
    Format = $Format
    Abi = 'arm64-v8a'
    RustCore = $requiredCore
    CertificateSha256 = $certificateSha256
}
