param(
    [string]$SourcePath=(Split-Path -Parent $PSScriptRoot),
    [string]$ExtensionsRoot=(Join-Path $env:APPDATA 'Adobe\CEP\extensions'),
    [string]$DataRoot=(Join-Path $env:APPDATA 'SU_AI_PNG_Export'),
    [switch]$SkipDebugMode
)

$ErrorActionPreference = 'Stop'
$extensionName = 'su-ai-png-export'
$source = [IO.Path]::GetFullPath($SourcePath)
$extensionsRootPath = [IO.Path]::GetFullPath($ExtensionsRoot)
$dataRootPath = [IO.Path]::GetFullPath($DataRoot)
$destination = [IO.Path]::GetFullPath((Join-Path $extensionsRootPath $extensionName))
$destinationPrefix = $extensionsRootPath.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar

if (-not $destination.StartsWith($destinationPrefix, [StringComparison]::OrdinalIgnoreCase) -or
    -not $destination.EndsWith(([IO.Path]::DirectorySeparatorChar + $extensionName), [StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe extension destination: $destination"
}

Write-Host '正在安装 SU+AI PNG 导出...'
Write-Host "来源: $source"
Write-Host "目标: $destination"
Write-Host ''

New-Item -ItemType Directory -Path $extensionsRootPath -Force | Out-Null
New-Item -ItemType Directory -Path $dataRootPath -Force | Out-Null

'panel.heartbeat','shortcut.command','shortcuts.cfg' | ForEach-Object {
    $legacyPath = Join-Path $dataRootPath $_
    if (Test-Path -LiteralPath $legacyPath) {
        Remove-Item -LiteralPath $legacyPath -Force
    }
}

$statusPath = Join-Path $dataRootPath 'shortcut-host.status'
$deadline = [DateTime]::UtcNow.AddSeconds(5)
while (Test-Path -LiteralPath $statusPath) {
    $processId = 0
    $statusPid = ([string](Get-Content -Raw -LiteralPath $statusPath)).Trim()
    if (-not [Int32]::TryParse($statusPid, [ref]$processId)) {
        break
    }

    $legacyHost = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if ($null -eq $legacyHost -or $legacyHost.ProcessName -ne 'SUAIShortcutHost') {
        break
    }
    if ([DateTime]::UtcNow -ge $deadline) {
        throw '旧版快捷键程序仍在运行。请关闭旧版 AI 插件面板后重试；Illustrator 不会被强制关闭。'
    }
    Start-Sleep -Milliseconds 100
}
if (Test-Path -LiteralPath $statusPath) {
    Remove-Item -LiteralPath $statusPath -Force
}

if (Test-Path -LiteralPath $destination) {
    $backupRoot = Join-Path $dataRootPath 'backups'
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $backupPath = Join-Path $backupRoot ('su-ai-png-export-' + (Get-Date -Format 'yyyyMMdd-HHmmssfff') + '-' + [Guid]::NewGuid().ToString('N') + '.zip')
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($destination, $backupPath, [IO.Compression.CompressionLevel]::Optimal, $false)
    Remove-Item -LiteralPath $destination -Recurse -Force
}

Copy-Item -LiteralPath $source -Destination $destination -Recurse -Force

if (-not $SkipDebugMode) {
    Write-Host '正在开启 PlayerDebugMode...'
    foreach ($version in 9..20) {
        $registryPath = "HKCU:\Software\Adobe\CSXS.$version"
        New-Item -Path $registryPath -Force | Out-Null
        Set-ItemProperty -Path $registryPath -Name 'PlayerDebugMode' -Value '1' -Type String
    }
}

Write-Host ''
Write-Host 'SU+AI PNG 导出 v3.7.1 安装完成！'
Write-Host "目标位置: $destination"
