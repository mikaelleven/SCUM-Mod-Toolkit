#Requires -Version 5.1

<#
.SYNOPSIS
    SCUM Mod Toolkit (SKit).

.DESCRIPTION
    Installs and wraps FModel, repak and UAssetGUI, and provides a small
    project workflow for building and testing SCUM .pak mods.
#>

[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Position = 0)]
    [string]$Command = 'help',

    [Alias('o', 'omit-key')]
    [switch]$OmitKey,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:SKitVersion = '1.1.0.10'
$script:ProjectFileName = 'skit.yml'
$script:DefaultEngineVersion = 'VER_UE4_27'
$script:GitHubApiVersion = '2026-03-10'
$script:InstallRoot = Join-Path $env:LOCALAPPDATA 'Programs\SKit'
$script:ToolsRoot = Join-Path $script:InstallRoot 'tools'
$script:GlobalConfigPath = Join-Path $script:InstallRoot 'SCUM-Mod-Toolkit.yaml'
$script:PreviousGlobalConfigPath = Join-Path $script:InstallRoot 'SKit.yaml'
$script:LegacyGlobalConfigPath = Join-Path $script:InstallRoot 'skit.config.yml'
$script:ScumAesKeyFileName = 'SCUM-AES-Key.txt'
$script:ScumAesKeyUri = 'https://www.gamestranslator.it/index.php?/forums/topic/1485-raccolta-di-chiavi-di-crittografia-aes-per-giochi-ue45/'

if ($null -eq $Arguments) {
    $Arguments = @()
}

function Write-Info {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "[SKit] $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "[SKit] $Message" -ForegroundColor Green
}

function Assert-Windows {
    if ($env:OS -ne 'Windows_NT') {
        throw 'SKit currently supports Windows only.'
    }
}

function Resolve-FullPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$AllowMissing
    )

    $expandedPath = [Environment]::ExpandEnvironmentVariables($Path)
    if (-not [System.IO.Path]::IsPathRooted($expandedPath)) {
        $expandedPath = Join-Path (Get-Location).Path $expandedPath
    }

    $fullPath = [System.IO.Path]::GetFullPath($expandedPath)
    if (-not $AllowMissing -and -not (Test-Path -LiteralPath $fullPath)) {
        throw "Path not found: $fullPath"
    }

    return $fullPath
}

function Write-Utf8File {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )

    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8WithoutBom)
}

