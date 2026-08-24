param(
    [ValidateSet('all', 'universal', 'arm64-v8a', 'armeabi-v7a', 'x86_64')]
    [string]$Target = 'all',
    [string]$FlutterRoot = $env:FLUTTER_ROOT,
    [string]$ExpectedCertSha256 = $env:AIUSAGE_ANDROID_CERT_SHA256,
    [switch]$RequireSignature,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$appRoot = Join-Path $projectRoot 'app'
$outputRoot = Join-Path $appRoot 'build\release'
$supportedAbis = @('armeabi-v7a', 'arm64-v8a', 'x86_64')
$targetPlatforms = @{
    'armeabi-v7a' = 'android-arm'
    'arm64-v8a' = 'android-arm64'
    'x86_64' = 'android-x64'
}

function Invoke-Git([string[]]$Arguments) {
    $output = (& git -C $projectRoot @Arguments 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "Git command failed: git $($Arguments -join ' ')`n$output"
    }
    return $output
}

if ((Invoke-Git @('rev-parse', '--is-shallow-repository')) -ne 'false') {
    throw 'Release builds require complete Git history; shallow clones are not supported.'
}
$buildNumberText = Invoke-Git @('rev-list', '--count', 'HEAD')
$buildNumber = 0
if (-not [int]::TryParse($buildNumberText, [ref]$buildNumber) -or $buildNumber -le 0) {
    throw "Invalid Git commit count: $buildNumberText"
}

$pubspec = Get-Content -Raw -LiteralPath (Join-Path $appRoot 'pubspec.yaml')
$versionMatch = [regex]::Match($pubspec, '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?)\s*$')
if (-not $versionMatch.Success) {
    throw 'app/pubspec.yaml must contain a SemVer without a +buildNumber suffix.'
}
$versionName = $versionMatch.Groups[1].Value

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

function Resolve-AndroidTool([string]$Name) {
    $androidSdkRoot = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } else { $env:ANDROID_HOME }
    if ([string]::IsNullOrWhiteSpace($androidSdkRoot)) {
        $localProperties = Join-Path $appRoot 'android\local.properties'
        if (Test-Path -LiteralPath $localProperties -PathType Leaf) {
            $sdkProperty = Get-Content -LiteralPath $localProperties |
                Where-Object { $_ -match '^sdk\.dir=' } |
                Select-Object -First 1
            if ($sdkProperty) {
                $androidSdkRoot = ($sdkProperty -replace '^sdk\.dir=', '') -replace '\\\\', '\'
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($androidSdkRoot)) {
        throw 'ANDROID_SDK_ROOT or ANDROID_HOME is required to locate Android build tools.'
    }

    $toolName = if ($IsWindows) { "$Name.exe" } else { $Name }
    if ($Name -eq 'apksigner' -and $IsWindows) { $toolName = 'apksigner.bat' }
    $tool = Get-ChildItem -LiteralPath (Join-Path $androidSdkRoot 'build-tools') -Recurse -File -Filter $toolName |
        Sort-Object { [version]$_.Directory.Name } -Descending |
        Select-Object -First 1
    if ($null -eq $tool) {
        throw "Unable to locate $toolName under the Android SDK."
    }
    return $tool.FullName
}

$aapt = Resolve-AndroidTool 'aapt'
$apksigner = if ($RequireSignature) { Resolve-AndroidTool 'apksigner' } else { $null }

if (-not $SkipBuild) {
    New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
    Push-Location $appRoot
    try {
        if ($Target -in @('all', 'universal')) {
            & $flutterBin build apk --release --target-platform android-arm,android-arm64,android-x64 `
                --build-name $versionName --build-number $buildNumber --no-pub
            if ($LASTEXITCODE -ne 0) { throw "Flutter universal APK build failed with exit code $LASTEXITCODE." }
            Copy-Item -LiteralPath 'build\app\outputs\flutter-apk\app-release.apk' `
                -Destination (Join-Path $outputRoot 'AiUsage-android-release-universal.apk') -Force
        }

        if ($Target -eq 'all') {
            & $flutterBin build apk --release --split-per-abi `
                --target-platform android-arm,android-arm64,android-x64 `
                --build-name $versionName --build-number $buildNumber `
                -P force-version-code-ignoring-abi=true --no-pub
            if ($LASTEXITCODE -ne 0) { throw "Flutter split APK build failed with exit code $LASTEXITCODE." }
            foreach ($abi in $supportedAbis) {
                Copy-Item -LiteralPath "build\app\outputs\flutter-apk\app-$abi-release.apk" `
                    -Destination (Join-Path $outputRoot "AiUsage-android-release-$abi.apk") -Force
            }
        } elseif ($Target -in $supportedAbis) {
            & $flutterBin build apk --release --target-platform $targetPlatforms[$Target] `
                --build-name $versionName --build-number $buildNumber --no-pub
            if ($LASTEXITCODE -ne 0) { throw "Flutter $Target APK build failed with exit code $LASTEXITCODE." }
            Copy-Item -LiteralPath 'build\app\outputs\flutter-apk\app-release.apk' `
                -Destination (Join-Path $outputRoot "AiUsage-android-release-$Target.apk") -Force
        }
    } finally {
        Pop-Location
    }
}

$targetsToValidate = if ($Target -eq 'all') { @('universal') + $supportedAbis } else { @($Target) }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$results = @()

foreach ($artifactTarget in $targetsToValidate) {
    $artifact = Join-Path $outputRoot "AiUsage-android-release-$artifactTarget.apk"
    if (-not (Test-Path -LiteralPath $artifact -PathType Leaf)) {
        throw "Android artifact not found at $artifact"
    }

    $expectedAbis = if ($artifactTarget -eq 'universal') { $supportedAbis } else { @($artifactTarget) }
    $archive = [System.IO.Compression.ZipFile]::OpenRead($artifact)
    try {
        $entries = @($archive.Entries | ForEach-Object FullName)
        foreach ($abi in $expectedAbis) {
            $requiredCore = "lib/$abi/libai_usage_core.so"
            if ($requiredCore -notin $entries) {
                throw "$artifactTarget APK is missing $requiredCore. Check FLUTTER_ROOT and Cargokit output."
            }
        }

        $actualAbis = @($entries |
            Where-Object { $_ -match '^lib/([^/]+)/.*\.so$' } |
            ForEach-Object { [regex]::Match($_, '^lib/([^/]+)/').Groups[1].Value } |
            Sort-Object -Unique)
        if (($actualAbis -join ',') -ne (($expectedAbis | Sort-Object) -join ',')) {
            throw "$artifactTarget APK ABI mismatch. Expected $($expectedAbis -join ', '), found $($actualAbis -join ', ')."
        }

        $forbiddenEntries = @($entries | Where-Object {
            $_ -eq 'assets/flutter_assets/kernel_blob.bin' -or
            $_ -like 'lib/*/libVkLayer_khronos_validation.so'
        })
        if ($forbiddenEntries.Count -gt 0) {
            throw "Debug-only artifacts found: $($forbiddenEntries -join ', ')"
        }
    } finally {
        $archive.Dispose()
    }

    $badging = (& $aapt dump badging $artifact 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) { throw "Unable to inspect AndroidManifest for ${artifactTarget}: $badging" }
    $packageMatch = [regex]::Match($badging, "package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'")
    if (-not $packageMatch.Success) { throw "Unable to parse Android package metadata for $artifactTarget." }
    if ($packageMatch.Groups[1].Value -ne 'dev.chendusk.aiusage') {
        throw "Unexpected Android package id: $($packageMatch.Groups[1].Value)"
    }
    if ($packageMatch.Groups[2].Value -ne [string]$buildNumber) {
        throw "Android versionCode mismatch. Expected $buildNumber, found $($packageMatch.Groups[2].Value)."
    }
    if ($packageMatch.Groups[3].Value -ne $versionName) {
        throw "Android versionName mismatch. Expected $versionName, found $($packageMatch.Groups[3].Value)."
    }

    $file = Get-Item -LiteralPath $artifact
    $sizeMiB = $file.Length / 1MB
    $sizeLimitMiB = if ($artifactTarget -eq 'universal') { 90 } else { 30 }
    if ($sizeMiB -gt $sizeLimitMiB) {
        throw "$artifactTarget Release APK is $([math]::Round($sizeMiB, 2)) MiB, exceeding the $sizeLimitMiB MiB gate."
    }

    $certificateSha256 = $null
    if ($RequireSignature) {
        if ([string]::IsNullOrWhiteSpace($ExpectedCertSha256)) {
            throw 'Expected certificate SHA-256 is required for signature verification.'
        }
        $signatureOutput = (& $apksigner verify --verbose --print-certs $artifact 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0) { throw "APK signature verification failed: $signatureOutput" }
        $certificateMatch = [regex]::Match(
            $signatureOutput,
            'certificate SHA-256 digest:\s*([0-9A-Fa-f:]+)',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
        if (-not $certificateMatch.Success) { throw 'Unable to read the signing certificate SHA-256 fingerprint.' }
        $certificateSha256 = $certificateMatch.Groups[1].Value.Replace(':', '').ToLowerInvariant()
        $expected = $ExpectedCertSha256.Replace(':', '').Replace(' ', '').ToLowerInvariant()
        if ($certificateSha256 -ne $expected) {
            throw "Signing certificate mismatch. Expected $expected, found $certificateSha256."
        }
    }

    $results += [pscustomobject]@{
        Artifact = $file.FullName
        Bytes = $file.Length
        MiB = [math]::Round($sizeMiB, 2)
        VersionName = $versionName
        VersionCode = $buildNumber
        Abi = $expectedAbis -join ','
        CertificateSha256 = $certificateSha256
    }
}

$results
