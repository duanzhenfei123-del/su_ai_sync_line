$ErrorActionPreference='Stop'
$script=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\illustrator\su-ai-png-export\scripts\install.ps1'))
$raw=Get-Content -Raw -LiteralPath $script
if ($raw -notmatch '(?m)^param\(' -or $raw -notmatch 'SourcePath') { throw 'Manual installer is not test-isolated yet' }
$temp=Join-Path ([IO.Path]::GetTempPath()) ('suai-manual-'+[Guid]::NewGuid().ToString('N'))

function Get-TreeSnapshot([string]$Path) {
    $root=[IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    @(Get-ChildItem -LiteralPath $root -Recurse | Sort-Object FullName | ForEach-Object {
        $relative=$_.FullName.Substring($root.Length).TrimStart([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
        if ($_.PSIsContainer) { 'D|' + $relative } else { 'F|' + $relative + '|' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    })
}

try {
    $selfRoot=Join-Path $temp 'self-overlap'
    $selfExtensions=Join-Path $selfRoot 'extensions'
    $selfTarget=Join-Path $selfExtensions 'su-ai-png-export'
    $selfData=Join-Path $selfRoot 'data'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\illustrator\su-ai-png-export') -Destination $selfTarget -Recurse
    New-Item -ItemType Directory -Path (Join-Path $selfExtensions 'sibling') -Force | Out-Null
    New-Item -ItemType Directory -Path $selfData -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $selfTarget 'preserve.txt'),'target-original')
    [IO.File]::WriteAllText((Join-Path $selfExtensions 'sibling\keep.txt'),'sibling-original')
    [IO.File]::WriteAllText((Join-Path $selfData 'panel.heartbeat'),'data-original')
    $beforeSelfInstall=Get-TreeSnapshot $selfRoot
    $selfScript=Join-Path $selfTarget 'scripts\install.ps1'
    $rejected=$false
    try {
        & $selfScript -SourcePath $selfTarget -ExtensionsRoot $selfExtensions -DataRoot $selfData -SkipDebugMode
    } catch {
        if ($_.Exception.Message -notmatch '重叠') { throw }
        $rejected=$true
    }
    if (-not $rejected) { throw 'Installer accepted an overlapping source and destination' }
    $afterSelfInstall=Get-TreeSnapshot $selfRoot
    if (@(Compare-Object -ReferenceObject $beforeSelfInstall -DifferenceObject $afterSelfInstall).Count -ne 0) {
        throw 'Rejected self-install mutated target, sibling, or data files'
    }

    $source=Join-Path $temp 'source'
    $extensions=Join-Path $temp 'extensions'
    $data=Join-Path $temp 'data'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\illustrator\su-ai-png-export') -Destination $source -Recurse
    $target=Join-Path $extensions 'su-ai-png-export'
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $extensions 'sibling') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $target 'obsolete.txt'),'old')
    Set-Content -LiteralPath (Join-Path $extensions 'sibling\keep.txt') -Value keep
    New-Item -ItemType Directory -Path $data -Force | Out-Null
    'panel.heartbeat','shortcut.command','shortcuts.cfg','shortcut-host.status' | ForEach-Object { Set-Content -LiteralPath (Join-Path $data $_) -Value stale }
    & $script -SourcePath $source -ExtensionsRoot $extensions -DataRoot $data -SkipDebugMode
    if (Test-Path -LiteralPath (Join-Path $target 'obsolete.txt')) { throw 'Obsolete target file remains' }
    if (-not (Test-Path -LiteralPath (Join-Path $target 'CSXS\manifest.xml') -PathType Leaf)) { throw 'Known source file was not installed' }
    if (Test-Path -LiteralPath (Join-Path $target 'bin\SUAIShortcutHost.exe')) { throw 'Helper was installed' }
    $backups=@(Get-ChildItem -LiteralPath (Join-Path $data 'backups') -Filter *.zip)
    if ($backups.Count -ne 1) { throw 'Backup missing' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive=[IO.Compression.ZipFile]::OpenRead($backups[0].FullName)
    try {
        $obsoleteEntry=$archive.GetEntry('obsolete.txt')
        if ($null -eq $obsoleteEntry) { throw 'Backup omitted obsolete.txt' }
        $reader=New-Object IO.StreamReader($obsoleteEntry.Open())
        try { $obsoleteContent=$reader.ReadToEnd() } finally { $reader.Dispose() }
        if ($obsoleteContent -ne 'old') { throw 'Backup changed obsolete.txt content' }
    } finally {
        $archive.Dispose()
    }
    if ((Get-Content -LiteralPath (Join-Path $extensions 'sibling\keep.txt')) -ne 'keep') { throw 'Sibling changed' }
    'panel.heartbeat','shortcut.command','shortcuts.cfg','shortcut-host.status' | ForEach-Object { if (Test-Path -LiteralPath (Join-Path $data $_)) { throw "Legacy file remains: $_" } }
    Write-Output 'PASS AI manual installer'
} finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