function Write-CommandShim {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$RelativeExecutable
    )

    $shimPath = Join-Path $script:InstallRoot "$Name.cmd"
    $windowsRelativePath = $RelativeExecutable.Replace('/', '\')
    $content = "@echo off`r`n`"%~dp0$windowsRelativePath`" %*`r`n"
    Write-Utf8File -Path $shimPath -Content $content
}

function Add-InstallRootToUserPath {
    $normalizedInstallRoot = $script:InstallRoot.TrimEnd('\')
    try {
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        $entries = @()
        if (-not [string]::IsNullOrWhiteSpace($userPath)) {
            $entries = @($userPath.Split(';') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }

        $alreadyRegistered = $false
        foreach ($entry in $entries) {
            $expandedEntry = [Environment]::ExpandEnvironmentVariables($entry).TrimEnd('\')
            if ($expandedEntry.Equals($normalizedInstallRoot, [StringComparison]::OrdinalIgnoreCase)) {
                $alreadyRegistered = $true
                break
            }
        }

        if (-not $alreadyRegistered) {
            $newUserPath = (@($entries) + $script:InstallRoot) -join ';'
            [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
            Write-Info 'Added the SKit directory to the user PATH.'
        }
    }
    catch {
        Write-Warning "Could not register the SKit directory in the user PATH. Run 'skit setup register-path' later. $($_.Exception.Message)"
        return $false
    }

    $processEntries = @()
    if (-not [string]::IsNullOrWhiteSpace($env:Path)) {
        $processEntries = @($env:Path.Split(';'))
    }
    if (-not ($processEntries | Where-Object {
                ([Environment]::ExpandEnvironmentVariables($_).TrimEnd('\')).Equals(
                    $normalizedInstallRoot,
                    [StringComparison]::OrdinalIgnoreCase
                )
            })) {
        $env:Path = if ([string]::IsNullOrWhiteSpace($env:Path)) {
            $script:InstallRoot
        }
        else {
            "$env:Path;$script:InstallRoot"
        }
    }
    return $true
}

function Remove-InstallRootFromUserPath {
    $normalizedInstallRoot = $script:InstallRoot.TrimEnd('\')
    try {
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if ([string]::IsNullOrWhiteSpace($userPath)) {
            return
        }

        $entries = @($userPath.Split(';') | Where-Object {
                -not [string]::IsNullOrWhiteSpace($_) -and
                -not ([Environment]::ExpandEnvironmentVariables($_).TrimEnd('\')).Equals(
                    $normalizedInstallRoot,
                    [StringComparison]::OrdinalIgnoreCase
                )
            })
        [Environment]::SetEnvironmentVariable('Path', ($entries -join ';'), 'User')
    }
    catch {
        Write-Warning "Could not remove the SKit directory from the user PATH. $($_.Exception.Message)"
    }
}

function Uninstall-SKit {
    param([switch]$RemoveConfiguration)

    Assert-Windows
    $installRoot = [System.IO.Path]::GetFullPath($script:InstallRoot)
    if (-not (Test-Path -LiteralPath $installRoot -PathType Container)) {
        Write-Info "SKit is not installed in $installRoot."
        return
    }

    $configurationFiles = @(
        Get-ChildItem -LiteralPath $installRoot -File -ErrorAction Stop |
            Where-Object { $_.Extension -in @('.yaml', '.yml') }
    )
    if ($RemoveConfiguration -and $configurationFiles.Count -gt 0) {
        $confirmation = Read-Host 'Remove SKit YAML configuration files? Type Y to continue'
        if (-not ([string]$confirmation).Equals('Y', [StringComparison]::OrdinalIgnoreCase)) {
            Write-Info 'Uninstallation cancelled. SKit files were not removed.'
            return
        }
    }

    $toolsRoot = [System.IO.Path]::GetFullPath($script:ToolsRoot)
    $expectedToolsRoot = Join-Path $installRoot 'tools'
    if (-not $toolsRoot.Equals($expectedToolsRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove an unexpected tools directory: $toolsRoot"
    }
    if (Test-Path -LiteralPath $toolsRoot -PathType Container) {
        Remove-Item -LiteralPath $toolsRoot -Recurse -Force
    }

    foreach ($file in @(Get-ChildItem -LiteralPath $installRoot -File -ErrorAction Stop)) {
        if (-not $RemoveConfiguration -and $file.Extension -in @('.yaml', '.yml')) {
            continue
        }
        Remove-Item -LiteralPath $file.FullName -Force
    }

    Remove-InstallRootFromUserPath
    if ($RemoveConfiguration) {
        if ((Test-Path -LiteralPath $installRoot -PathType Container) -and
            -not (Get-ChildItem -LiteralPath $installRoot -Force | Select-Object -First 1)) {
            Remove-Item -LiteralPath $installRoot -Force
        }
        Write-Success 'SKit and its YAML configuration files were removed.'
    }
    else {
        Write-Success 'SKit binaries, scripts, command files, and tools were removed.'
        Write-Info "SKit YAML configuration files were kept in $installRoot. Remove them with: skit setup uninstall all"
    }
}

function Install-Self {
    Assert-Windows
    [System.IO.Directory]::CreateDirectory($script:InstallRoot) | Out-Null
    [System.IO.Directory]::CreateDirectory($script:ToolsRoot) | Out-Null

    $sourcePath = Resolve-FullPath -Path $PSCommandPath
    $targetPath = Join-Path $script:InstallRoot 'SCUM-Mod-Toolkit.ps1'
    if (-not $sourcePath.Equals($targetPath, [StringComparison]::OrdinalIgnoreCase)) {
        Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
    }

    $launcher = @'
@echo off
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0SCUM-Mod-Toolkit.ps1" %*
'@
    Write-Utf8File -Path (Join-Path $script:InstallRoot 'skit.cmd') -Content ($launcher + "`r`n")

    Initialize-SKitConfig

    $legacyInstalledScript = Join-Path $script:InstallRoot 'skit.ps1'
    if (Test-Path -LiteralPath $legacyInstalledScript -PathType Leaf) {
        Remove-Item -LiteralPath $legacyInstalledScript -Force
    }

    Add-InstallRootToUserPath
}

function Ensure-SelfInstalled {
    Assert-Windows
    $installedScript = Join-Path $script:InstallRoot 'SCUM-Mod-Toolkit.ps1'
    $installedLauncher = Join-Path $script:InstallRoot 'skit.cmd'
    if (-not (Test-Path -LiteralPath $installedScript) -or
        -not (Test-Path -LiteralPath $installedLauncher)) {
        Install-Self
        Write-Success "SKit installed in $script:InstallRoot"
        Write-Info 'Open a new terminal before using the skit command globally.'
    }
}

function Get-GitHubHeaders {
    return @{
        Accept                 = 'application/vnd.github+json'
        'User-Agent'           = "SKit/$script:SKitVersion"
        'X-GitHub-Api-Version' = $script:GitHubApiVersion
    }
}

function Get-LatestGitHubRelease {
    param([Parameter(Mandatory)][string]$Repository)

    $uri = "https://api.github.com/repos/$Repository/releases/latest"
    try {
        return Invoke-RestMethod -Uri $uri -Headers (Get-GitHubHeaders) -UseBasicParsing
    }
    catch {
        throw "Could not retrieve the latest release for $Repository. $($_.Exception.Message)"
    }
}

function Select-ReleaseAsset {
    param(
        [Parameter(Mandatory)]$Release,
        [Parameter(Mandatory)][ValidateSet('fmodel', 'repak', 'uassetgui')][string]$Tool
    )

    $candidates = foreach ($asset in @($Release.assets)) {
        $name = [string]$asset.name
        if ($name -match '(?i)(sha(256)?|checksums?|symbols?|source|\.sig$|\.blockmap$)') {
            continue
        }

        $score = 0
        switch ($Tool) {
            'fmodel' {
                if ($name -match '(?i)^FModel\.zip$') { $score = 120 }
                elseif ($name -match '(?i)^FModel.*(win|windows|x64).*\.zip$') { $score = 110 }
                elseif ($name -match '(?i)^FModel.*\.zip$') { $score = 100 }
                elseif ($name -match '(?i)^FModel\.exe$') { $score = 90 }
            }
            'repak' {
                if ($name -match '(?i)^repak.*x86_64.*(pc-windows|windows|win64).*\.zip$') { $score = 120 }
                elseif ($name -match '(?i)^repak.*(pc-windows|windows|win64).*\.zip$') { $score = 110 }
                elseif ($name -match '(?i)^repak.*x86_64.*\.zip$') { $score = 100 }
                elseif ($name -match '(?i)^repak\.exe$') { $score = 90 }
            }
            'uassetgui' {
                if ($name -match '(?i)^UAssetGUI\.exe$') { $score = 120 }
                elseif ($name -match '(?i)^UAssetGUI.*(win|windows|x64).*\.zip$') { $score = 110 }
                elseif ($name -match '(?i)^UAssetGUI.*\.zip$') { $score = 100 }
            }
        }

        if ($score -gt 0) {
            [pscustomobject]@{
                Asset = $asset
                Score = $score
            }
        }
    }

    $selection = $candidates | Sort-Object Score -Descending | Select-Object -First 1
    if ($null -eq $selection) {
        $available = (@($Release.assets) | ForEach-Object { $_.name }) -join ', '
        throw "No supported Windows asset was found for $Tool. Available assets: $available"
    }

    return $selection.Asset
}

function Get-ExpectedSha256 {
    param([Parameter(Mandatory)]$Asset)

    if ($Asset.PSObject.Properties.Name -notcontains 'digest') {
        throw "GitHub did not provide SHA-256 metadata for release asset '$($Asset.name)'. Installation was stopped."
    }

    $digest = [string]$Asset.digest
    if ($digest -notmatch '(?i)^sha256:([0-9a-f]{64})$') {
        throw "GitHub did not provide a valid SHA-256 digest for release asset '$($Asset.name)'. Installation was stopped."
    }

    return $Matches[1].ToLowerInvariant()
}

function Get-FileSha256 {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Cannot calculate SHA-256 because the file was not found: $Path"
    }

    $stream = $null
    $sha256 = $null
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $hashBytes = $sha256.ComputeHash($stream)
        return [System.BitConverter]::ToString($hashBytes).Replace('-', '').ToLowerInvariant()
    }
    finally {
        if ($null -ne $sha256) {
            $sha256.Dispose()
        }
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}

function Invoke-VerifiedDownload {
    param(
        [Parameter(Mandatory)]$Asset,
        [Parameter(Mandatory)][string]$Destination
    )

    $expectedHash = Get-ExpectedSha256 -Asset $Asset
    Write-Info "Downloading $($Asset.name)..."
    Invoke-WebRequest `
        -Uri ([string]$Asset.browser_download_url) `
        -Headers (Get-GitHubHeaders) `
        -UseBasicParsing `
        -OutFile $Destination

    if ($Asset.size -and (Get-Item -LiteralPath $Destination).Length -ne [long]$Asset.size) {
        throw "Downloaded size does not match the GitHub release metadata for '$($Asset.name)'."
    }

    $actualHash = Get-FileSha256 -Path $Destination
    if ($actualHash -ne $expectedHash) {
        throw "SHA-256 verification failed for '$($Asset.name)'. Expected $expectedHash but got $actualHash."
    }

    Write-Success "SHA-256 verified: $actualHash"
}

function Get-ToolDefinition {
    param([Parameter(Mandatory)][ValidateSet('fmodel', 'repak', 'uassetgui')][string]$Tool)

    switch ($Tool) {
        'fmodel' {
            return @{
                Id         = 'fmodel'
                Name       = 'FModel'
                Repository = '4sval/FModel'
                Executable = 'FModel.exe'
            }
        }
        'repak' {
            return @{
                Id         = 'repak'
                Name       = 'repak'
                Repository = 'trumank/repak'
                Executable = 'repak.exe'
            }
        }
        'uassetgui' {
            return @{
                Id         = 'uassetgui'
                Name       = 'UAssetGUI'
                Repository = 'atenfyr/UAssetGUI'
                Executable = 'UAssetGUI.exe'
            }
        }
    }
}

function Install-Tool {
    param([Parameter(Mandatory)][ValidateSet('fmodel', 'repak', 'uassetgui')][string]$Tool)

    $definition = Get-ToolDefinition -Tool $Tool
    $release = Get-LatestGitHubRelease -Repository $definition.Repository
    $asset = Select-ReleaseAsset -Release $release -Tool $Tool
    $workDirectory = Join-Path $script:InstallRoot ('.install-' + [Guid]::NewGuid().ToString('N'))
    $downloadPath = Join-Path $workDirectory ([string]$asset.name)
    $payloadDirectory = Join-Path $workDirectory 'payload'
    $newToolDirectory = Join-Path $script:ToolsRoot ($definition.Id + '.new-' + [Guid]::NewGuid().ToString('N'))
    $toolDirectory = Join-Path $script:ToolsRoot $definition.Id
    $backupDirectory = Join-Path $script:ToolsRoot ($definition.Id + '.backup-' + [Guid]::NewGuid().ToString('N'))

    [System.IO.Directory]::CreateDirectory($workDirectory) | Out-Null
    [System.IO.Directory]::CreateDirectory($payloadDirectory) | Out-Null
    [System.IO.Directory]::CreateDirectory($newToolDirectory) | Out-Null

    try {
        Invoke-VerifiedDownload -Asset $asset -Destination $downloadPath

        if ([System.IO.Path]::GetExtension($downloadPath).Equals('.zip', [StringComparison]::OrdinalIgnoreCase)) {
            Expand-Archive -LiteralPath $downloadPath -DestinationPath $payloadDirectory -Force
        }
        elseif ([System.IO.Path]::GetExtension($downloadPath).Equals('.exe', [StringComparison]::OrdinalIgnoreCase)) {
            Copy-Item -LiteralPath $downloadPath -Destination (Join-Path $payloadDirectory $definition.Executable)
        }
        else {
            throw "Unsupported release asset format: $($asset.name)"
        }

        $executable = Get-ChildItem -LiteralPath $payloadDirectory -Filter $definition.Executable -File -Recurse |
            Select-Object -First 1
        if ($null -eq $executable) {
            throw "The release asset did not contain $($definition.Executable)."
        }

        Copy-Item -Path (Join-Path $executable.Directory.FullName '*') -Destination $newToolDirectory -Recurse -Force
        if (-not (Test-Path -LiteralPath (Join-Path $newToolDirectory $definition.Executable) -PathType Leaf)) {
            throw "Failed to prepare $($definition.Name) for installation."
        }

        if (Test-Path -LiteralPath $toolDirectory) {
            Move-Item -LiteralPath $toolDirectory -Destination $backupDirectory
        }

        try {
            Move-Item -LiteralPath $newToolDirectory -Destination $toolDirectory
        }
        catch {
            if (Test-Path -LiteralPath $backupDirectory) {
                Move-Item -LiteralPath $backupDirectory -Destination $toolDirectory
            }
            throw
        }

        if (Test-Path -LiteralPath $backupDirectory) {
            Remove-Item -LiteralPath $backupDirectory -Recurse -Force
        }

        Write-CommandShim `
            -Name $definition.Name `
            -RelativeExecutable "tools\$($definition.Id)\$($definition.Executable)"
        Write-Success "$($definition.Name) $($release.tag_name) installed."
    }
    finally {
        if (Test-Path -LiteralPath $workDirectory) {
            Remove-Item -LiteralPath $workDirectory -Recurse -Force
        }
        if (Test-Path -LiteralPath $newToolDirectory) {
            Remove-Item -LiteralPath $newToolDirectory -Recurse -Force
        }
    }
}

function Install-Tools {
    param([string]$Selection = 'all')

    $normalizedSelection = $Selection.ToLowerInvariant()
    $tools = switch ($normalizedSelection) {
        'all' { @('fmodel', 'repak', 'uassetgui') }
        'fmodel' { @('fmodel') }
        'repak' { @('repak') }
        'uassetgui' { @('uassetgui') }
        default { throw "Unknown tool '$Selection'. Use all, fmodel, repak or uassetgui." }
    }

    foreach ($tool in $tools) {
        Install-Tool -Tool $tool
    }
}

function Get-ToolExecutable {
    param([Parameter(Mandatory)][ValidateSet('fmodel', 'repak', 'uassetgui')][string]$Tool)

    $definition = Get-ToolDefinition -Tool $Tool
    $path = Join-Path (Join-Path $script:ToolsRoot $definition.Id) $definition.Executable
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "$($definition.Name) is not installed. Run: skit setup tools $Tool"
    }

    return $path
}

function Invoke-ExternalTool {
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string[]]$ToolArguments
    )

    $global:LASTEXITCODE = 0
    & $Executable @ToolArguments | Out-Host
    $exitCode = $global:LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "'$Executable' exited with code $exitCode."
    }
}

function Get-RepakAesArguments {
    param([switch]$OmitKey)

    if ($OmitKey) {
        return @()
    }

    $config = Merge-SKitConfig
    if ([string]::IsNullOrWhiteSpace($config.ScumAesKey)) {
        return @()
    }
    return @('--aes-key', (ConvertTo-NormalizedScumAesKey -Key $config.ScumAesKey))
}

function Split-SKitFileArguments {
    param([string[]]$FileArguments = @())

    $omitKey = $false
    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($argument in $FileArguments) {
        if ($argument -in @('-o', '-omit-key')) {
            $omitKey = $true
            continue
        }
        $paths.Add($argument)
    }

    return [pscustomobject]@{
        OmitKey = $omitKey
        Paths    = $paths.ToArray()
    }
}

function Invoke-Unpack {
    param(
        [Parameter(Mandatory)][string]$PakPath,
        [string]$OutputPath,
        [switch]$OmitKey
    )

    $source = Resolve-FullPath -Path $PakPath
    if ([System.IO.Path]::GetExtension($source) -ne '.pak') {
        throw "Expected a .pak file: $source"
    }

    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $destination = [System.IO.Path]::ChangeExtension($source, $null)
    }
    else {
        $destination = Resolve-FullPath -Path $OutputPath -AllowMissing
    }

    $repak = Get-ToolExecutable -Tool repak
    $toolArguments = @(Get-RepakAesArguments -OmitKey:$OmitKey)
    $toolArguments += @(
        'unpack',
        '--output', $destination,
        $source
    )
    Invoke-ExternalTool -Executable $repak -ToolArguments $toolArguments
}

function Invoke-Pack {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [string]$OutputPath,
        [switch]$OmitKey
    )

    $source = Resolve-FullPath -Path $SourcePath
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "Expected a directory: $source"
    }

    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $destination = "$source.pak"
    }
    else {
        $destination = Resolve-FullPath -Path $OutputPath -AllowMissing
    }

    if ([System.IO.Path]::GetExtension($destination) -ne '.pak') {
        $destination += '.pak'
    }

    [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($destination)) | Out-Null
    $repak = Get-ToolExecutable -Tool repak
    $toolArguments = @(Get-RepakAesArguments -OmitKey:$OmitKey)
    $toolArguments += @(
        'pack',
        '--version', 'V11',
        $source,
        $destination
    )
    Invoke-ExternalTool -Executable $repak -ToolArguments $toolArguments
}

function Convert-UAssetToJson {
    param(
        [Parameter(Mandatory)][string]$UAssetPath,
        [string]$EngineVersion = $script:DefaultEngineVersion,
        [string]$Mappings
    )

    $source = Resolve-FullPath -Path $UAssetPath
    if ([System.IO.Path]::GetExtension($source) -ne '.uasset') {
        throw "Expected a .uasset file: $source"
    }

    $destination = [System.IO.Path]::ChangeExtension($source, '.full.json')
    $toolArguments = @('tojson', $source, $destination, $EngineVersion)
    if (-not [string]::IsNullOrWhiteSpace($Mappings)) {
        $toolArguments += $Mappings
    }

    $uassetGui = Get-ToolExecutable -Tool uassetgui
    Invoke-ExternalTool -Executable $uassetGui -ToolArguments $toolArguments
    Write-Success "Exported $destination"
}

function Convert-JsonToUAsset {
    param(
        [Parameter(Mandatory)][string]$JsonPath,
        [string]$OutputPath,
        [string]$Mappings
    )

    $source = Resolve-FullPath -Path $JsonPath
    if (-not $source.EndsWith('.json', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Expected a .json file: $source"
    }

    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        if ($source.EndsWith('.full.json', [StringComparison]::OrdinalIgnoreCase)) {
            $destination = $source.Substring(0, $source.Length - '.full.json'.Length) + '.uasset'
        }
        else {
            $destination = [System.IO.Path]::ChangeExtension($source, '.uasset')
        }
    }
    else {
        $destination = Resolve-FullPath -Path $OutputPath -AllowMissing
        if ([System.IO.Path]::GetExtension($destination) -ne '.uasset') {
            $destination += '.uasset'
        }
    }

    $toolArguments = @('fromjson', $source, $destination)
    if (-not [string]::IsNullOrWhiteSpace($Mappings)) {
        $toolArguments += $Mappings
    }

    $uassetGui = Get-ToolExecutable -Tool uassetgui
    Invoke-ExternalTool -Executable $uassetGui -ToolArguments $toolArguments
    Write-Success "Created $destination"
}

function ConvertFrom-StrictYamlScalar {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)

    $trimmedValue = $Value.Trim()
    if ($trimmedValue.Length -eq 0) {
        return ''
    }

    if ($trimmedValue.StartsWith("'")) {
        if (-not $trimmedValue.EndsWith("'") -or $trimmedValue.Length -lt 2) {
            throw "Invalid single-quoted YAML scalar: $Value"
        }
        return $trimmedValue.Substring(1, $trimmedValue.Length - 2).Replace("''", "'")
    }

    if ($trimmedValue.StartsWith('"')) {
        if (-not $trimmedValue.EndsWith('"')) {
            throw "Invalid double-quoted YAML scalar: $Value"
        }
        try {
            return [string](ConvertFrom-Json -InputObject $trimmedValue)
        }
        catch {
            throw "Invalid double-quoted YAML scalar: $Value"
        }
    }

    if ($trimmedValue -match '[:#\[\]\{\},&*!|>@`]') {
        throw "Plain YAML scalar contains a reserved character and must be quoted: $Value"
    }

    return $trimmedValue
}

