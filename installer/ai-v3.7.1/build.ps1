$ErrorActionPreference = 'Stop'

$installerDir = Split-Path -Parent $PSCommandPath
$repoRoot = [IO.Path]::GetFullPath((Join-Path $installerDir '..\..'))
$sourceDir = [IO.Path]::GetFullPath((Join-Path $repoRoot 'illustrator\su-ai-png-export'))
$allowedBuildRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'build')) + [IO.Path]::DirectorySeparatorChar
$buildDir = [IO.Path]::GetFullPath((Join-Path $repoRoot 'build\ai-installer-v3.7.1'))
$payload = Join-Path $buildDir 'PluginPayload.zip'
$testExe = Join-Path $buildDir 'InstallerCoreTests.exe'
$zipOutput = Join-Path $repoRoot 'SU_AI_PNG_Export_v3.7.1.zip'
$output = Join-Path $repoRoot 'SU_AI_PNG_Export_v3.7.1_Setup.exe'
$csc = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'

if (-not (Test-Path -LiteralPath $csc -PathType Leaf)) {
    throw "C# compiler not found: $csc"
}
if (-not (Test-Path -LiteralPath $sourceDir -PathType Container)) {
    throw "Plugin source not found: $sourceDir"
}
if (-not $buildDir.StartsWith($allowedBuildRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe build directory: $buildDir"
}

if (Test-Path -LiteralPath $buildDir) {
    Remove-Item -LiteralPath $buildDir -Recurse -Force
}
New-Item -ItemType Directory -Path $buildDir | Out-Null

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory(
    $sourceDir,
    $payload,
    [IO.Compression.CompressionLevel]::Optimal,
    $false)

function Assert-PayloadMatchesSource {
    param(
        [Parameter(Mandatory = $true)][string]$PayloadPath,
        [Parameter(Mandatory = $true)][string]$SourcePath
    )

    $archive = [IO.Compression.ZipFile]::OpenRead($PayloadPath)
    $sha = [Security.Cryptography.SHA256]::Create()
    $mismatches = @()
    try {
        $entries = @($archive.Entries | Where-Object { -not [String]::IsNullOrEmpty($_.Name) })
        $sourceFiles = @(Get-ChildItem -LiteralPath $SourcePath -File -Recurse)
        $forbidden = @($entries | Where-Object { $_.FullName -match '(?i)SUAIShortcutHost\.exe$' })

        foreach ($entry in $entries) {
            $relative = $entry.FullName.Replace('/', [IO.Path]::DirectorySeparatorChar)
            $sourceFile = Join-Path $SourcePath $relative
            if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) {
                $mismatches += "missing source: $relative"
                continue
            }

            $stream = $entry.Open()
            try {
                $embeddedHash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '')
            }
            finally {
                $stream.Dispose()
            }

            $sourceHash = (Get-FileHash -LiteralPath $sourceFile -Algorithm SHA256).Hash
            if ($embeddedHash -ne $sourceHash) {
                $mismatches += "hash mismatch: $relative"
            }
        }

        if ($sourceFiles.Count -ne 11 -or $entries.Count -ne 11 -or $forbidden.Count -ne 0 -or $mismatches.Count -ne 0) {
            throw "Payload mismatch: source=$($sourceFiles.Count), entries=$($entries.Count), forbidden=$($forbidden.Count), errors=$($mismatches -join '; ')"
        }
    }
    finally {
        $sha.Dispose()
        $archive.Dispose()
    }
}

Assert-PayloadMatchesSource -PayloadPath $payload -SourcePath $sourceDir
Copy-Item -LiteralPath $payload -Destination $zipOutput -Force

$references = @(
    '/r:System.IO.Compression.dll',
    '/r:System.IO.Compression.FileSystem.dll'
)
$coreSource = Join-Path $installerDir 'InstallerCore.cs'
$testSource = Join-Path $installerDir 'InstallerCoreTests.cs'
$formSource = Join-Path $installerDir 'InstallerForm.cs'
$programSource = Join-Path $installerDir 'Program.cs'
$manifest = Join-Path $installerDir 'app.manifest'

$testArguments = @(
    '/nologo',
    '/codepage:65001',
    '/target:exe',
    "/out:$testExe",
    "/resource:$payload,PluginPayload"
) + $references + @($coreSource, $testSource)

& $csc @testArguments
if ($LASTEXITCODE -ne 0) {
    throw 'Installer core test compilation failed.'
}

& $testExe $sourceDir
if ($LASTEXITCODE -ne 0) {
    throw 'Installer core tests failed.'
}

$installerArguments = @(
    '/nologo',
    '/codepage:65001',
    '/target:winexe',
    '/platform:anycpu',
    "/out:$output",
    "/resource:$payload,PluginPayload",
    "/win32manifest:$manifest",
    '/r:System.Windows.Forms.dll',
    '/r:System.Drawing.dll'
) + $references + @($coreSource, $formSource, $programSource)

& $csc @installerArguments
if ($LASTEXITCODE -ne 0) {
    throw 'Installer compilation failed.'
}

& $output --verify-payload | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'Final embedded payload verification failed.'
}

$version = (Get-Item -LiteralPath $output).VersionInfo
if ($version.FileVersion -ne '3.7.1.0' -or $version.ProductVersion -ne '3.7.1') {
    throw "Unexpected version metadata: $($version.FileVersion) / $($version.ProductVersion)"
}

$zipHash = Get-FileHash -LiteralPath $zipOutput -Algorithm SHA256
$exeHash = Get-FileHash -LiteralPath $output -Algorithm SHA256
Write-Output 'BUILD_OK=true'
Write-Output "ZIP_OUTPUT=$zipOutput"
Write-Output "OUTPUT=$output"
Write-Output "FILE_VERSION=$($version.FileVersion)"
Write-Output "PRODUCT_VERSION=$($version.ProductVersion)"
Write-Output "ZIP_SHA256=$($zipHash.Hash)"
Write-Output "EXE_SHA256=$($exeHash.Hash)"
