$ErrorActionPreference='Stop'
$script=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\illustrator\su-ai-png-export\scripts\install.ps1'))
$raw=Get-Content -Raw -LiteralPath $script
if ($raw -notmatch '(?m)^param\(' -or $raw -notmatch 'SourcePath') { throw 'Manual installer is not test-isolated yet' }
$temp=Join-Path ([IO.Path]::GetTempPath()) ('suai-manual-'+[Guid]::NewGuid().ToString('N'))
try {
    $source=Join-Path $temp 'source'
    $extensions=Join-Path $temp 'extensions'
    $data=Join-Path $temp 'data'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\illustrator\su-ai-png-export') -Destination $source -Recurse
    $target=Join-Path $extensions 'su-ai-png-export'
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $extensions 'sibling') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $target 'obsolete.txt') -Value old
    Set-Content -LiteralPath (Join-Path $extensions 'sibling\keep.txt') -Value keep
    New-Item -ItemType Directory -Path $data -Force | Out-Null
    'panel.heartbeat','shortcut.command','shortcuts.cfg','shortcut-host.status' | ForEach-Object { Set-Content -LiteralPath (Join-Path $data $_) -Value stale }
    & $script -SourcePath $source -ExtensionsRoot $extensions -DataRoot $data -SkipDebugMode
    if (Test-Path -LiteralPath (Join-Path $target 'obsolete.txt')) { throw 'Obsolete target file remains' }
    if (Test-Path -LiteralPath (Join-Path $target 'bin\SUAIShortcutHost.exe')) { throw 'Helper was installed' }
    if ((Get-ChildItem -LiteralPath (Join-Path $data 'backups') -Filter *.zip).Count -ne 1) { throw 'Backup missing' }
    if ((Get-Content -LiteralPath (Join-Path $extensions 'sibling\keep.txt')) -ne 'keep') { throw 'Sibling changed' }
    'panel.heartbeat','shortcut.command','shortcuts.cfg','shortcut-host.status' | ForEach-Object { if (Test-Path -LiteralPath (Join-Path $data $_)) { throw "Legacy file remains: $_" } }
    Write-Output 'PASS AI manual installer'
} finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