function ConvertTo-StrictYamlScalar {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function ConvertTo-Version {
    param([Parameter(Mandatory)][string]$Value)

    if ($Value -notmatch '^(\d+)\.(\d+)\.(\d+)\.(\d+)$') {
        throw "Version must use major.minor.patch.build, for example 1.2.0.4. Received: $Value"
    }

    return [pscustomobject]@{
        Major = [int]$Matches[1]
        Minor = [int]$Matches[2]
        Patch = [int]$Matches[3]
        Build = [int]$Matches[4]
    }
}

function ConvertTo-VersionString {
    param([Parameter(Mandatory)]$Version)
    return "$($Version.Major).$($Version.Minor).$($Version.Patch).$($Version.Build)"
}

function Get-ProjectFilePath {
    param([string]$StartPath = (Get-Location).Path)

    $directory = Resolve-FullPath -Path $StartPath
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        $directory = [System.IO.Path]::GetDirectoryName($directory)
    }

    while (-not [string]::IsNullOrWhiteSpace($directory)) {
        $candidate = Join-Path $directory $script:ProjectFileName
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }

        $parent = [System.IO.Directory]::GetParent($directory)
        if ($null -eq $parent) {
            break
        }
        $directory = $parent.FullName
    }

    throw "No $script:ProjectFileName was found in the current directory or its parents. Run: skit init"
}

