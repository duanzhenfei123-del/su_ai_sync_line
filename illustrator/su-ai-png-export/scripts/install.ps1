$ErrorActionPreference = "Stop"

$extensionName = "su-ai-png-export"
$source = Split-Path -Parent $PSScriptRoot
$extensionsRoot = Join-Path $env:APPDATA "Adobe\CEP\extensions"
$destination = Join-Path $extensionsRoot $extensionName

Write-Host "正在安装 SU+AI PNG 导出..."
Write-Host "来源: $source"
Write-Host "目标: $destination"
Write-Host ""

# 创建目录并复制文件
New-Item -ItemType Directory -Path $extensionsRoot -Force | Out-Null
New-Item -ItemType Directory -Path $destination -Force | Out-Null
Copy-Item -Path (Join-Path $source "*") -Destination $destination -Recurse -Force

# 自动开启 CEP 调试模式（覆盖多个 CSXS 版本）
Write-Host "正在开启 PlayerDebugMode..."
foreach ($version in 9..20) {
    $registryPath = "HKCU:\Software\Adobe\CSXS.$version"
    New-Item -Path $registryPath -Force | Out-Null
    Set-ItemProperty -Path $registryPath -Name "PlayerDebugMode" -Value "1" -Type String
}

Write-Host ""
Write-Host "SU+AI PNG 导出 v3.6 安装完成！"
Write-Host ""
Write-Host "目标位置: $destination"
Write-Host ""
Write-Host "请重启 Illustrator，然后打开："
Write-Host "  窗口 > 扩展（旧版） > SU+AI PNG 导出"