function Read-Project {
    param([string]$Path = (Get-ProjectFilePath))

    $lines = [System.IO.File]::ReadAllLines($Path)
    $values = @{}
    $exclude = New-Object System.Collections.Generic.List[string]
    $currentList = $null

    for ($index = 0; $index -lt $lines.Length; $index++) {
        $lineNumber = $index + 1
        $line = $lines[$index]
        if ($line.Contains("`t")) {
            throw "$Path line ${lineNumber}: tabs are not allowed."
        }
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) {
            continue
        }

        if ($line -match '^  -\s+(.+)$') {
            if ($currentList -ne 'exclude') {
                throw "$Path line ${lineNumber}: list item is only allowed below exclude."
            }
            $exclude.Add((ConvertFrom-StrictYamlScalar -Value $Matches[1]))
            continue
        }

        if ($line.StartsWith(' ')) {
            throw "$Path line ${lineNumber}: invalid indentation. Use exactly two spaces before list items."
        }

        if ($line -notmatch '^([A-Za-z][A-Za-z0-9_-]*):(?:\s*(.*))?$') {
            throw "$Path line ${lineNumber}: invalid strict YAML syntax."
        }

        $key = $Matches[1]
        $rawValue = [string]$Matches[2]
        if ($key -notin @('name', 'exclude', 'version')) {
            throw "$Path line ${lineNumber}: unknown project key '$key'."
        }
        if ($values.ContainsKey($key)) {
            throw "$Path line ${lineNumber}: duplicate project key '$key'."
        }

        $values[$key] = $true
        $currentList = $null
        if ($key -eq 'exclude') {
            if ([string]::IsNullOrWhiteSpace($rawValue)) {
                $currentList = 'exclude'
            }
            elseif ($rawValue.Trim() -ne '[]') {
                throw "$Path line ${lineNumber}: exclude must be an indented list or []."
            }
        }
        else {
            if ([string]::IsNullOrWhiteSpace($rawValue)) {
                throw "$Path line ${lineNumber}: '$key' requires a value."
            }
            $values[$key] = ConvertFrom-StrictYamlScalar -Value $rawValue
        }
    }

    foreach ($requiredKey in @('name', 'version')) {
        if (-not $values.ContainsKey($requiredKey)) {
            throw "$Path is missing required key '$requiredKey'."
        }
    }

    $name = [string]$values.name
    if ([string]::IsNullOrWhiteSpace($name) -or
        $name.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0) {
        throw "Project name '$name' is not a valid file name."
    }

    return [pscustomobject]@{
        Path      = Resolve-FullPath -Path $Path
        Directory = [System.IO.Path]::GetDirectoryName((Resolve-FullPath -Path $Path))
        Name      = $name
        Exclude   = @($exclude)
        Version   = ConvertTo-Version -Value ([string]$values.version)
    }
}

function Set-ProjectVersion {
    param(
        [Parameter(Mandatory)]$Project,
        [Parameter(Mandatory)]$Version
    )

    $lines = [System.IO.File]::ReadAllLines($Project.Path)
    $replacement = 'version: ' + (ConvertTo-VersionString -Version $Version)
    $replaced = $false
    for ($index = 0; $index -lt $lines.Length; $index++) {
        if ($lines[$index] -match '^version:') {
            $lines[$index] = $replacement
            $replaced = $true
            break
        }
    }

    if (-not $replaced) {
        throw "Could not update version in $($Project.Path)."
    }

    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($Project.Path, $lines, $utf8WithoutBom)
}

function Get-BumpedVersion {
    param(
        [Parameter(Mandatory)]$Version,
        [Parameter(Mandatory)][ValidateSet('major', 'minor', 'patch', 'build')][string]$Part
    )

    $next = [pscustomobject]@{
        Major = [int]$Version.Major
        Minor = [int]$Version.Minor
        Patch = [int]$Version.Patch
        Build = [int]$Version.Build
    }

    switch ($Part) {
        'major' {
            $next.Major++
            $next.Minor = 0
            $next.Patch = 0
            $next.Build = 0
        }
        'minor' {
            $next.Minor++
            $next.Patch = 0
            $next.Build = 0
        }
        'patch' {
            $next.Patch++
            $next.Build = 0
        }
        'build' {
            $next.Build++
        }
    }

    return $next
}

function Invoke-VersionBump {
    param([ValidateSet('major', 'minor', 'patch', 'build')][string]$Part = 'minor')

    $project = Read-Project
    $nextVersion = Get-BumpedVersion -Version $project.Version -Part $Part
    Set-ProjectVersion -Project $project -Version $nextVersion
    Write-Success "Version: $(ConvertTo-VersionString -Version $nextVersion)"
}

function Convert-GlobToRegex {
    param([Parameter(Mandatory)][string]$Pattern)

    $normalizedPattern = $Pattern.Replace('\', '/').TrimStart('/')
    if ($normalizedPattern.EndsWith('/')) {
        $normalizedPattern += '**'
    }

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('^')
    for ($index = 0; $index -lt $normalizedPattern.Length; $index++) {
        $character = $normalizedPattern[$index]
        if ($character -eq '*') {
            if ($index + 1 -lt $normalizedPattern.Length -and $normalizedPattern[$index + 1] -eq '*') {
                $index++
                if ($index + 1 -lt $normalizedPattern.Length -and $normalizedPattern[$index + 1] -eq '/') {
                    $index++
                    [void]$builder.Append('(?:.*/)?')
                }
                else {
                    [void]$builder.Append('.*')
                }
            }
            else {
                [void]$builder.Append('[^/]*')
            }
        }
        elseif ($character -eq '?') {
            [void]$builder.Append('[^/]')
        }
        else {
            [void]$builder.Append([Regex]::Escape([string]$character))
        }
    }
    [void]$builder.Append('$')
    return $builder.ToString()
}

function Test-ProjectPathExcluded {
    param(
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][string[]]$Patterns
    )

    $normalizedPath = $RelativePath.Replace('\', '/').TrimStart('/')
    foreach ($pattern in $Patterns) {
        if ($normalizedPath -match (Convert-GlobToRegex -Pattern $pattern)) {
            return $true
        }
    }
    return $false
}

function Copy-ProjectFilesToStage {
    param(
        [Parameter(Mandatory)]$Project,
        [Parameter(Mandatory)][string]$StagePath
    )

    $patterns = @(
        $script:ProjectFileName,
        '.git/**',
        'build/**'
    ) + @($Project.Exclude)

    $files = Get-ChildItem -LiteralPath $Project.Directory -File -Recurse -Force
    $copiedCount = 0
    foreach ($file in $files) {
        $relativePath = $file.FullName.Substring($Project.Directory.Length).TrimStart('\', '/')
        if (Test-ProjectPathExcluded -RelativePath $relativePath -Patterns $patterns) {
            continue
        }

        $destination = Join-Path $StagePath $relativePath
        [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($destination)) | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
        $copiedCount++
    }

    if ($copiedCount -eq 0) {
        throw 'The project does not contain any files to pack after exclusions were applied.'
    }

    return $copiedCount
}

function Invoke-ProjectBuild {
    $project = Read-Project
    $nextVersion = Get-BumpedVersion -Version $project.Version -Part build
    $versionText = ConvertTo-VersionString -Version $nextVersion
    $buildDirectory = Join-Path $project.Directory 'build'
    $outputPath = Join-Path $buildDirectory "$($project.Name)-$versionText.pak"
    $stagePath = Join-Path ([System.IO.Path]::GetTempPath()) ('skit-build-' + [Guid]::NewGuid().ToString('N'))
    $temporaryPak = Join-Path ([System.IO.Path]::GetTempPath()) ('skit-' + [Guid]::NewGuid().ToString('N') + '.pak')

    [System.IO.Directory]::CreateDirectory($stagePath) | Out-Null
    [System.IO.Directory]::CreateDirectory($buildDirectory) | Out-Null

    try {
        $fileCount = Copy-ProjectFilesToStage -Project $project -StagePath $stagePath
        Write-Info "Packing $fileCount files..."
        $repak = Get-ToolExecutable -Tool repak
        Invoke-ExternalTool -Executable $repak -ToolArguments @(
            'pack',
            '--version', 'V11',
            $stagePath,
            $temporaryPak
        )

        Move-Item -LiteralPath $temporaryPak -Destination $outputPath -Force
        Set-ProjectVersion -Project $project -Version $nextVersion
        Write-Utf8File -Path (Join-Path $buildDirectory 'latest.txt') -Content ([System.IO.Path]::GetFileName($outputPath) + "`r`n")
        Write-Success "Built $outputPath"
        return $outputPath
    }
    finally {
        if (Test-Path -LiteralPath $stagePath) {
            Remove-Item -LiteralPath $stagePath -Recurse -Force
        }
        if (Test-Path -LiteralPath $temporaryPak) {
            Remove-Item -LiteralPath $temporaryPak -Force
        }
    }
}

function ConvertTo-NormalizedScumAesKey {
    param([AllowEmptyString()][string]$Key)

    if ([string]::IsNullOrWhiteSpace($Key)) {
        return ''
    }
    if ($Key -notmatch '^0x[0-9A-Fa-f]{64}$') {
        throw 'scumAesKey must be empty or a valid 256-bit AES key.'
    }

    return '0x' + $Key.Substring(2).ToUpperInvariant()
}

function Read-SKitConfigFile {
    param([Parameter(Mandatory)][string]$Path)

    $values = @{}
    $lines = [System.IO.File]::ReadAllLines($Path)
    for ($index = 0; $index -lt $lines.Length; $index++) {
        $line = $lines[$index]
        $lineNumber = $index + 1
        if ($line.Contains("`t")) {
            throw "$Path line ${lineNumber}: tabs are not allowed."
        }
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) {
            continue
        }
        if ($line.StartsWith(' ') -or $line -notmatch '^([A-Za-z][A-Za-z0-9_-]*):(?:\s*(.*))?$') {
            throw "$Path line ${lineNumber}: invalid strict YAML syntax."
        }

        $key = $Matches[1]
        $rawValue = [string]$Matches[2]
        if ($key -notin @('scumPath', 'scumExecutable', 'scumAesKey', 'scumStartParams')) {
            throw "$Path line ${lineNumber}: unknown configuration key '$key'."
        }
        if ($values.ContainsKey($key)) {
            throw "$Path line ${lineNumber}: duplicate configuration key '$key'."
        }
        $value = ConvertFrom-StrictYamlScalar -Value $rawValue
        if ($key -eq 'scumAesKey') {
            try {
                $value = ConvertTo-NormalizedScumAesKey -Key $value
            }
            catch {
                throw "$Path line ${lineNumber}: scumAesKey must be empty or a valid 256-bit AES key."
            }
        }
        $values[$key] = $value
    }

    return [pscustomobject]@{
        ScumPath         = if ($values.ContainsKey('scumPath')) { [string]$values.scumPath } else { '' }
        ScumExecutable   = if ($values.ContainsKey('scumExecutable')) { [string]$values.scumExecutable } else { '' }
        ScumAesKey       = if ($values.ContainsKey('scumAesKey')) { [string]$values.scumAesKey } else { '' }
        ScumStartParams  = if ($values.ContainsKey('scumStartParams')) { [string]$values.scumStartParams } else { '' }
        HasScumPath       = $values.ContainsKey('scumPath')
        HasScumExecutable = $values.ContainsKey('scumExecutable')
        HasScumAesKey     = $values.ContainsKey('scumAesKey')
        HasScumStartParams = $values.ContainsKey('scumStartParams')
    }
}

function Merge-SKitConfig {
    $mergedScumPath = ''
    $mergedScumExecutable = ''
    $mergedScumAesKey = ''
    $mergedScumStartParams = ''
    $foundConfig = $false
    $configPaths = @(
        $script:LegacyGlobalConfigPath,
        $script:PreviousGlobalConfigPath,
        $script:GlobalConfigPath
    )

    foreach ($configPath in $configPaths) {
        if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
            continue
        }
        $foundConfig = $true
        $config = Read-SKitConfigFile -Path $configPath
        if ($config.HasScumPath) {
            $mergedScumPath = $config.ScumPath
        }
        if ($config.HasScumExecutable) {
            $mergedScumExecutable = $config.ScumExecutable
        }
        if ($config.HasScumAesKey) {
            $mergedScumAesKey = $config.ScumAesKey
        }
        if ($config.HasScumStartParams) {
            $mergedScumStartParams = $config.ScumStartParams
        }
    }

    return [pscustomobject]@{
        ScumPath       = $mergedScumPath
        ScumExecutable = $mergedScumExecutable
        ScumAesKey     = $mergedScumAesKey
        ScumStartParams = $mergedScumStartParams
        FoundConfig    = $foundConfig
    }
}

function Write-SKitConfig {
    param(
        [AllowEmptyString()][string]$ScumPath = '',
        [AllowEmptyString()][string]$ScumExecutable = '',
        [AllowEmptyString()][string]$ScumAesKey = '',
        [AllowEmptyString()][string]$ScumStartParams = ''
    )

    $normalizedScumAesKey = ConvertTo-NormalizedScumAesKey -Key $ScumAesKey
    $content = @(
        '# SCUM settings used by SKit.',
        ('scumPath: ' + (ConvertTo-StrictYamlScalar -Value $ScumPath)),
        ('scumExecutable: ' + (ConvertTo-StrictYamlScalar -Value $ScumExecutable)),
        ('scumAesKey: ' + (ConvertTo-StrictYamlScalar -Value $normalizedScumAesKey)),
        ('scumStartParams: ' + (ConvertTo-StrictYamlScalar -Value $ScumStartParams))
    ) -join "`r`n"
    Write-Utf8File -Path $script:GlobalConfigPath -Content ($content + "`r`n")
}

function Initialize-SKitConfig {
    $config = Merge-SKitConfig
    Write-SKitConfig `
        -ScumPath $config.ScumPath `
        -ScumExecutable $config.ScumExecutable `
        -ScumAesKey $config.ScumAesKey `
        -ScumStartParams $config.ScumStartParams
}

function Open-SKitConfig {
    if (-not (Test-Path -LiteralPath $script:GlobalConfigPath -PathType Leaf)) {
        Initialize-SKitConfig
    }

    try {
        Start-Process -FilePath $script:GlobalConfigPath
    }
    catch {
        Start-Process -FilePath 'notepad.exe' -ArgumentList @($script:GlobalConfigPath)
    }
    Write-Success "Opened SKit configuration: $script:GlobalConfigPath"
}

function Read-SKitConfig {
    $config = Merge-SKitConfig
    if (-not $config.FoundConfig) {
        throw "SKit configuration not found: $script:GlobalConfigPath"
    }
    return [pscustomobject]@{
        ScumPath       = $config.ScumPath
        ScumExecutable = $config.ScumExecutable
        ScumAesKey     = $config.ScumAesKey
        ScumStartParams = $config.ScumStartParams
    }
}

function Set-SKitScumPath {
    param([Parameter(Mandatory)][string]$ScumPath)

    $resolvedPath = Resolve-FullPath -Path $ScumPath
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Container)) {
        throw "SCUM directory not found: $resolvedPath"
    }

    $config = Merge-SKitConfig
    Write-SKitConfig `
        -ScumPath $resolvedPath `
        -ScumAesKey $config.ScumAesKey `
        -ScumStartParams $config.ScumStartParams
    Write-Success "SCUM path configured: $resolvedPath"
}

function Set-SKitScumExecutable {
    param([Parameter(Mandatory)][string]$ExecutablePath)

    $resolvedExecutable = Resolve-FullPath -Path $ExecutablePath
    if (-not (Test-Path -LiteralPath $resolvedExecutable -PathType Leaf) -or
        -not [System.IO.Path]::GetFileName($resolvedExecutable).Equals(
            'SCUM.exe',
            [StringComparison]::OrdinalIgnoreCase
        )) {
        throw "SCUM executable not found: $resolvedExecutable"
    }

    $relativeExecutable = 'SCUM\Binaries\Win64\SCUM.exe'
    if (-not $resolvedExecutable.EndsWith($relativeExecutable, [StringComparison]::OrdinalIgnoreCase)) {
        throw "SCUM.exe is not in the expected relative path: $relativeExecutable"
    }
    $scumPath = $resolvedExecutable.Substring(0, $resolvedExecutable.Length - $relativeExecutable.Length).TrimEnd('\')

    $config = Merge-SKitConfig
    Write-SKitConfig `
        -ScumPath $scumPath `
        -ScumExecutable $resolvedExecutable `
        -ScumAesKey $config.ScumAesKey `
        -ScumStartParams $config.ScumStartParams
    Write-Success "SCUM executable configured: $resolvedExecutable"
}

function Set-SKitStartParameters {
    param([AllowEmptyString()][string]$StartParameters = '')

    $config = Merge-SKitConfig
    Write-SKitConfig `
        -ScumPath $config.ScumPath `
        -ScumExecutable $config.ScumExecutable `
        -ScumAesKey $config.ScumAesKey `
        -ScumStartParams $StartParameters

    if ([string]::IsNullOrWhiteSpace($StartParameters)) {
        Write-Success 'SCUM custom start parameters cleared.'
    }
    else {
        Write-Success "SCUM custom start parameters configured: $StartParameters"
    }
}

function Set-SKitScumAesKey {
    param([Parameter(Mandatory)][string]$Key)

    try {
        $normalizedKey = ConvertTo-NormalizedScumAesKey -Key $Key
    }
    catch {
        throw 'The SCUM AES key must contain 0x followed by 64 hexadecimal characters.'
    }
    $config = Merge-SKitConfig
    Write-SKitConfig `
        -ScumPath $config.ScumPath `
        -ScumExecutable $config.ScumExecutable `
        -ScumAesKey $normalizedKey `
        -ScumStartParams $config.ScumStartParams
    Write-Success "SCUM AES key stored in $script:GlobalConfigPath"
}

function Get-ConfiguredScumPath {
    $config = Read-SKitConfig
    if ([string]::IsNullOrWhiteSpace($config.ScumPath)) {
        throw 'SCUM path is not configured. Run: skit setup detect-path'
    }
    return Resolve-FullPath -Path $config.ScumPath
}

function Get-ConfiguredScumExecutable {
    $config = Read-SKitConfig
    if (-not [string]::IsNullOrWhiteSpace($config.ScumExecutable)) {
        $configuredExecutable = Resolve-FullPath -Path $config.ScumExecutable
        if (-not (Test-Path -LiteralPath $configuredExecutable -PathType Leaf)) {
            throw "Configured SCUM executable not found: $configuredExecutable"
        }
        return $configuredExecutable
    }

    $scumPath = Get-ConfiguredScumPath
    $candidates = @(
        (Join-Path $scumPath 'SCUM\Binaries\Win64\SCUM.exe'),
        (Join-Path $scumPath 'SCUM.exe')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }
    throw "Could not find SCUM.exe below: $scumPath"
}

function Get-ScumPaksPath {
    $scumPath = Get-ConfiguredScumPath
    $candidates = @(
        (Join-Path $scumPath 'SCUM\Content\Paks'),
        (Join-Path $scumPath 'Content\Paks')
    )
    if ([System.IO.Path]::GetFileName($scumPath).Equals('Paks', [StringComparison]::OrdinalIgnoreCase)) {
        $candidates = @($scumPath) + $candidates
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            return $candidate
        }
    }

    throw "Could not find the SCUM Paks directory below: $scumPath"
}

function Get-LatestProjectBuild {
    param([Parameter(Mandatory)]$Project)

    $buildDirectory = Join-Path $Project.Directory 'build'
    $latestFile = Join-Path $buildDirectory 'latest.txt'
    if (Test-Path -LiteralPath $latestFile -PathType Leaf) {
        $fileName = [System.IO.File]::ReadAllText($latestFile).Trim()
        if ([System.IO.Path]::GetFileName($fileName) -ne $fileName -or
            [System.IO.Path]::GetExtension($fileName) -ne '.pak') {
            throw "Invalid build/latest.txt entry: $fileName"
        }

        $candidate = Join-Path $buildDirectory $fileName
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    $latestBuild = Get-ChildItem -LiteralPath $buildDirectory -Filter '*.pak' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
    if ($null -eq $latestBuild) {
        throw 'No project build was found. Run: skit build'
    }
    return $latestBuild.FullName
}

function Install-ProjectBuild {
    $project = Read-Project
    $buildPath = Get-LatestProjectBuild -Project $project
    $modsPath = Join-Path (Get-ScumPaksPath) '~mods'
    [System.IO.Directory]::CreateDirectory($modsPath) | Out-Null

    $buildDirectory = Join-Path $project.Directory 'build'
    $installedFile = Join-Path $buildDirectory 'installed.txt'
    if (Test-Path -LiteralPath $installedFile -PathType Leaf) {
        $previousName = [System.IO.File]::ReadAllText($installedFile).Trim()
        if ([System.IO.Path]::GetFileName($previousName) -eq $previousName -and
            [System.IO.Path]::GetExtension($previousName) -eq '.pak') {
            $previousPath = Join-Path $modsPath $previousName
            if ((Test-Path -LiteralPath $previousPath -PathType Leaf) -and
                -not $previousName.Equals([System.IO.Path]::GetFileName($buildPath), [StringComparison]::OrdinalIgnoreCase)) {
                Remove-Item -LiteralPath $previousPath -Force
            }
        }
    }

    $destination = Join-Path $modsPath ([System.IO.Path]::GetFileName($buildPath))
    Copy-Item -LiteralPath $buildPath -Destination $destination -Force
    Write-Utf8File -Path $installedFile -Content ([System.IO.Path]::GetFileName($destination) + "`r`n")
    Write-Success "Installed $destination"
}

function Invoke-ProjectRelease {
    param([ValidateSet('major', 'minor')][string]$Part = 'minor')

    [void](Invoke-ProjectBuild)
    Invoke-VersionBump -Part $Part
}

function Invoke-ProjectTest {
    [void](Invoke-ProjectBuild)
    Install-ProjectBuild
}

function Find-SteamExecutable {
    $registryCandidates = @(
        @{ Path = 'HKCU:\Software\Valve\Steam'; Name = 'SteamExe' },
        @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam'; Name = 'InstallPath' },
        @{ Path = 'HKLM:\SOFTWARE\Valve\Steam'; Name = 'InstallPath' }
    )
    foreach ($candidate in $registryCandidates) {
        try {
            $registryValues = Get-ItemProperty `
                -LiteralPath $candidate.Path `
                -Name $candidate.Name `
                -ErrorAction Stop
            $propertyName = [string]$candidate.Name
            $value = $registryValues.$propertyName
            if ($candidate.Name -eq 'InstallPath') {
                $value = Join-Path $value 'steam.exe'
            }
            if (Test-Path -LiteralPath $value -PathType Leaf) {
                return $value
            }
        }
        catch {
            continue
        }
    }

    $programFilesX86 = [Environment]::GetFolderPath('ProgramFilesX86')
    if (-not [string]::IsNullOrWhiteSpace($programFilesX86)) {
        $defaultPath = Join-Path $programFilesX86 'Steam\steam.exe'
        if (Test-Path -LiteralPath $defaultPath -PathType Leaf) {
            return $defaultPath
        }
    }
    return $null
}

function Get-SteamLibraryPaths {
    $steamExecutable = Find-SteamExecutable
    if ($null -eq $steamExecutable) {
        throw 'Could not find Steam. Install Steam or configure SCUM manually.'
    }

    $steamRoot = Split-Path -Parent $steamExecutable
    $libraries = New-Object System.Collections.Generic.List[string]
    $libraries.Add($steamRoot)
    $libraryFile = Join-Path $steamRoot 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $libraryFile -PathType Leaf) {
        foreach ($line in [System.IO.File]::ReadAllLines($libraryFile)) {
            $libraryPath = $null
            if ($line -match '^\s*"\d+"\s+"([^"]+)"\s*$') {
                $libraryPath = $Matches[1]
            }
            elseif ($line -match '^\s*"path"\s+"([^"]+)"\s*$') {
                $libraryPath = $Matches[1]
            }
            if (-not [string]::IsNullOrWhiteSpace($libraryPath)) {
                $libraryPath = $libraryPath.Replace('\\', '\')
                if (-not ($libraries | Where-Object {
                            $_.Equals($libraryPath, [StringComparison]::OrdinalIgnoreCase)
                        })) {
                    $libraries.Add($libraryPath)
                }
            }
        }
    }

    return $libraries.ToArray()
}

function Find-ScumExecutable {
    $relativePath = 'steamapps\common\SCUM\SCUM\Binaries\Win64\SCUM.exe'
    foreach ($libraryPath in Get-SteamLibraryPaths) {
        $candidate = Join-Path $libraryPath $relativePath
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }
    throw "Could not find SCUM.exe in the configured Steam libraries."
}

function Find-AndConfigureScum {
    $executable = Find-ScumExecutable
    Set-SKitScumExecutable -ExecutablePath $executable
}

function Get-ScumAesKeyFromContent {
    param([Parameter(Mandatory)][string]$Content)

    $withoutTags = [regex]::Replace($Content, '<[^>]+>', ' ')
    $plainText = [System.Net.WebUtility]::HtmlDecode($withoutTags)
    $match = [regex]::Match(
        $plainText,
        '(?im)(?<![A-Za-z0-9])SCUM(?![A-Za-z0-9])\s+(0x[0-9A-F]{64})(?![0-9A-F])'
    )
    if (-not $match.Success) {
        throw 'Could not find a valid 256-bit AES key for SCUM in the downloaded page.'
    }
    return ConvertTo-NormalizedScumAesKey -Key $match.Groups[1].Value
}

function Get-ScumAesKeyFromWeb {
    try {
        $response = Invoke-WebRequest -Uri $script:ScumAesKeyUri -UseBasicParsing
    }
    catch {
        throw "Could not download the SCUM AES key page. $($_.Exception.Message)"
    }

    return Get-ScumAesKeyFromContent -Content ([string]$response.Content)
}

function Find-AndSaveScumAesKey {
    $key = Get-ScumAesKeyFromWeb
    $outputPath = Join-Path (Get-Location).Path $script:ScumAesKeyFileName
    Write-Utf8File -Path $outputPath -Content ($key + "`r`n")
    Write-Success "Saved the SCUM AES key to $outputPath"
    return $outputPath
}

function Get-FModelSettingsPath {
    $appData = [Environment]::GetFolderPath('ApplicationData')
    return Join-Path $appData 'FModel\AppSettings.json'
}

function Update-FModelScumAesKey {
    param([Parameter(Mandatory)][string]$Key)

    if (Get-Process -Name 'FModel' -ErrorAction SilentlyContinue) {
        Write-Info 'FModel is running. Close it and run skit setup get-key again to update FModel.'
        return $false
    }

    $settingsPath = Get-FModelSettingsPath
    if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
        Write-Info 'FModel settings were not found. Start FModel once, close it, and run skit setup get-key again.'
        return $false
    }

    try {
        $settings = [System.IO.File]::ReadAllText($settingsPath) | ConvertFrom-Json
    }
    catch {
        Write-Info "FModel settings could not be read; no changes were made. $($_.Exception.Message)"
        return $false
    }

    $config = Read-SKitConfig
    if ([string]::IsNullOrWhiteSpace($config.ScumPath)) {
        Write-Info 'SCUM is not configured in SKit; the FModel AES key was not updated.'
        return $false
    }
    if ($null -eq $settings.PerDirectory) {
        Write-Info 'FModel has no per-game settings; the FModel AES key was not updated.'
        return $false
    }

    $trimCharacters = [char[]]"\/"
    $normalizedScumPath = $config.ScumPath.TrimEnd($trimCharacters)
    $targetEntry = $null
    foreach ($property in $settings.PerDirectory.PSObject.Properties) {
        $entryPath = [string]$property.Name
        if ($null -ne $property.Value -and
            $null -ne $property.Value.PSObject.Properties['GameDirectory']) {
            $entryPath = [string]$property.Value.GameDirectory
        }
        if ($entryPath.TrimEnd($trimCharacters).Equals(
                $normalizedScumPath,
                [StringComparison]::OrdinalIgnoreCase
            )) {
            $targetEntry = $property.Value
            break
        }
    }
    if ($null -eq $targetEntry) {
        Write-Info 'FModel has no SCUM game entry. Select SCUM in FModel, close FModel, and run skit setup get-key again.'
        return $false
    }

    if ($null -eq $targetEntry.PSObject.Properties['AesKeys'] -or
        $null -eq $targetEntry.AesKeys) {
        $targetEntry | Add-Member -MemberType NoteProperty -Name AesKeys -Value ([pscustomobject]@{
            mainKey = $Key
            dynamicKeys = @()
        }) -Force
    }
    else {
        $targetEntry.AesKeys |
            Add-Member -MemberType NoteProperty -Name mainKey -Value $Key -Force
        if ($null -eq $targetEntry.AesKeys.PSObject.Properties['dynamicKeys']) {
            $targetEntry.AesKeys |
                Add-Member -MemberType NoteProperty -Name dynamicKeys -Value @()
        }
    }

    $backupPath = "$settingsPath.skit-backup"
    if (-not (Test-Path -LiteralPath $backupPath)) {
        Copy-Item -LiteralPath $settingsPath -Destination $backupPath
    }
    $temporaryPath = "$settingsPath.skit-$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        $updatedJson = $settings | ConvertTo-Json -Depth 100
        Write-Utf8File -Path $temporaryPath -Content ($updatedJson + "`r`n")
        [void]([System.IO.File]::ReadAllText($temporaryPath) | ConvertFrom-Json)
        Move-Item -LiteralPath $temporaryPath -Destination $settingsPath -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }

    Write-Success "Updated the SCUM AES key in FModel settings: $settingsPath"
    return $true
}

function Get-AndConfigureScumAesKey {
    $key = Get-ScumAesKeyFromWeb
    Set-SKitScumAesKey -Key $key
    [void](Update-FModelScumAesKey -Key $key)
}

function Start-Scum {
    param([ValidateSet('modded', 'default')][string]$Mode = 'modded')

    $executable = Get-ConfiguredScumExecutable
    $config = Read-SKitConfig
    $startArguments = @()
    if ($Mode -eq 'modded') {
        $startArguments += @('-fileopenlog', '-nobattleye')
    }
    if (-not [string]::IsNullOrWhiteSpace($config.ScumStartParams)) {
        $startArguments += $config.ScumStartParams
    }

    if ($startArguments.Count -gt 0) {
        Start-Process -FilePath $executable -ArgumentList $startArguments
    }
    else {
        Start-Process -FilePath $executable
    }

    if ($Mode -eq 'modded') {
        Write-Success 'Started SCUM with mod support.'
        return
    }
    Write-Success 'Started SCUM with default launch settings.'
}

function Initialize-Project {
    $directory = (Get-Location).Path
    $projectPath = Join-Path $directory $script:ProjectFileName
    if (Test-Path -LiteralPath $projectPath) {
        throw "Project file already exists: $projectPath"
    }

    $name = Split-Path -Leaf $directory
    if ([string]::IsNullOrWhiteSpace($name)) {
        throw 'Could not derive a project name from the current directory.'
    }

    $content = @(
        ('name: ' + (ConvertTo-StrictYamlScalar -Value $name)),
        'version: 0.1.0.0',
        'exclude: []'
    ) -join "`r`n"
    Write-Utf8File -Path $projectPath -Content ($content + "`r`n")
    Write-Success "Created $projectPath"
}

function Show-Help {
    @"
SCUM Mod Toolkit (SKit) $script:SKitVersion

Usage:
  skit <command> [arguments]

Setup:
  skit setup help                          Show setup commands

Files:
  skit unpack <file.pak> [output-dir] [-o|-omit-key]
                                              Unpack a .pak with repak
  skit pack <input-dir> [output.pak] [-o|-omit-key]
                                              Pack a directory as UE PAK V11
  skit tojson <file.uasset> [version] [mappings]
                                              Export as <file>.full.json
  skit fromjson <file.json> [output.uasset] [mappings]
                                              Convert JSON to .uasset

Project:
  skit init                                 Create skit.yml in the current directory
  skit build                                Build .pak and increment build version
  skit bump [major|minor|patch|build]        Increment version; default is minor
  skit release [major|minor]                 Build, then bump release; default is minor
  skit install                              Copy the latest build to SCUM\Content\Paks\~mods
  skit test                                 Build and install
  skit play [modded|default]                Start modded by default; default omits mod flags

Other:
  skit version
  skit help
"@
}

function Show-SetupHelp {
    @"
SCUM Mod Toolkit setup

Usage:
  skit setup <command> [arguments]

Commands:
  skit setup self                          Reinstall SKit and register user PATH
  skit setup register-path                 Retry user PATH registration
  skit setup uninstall [all]               Remove SKit; 'all' also removes YAML configuration
  skit setup tools [all|fmodel|repak|uassetgui]
                                              Install latest verified tools
  skit setup set-path <scum-path>          Configure the SCUM installation root
  skit setup detect-path                   Detect SCUM.exe in Steam libraries
  skit setup find-key                      Save the current SCUM AES key as a text file
  skit setup get-key                       Store the current SCUM AES key in the configuration
  skit setup open-config                   Open or create SCUM-Mod-Toolkit.yaml
  skit setup set-startparams <parameters>  Configure custom SCUM launch parameters
  skit setup help                          Show this help
"@
}

function Invoke-SKitSetupCommand {
    param([string[]]$SetupArguments = @())

    if ($SetupArguments.Count -eq 0) {
        Show-SetupHelp
        return
    }

    $setupCommand = $SetupArguments[0].ToLowerInvariant()
    switch ($setupCommand) {
        'help' {
            if ($SetupArguments.Count -ne 1) {
                throw 'Usage: skit setup help'
            }
            Show-SetupHelp
        }
        'self' {
            if ($SetupArguments.Count -ne 1) {
                throw 'Usage: skit setup self'
            }
            Install-Self
            Write-Success "SKit installed in $script:InstallRoot"
            Write-Info 'Open a new terminal if the skit command is not yet available in this one.'
        }
        'register-path' {
            if ($SetupArguments.Count -ne 1) {
                throw 'Usage: skit setup register-path'
            }
            if (Add-InstallRootToUserPath) {
                Write-Success 'The SKit directory is registered in the user PATH.'
            }
        }
        'uninstall' {
            if ($SetupArguments.Count -gt 2 -or
                ($SetupArguments.Count -eq 2 -and -not $SetupArguments[1].Equals('all', [StringComparison]::OrdinalIgnoreCase))) {
                throw 'Usage: skit setup uninstall [all]'
            }
            Uninstall-SKit -RemoveConfiguration:($SetupArguments.Count -eq 2)
        }
        'tools' {
            if ($SetupArguments.Count -gt 2) {
                throw 'Usage: skit setup tools [all|fmodel|repak|uassetgui]'
            }
            $selection = if ($SetupArguments.Count -eq 2) { $SetupArguments[1] } else { 'all' }
            Install-Tools -Selection $selection
        }
        'set-path' {
            if ($SetupArguments.Count -ne 2) {
                throw 'Usage: skit setup set-path <scum-path>'
            }
            Set-SKitScumPath -ScumPath $SetupArguments[1]
        }
        'detect-path' {
            if ($SetupArguments.Count -ne 1) {
                throw 'Usage: skit setup detect-path'
            }
            Find-AndConfigureScum
        }
        'find-key' {
            if ($SetupArguments.Count -ne 1) {
                throw 'Usage: skit setup find-key'
            }
            [void](Find-AndSaveScumAesKey)
        }
        'get-key' {
            if ($SetupArguments.Count -ne 1) {
                throw 'Usage: skit setup get-key'
            }
            Get-AndConfigureScumAesKey
        }
        'open-config' {
            if ($SetupArguments.Count -ne 1) {
                throw 'Usage: skit setup open-config'
            }
            Open-SKitConfig
        }
        'set-startparams' {
            if ($SetupArguments.Count -lt 2) {
                throw 'Usage: skit setup set-startparams <parameter-string>'
            }
            Set-SKitStartParameters -StartParameters ($SetupArguments[1..($SetupArguments.Count - 1)] -join ' ')
        }
        default {
            throw "Unknown setup command '$($SetupArguments[0])'. Run: skit setup help"
        }
    }
}

function Invoke-SKitCommand {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Ensure-SelfInstalled

        $normalizedCommand = $Command.ToLowerInvariant()
        switch ($normalizedCommand) {
            'help' {
                Show-Help
            }
            '--help' {
                Show-Help
            }
            '-h' {
                Show-Help
            }
            'version' {
                Write-Output $script:SKitVersion
            }
            '--version' {
                Write-Output $script:SKitVersion
            }
            'setup' {
                Invoke-SKitSetupCommand -SetupArguments $Arguments
            }
            'unpack' {
                $fileArguments = Split-SKitFileArguments -FileArguments $Arguments
                if ($fileArguments.Paths.Count -lt 1 -or $fileArguments.Paths.Count -gt 2) {
                    throw 'Usage: skit unpack <file.pak> [output-dir] [-o|-omit-key]'
                }
                $output = if ($fileArguments.Paths.Count -gt 1) { $fileArguments.Paths[1] } else { $null }
                Invoke-Unpack `
                    -PakPath $fileArguments.Paths[0] `
                    -OutputPath $output `
                    -OmitKey:($OmitKey -or $fileArguments.OmitKey)
            }
            'pack' {
                $fileArguments = Split-SKitFileArguments -FileArguments $Arguments
                if ($fileArguments.Paths.Count -lt 1 -or $fileArguments.Paths.Count -gt 2) {
                    throw 'Usage: skit pack <input-dir> [output.pak] [-o|-omit-key]'
                }
                $output = if ($fileArguments.Paths.Count -gt 1) { $fileArguments.Paths[1] } else { $null }
                Invoke-Pack `
                    -SourcePath $fileArguments.Paths[0] `
                    -OutputPath $output `
                    -OmitKey:($OmitKey -or $fileArguments.OmitKey)
            }
            'tojson' {
                if ($Arguments.Count -lt 1) { throw 'Usage: skit tojson <file.uasset> [engine-version] [mappings]' }
                $engineVersion = if ($Arguments.Count -gt 1) { $Arguments[1] } else { $script:DefaultEngineVersion }
                $mappings = if ($Arguments.Count -gt 2) { $Arguments[2] } else { $null }
                Convert-UAssetToJson -UAssetPath $Arguments[0] -EngineVersion $engineVersion -Mappings $mappings
            }
            'fromjson' {
                if ($Arguments.Count -lt 1) { throw 'Usage: skit fromjson <file.json> [output.uasset] [mappings]' }
                $output = if ($Arguments.Count -gt 1) { $Arguments[1] } else { $null }
                $mappings = if ($Arguments.Count -gt 2) { $Arguments[2] } else { $null }
                Convert-JsonToUAsset -JsonPath $Arguments[0] -OutputPath $output -Mappings $mappings
            }
            'init' {
                Initialize-Project
            }
            'build' {
                [void](Invoke-ProjectBuild)
            }
            'bump' {
                $part = if ($Arguments.Count -gt 0) { $Arguments[0].ToLowerInvariant() } else { 'minor' }
                Invoke-VersionBump -Part $part
            }
            'release' {
                $part = if ($Arguments.Count -gt 0) { $Arguments[0].ToLowerInvariant() } else { 'minor' }
                Invoke-ProjectRelease -Part $part
            }
            'install' {
                Install-ProjectBuild
            }
            'test' {
                Invoke-ProjectTest
            }
            'play' {
                $mode = if ($Arguments.Count -gt 0) {
                    $Arguments[0].ToLowerInvariant()
                }
                else {
                    'modded'
                }
                if ($Arguments.Count -gt 1 -or $mode -notin @('modded', 'default')) {
                    throw 'Usage: skit play [modded|default]'
                }
                Start-Scum -Mode $mode
            }
            default {
                throw "Unknown command '$Command'. Run: skit help"
            }
        }
    }
    catch {
        Write-Host "[SKit] ERROR: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# Dot-sourcing loads the functions for Pester without running installation or dispatch.
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-SKitCommand
}
