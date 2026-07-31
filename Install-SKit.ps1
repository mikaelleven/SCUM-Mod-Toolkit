#Requires -Version 5.1

<#
.SYNOPSIS
    Installs the latest verified SKit release from GitHub.

.DESCRIPTION
    This bootstrap script is intended to be invoked with:

        irm <URL> | iex

    It downloads the latest SKit release archive, requires GitHub SHA-256
    metadata, verifies the downloaded bytes, and runs SKit's self-installer.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Update this value if the published repository uses a different owner or name.
$script:SKitInstallerRepository = 'w33zl/SCUM-Mod-Toolkit'
$script:SKitInstallerGitHubApiVersion = '2026-03-10'
$script:SKitInstallerInstallRoot = Join-Path $env:LOCALAPPDATA 'Programs\SKit'

function Write-SKitInstallerInfo {
    param([Parameter(Mandatory)][string]$Message)

    Write-Host "[SKit Installer] $Message" -ForegroundColor Cyan
}

function Write-SKitInstallerSuccess {
    param([Parameter(Mandatory)][string]$Message)

    Write-Host "[SKit Installer] $Message" -ForegroundColor Green
}

function Assert-SKitInstallerWindows {
    if ($env:OS -ne 'Windows_NT') {
        throw 'SKit currently supports Windows only.'
    }
}

function Get-SKitInstallerGitHubHeaders {
    return @{
        Accept                 = 'application/vnd.github+json'
        'User-Agent'           = 'SKit-Installer'
        'X-GitHub-Api-Version' = $script:SKitInstallerGitHubApiVersion
    }
}

function Get-SKitInstallerLatestRelease {
    param([Parameter(Mandatory)][string]$Repository)

    if ($Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') {
        throw "Invalid GitHub repository '$Repository'. Expected owner/name."
    }

    $uri = "https://api.github.com/repos/$Repository/releases/latest"
    try {
        return Invoke-RestMethod `
            -Uri $uri `
            -Headers (Get-SKitInstallerGitHubHeaders) `
            -UseBasicParsing
    }
    catch {
        throw "Could not retrieve the latest SKit release from $Repository. $($_.Exception.Message)"
    }
}

function Select-SKitInstallerReleaseAsset {
    param([Parameter(Mandatory)]$Release)

    $tag = ([string]$Release.tag_name).Trim()
    $version = $tag.TrimStart('v', 'V')
    $versionedName = "SCUM-Mod-Toolkit-$version.zip"
    $unversionedName = 'SCUM-Mod-Toolkit.zip'

    $asset = @($Release.assets) |
        Where-Object {
            ([string]$_.name).Equals($versionedName, [StringComparison]::OrdinalIgnoreCase)
        } |
        Select-Object -First 1

    if ($null -eq $asset) {
        $asset = @($Release.assets) |
            Where-Object {
                ([string]$_.name).Equals($unversionedName, [StringComparison]::OrdinalIgnoreCase)
            } |
            Select-Object -First 1
    }

    if ($null -eq $asset) {
        $available = (@($Release.assets) | ForEach-Object { $_.name }) -join ', '
        throw "The latest release does not contain '$versionedName' or '$unversionedName'. Available assets: $available"
    }

    return $asset
}

function Get-SKitInstallerExpectedSha256 {
    param([Parameter(Mandatory)]$Asset)

    if ($Asset.PSObject.Properties.Name -notcontains 'digest' -or
        [string]::IsNullOrWhiteSpace([string]$Asset.digest)) {
        throw "GitHub did not provide SHA-256 metadata for release asset '$($Asset.name)'. Installation was stopped."
    }

    $digest = [string]$Asset.digest
    if ($digest -notmatch '(?i)^sha256:([0-9a-f]{64})$') {
        throw "GitHub did not provide a valid SHA-256 digest for release asset '$($Asset.name)'. Installation was stopped."
    }

    return $Matches[1].ToLowerInvariant()
}

function Get-SKitInstallerFileSha256 {
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
        return ([BitConverter]::ToString($hashBytes)).Replace('-', '').ToLowerInvariant()
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

function Invoke-SKitInstallerVerifiedDownload {
    param(
        [Parameter(Mandatory)]$Asset,
        [Parameter(Mandatory)][string]$Destination
    )

    $expectedHash = Get-SKitInstallerExpectedSha256 -Asset $Asset
    Write-SKitInstallerInfo "Downloading $($Asset.name)..."
    Invoke-WebRequest `
        -Uri $Asset.browser_download_url `
        -Headers (Get-SKitInstallerGitHubHeaders) `
        -UseBasicParsing `
        -OutFile $Destination

    if ($Asset.PSObject.Properties.Name -contains 'size' -and
        $null -ne $Asset.size -and
        [long]$Asset.size -gt 0 -and
        (Get-Item -LiteralPath $Destination).Length -ne [long]$Asset.size) {
        throw "Downloaded size does not match the GitHub release metadata for '$($Asset.name)'."
    }

    $actualHash = Get-SKitInstallerFileSha256 -Path $Destination
    if (-not $actualHash.Equals($expectedHash, [StringComparison]::OrdinalIgnoreCase)) {
        throw "SHA-256 verification failed for '$($Asset.name)'. Expected $expectedHash but got $actualHash."
    }

    Write-SKitInstallerSuccess "SHA-256 verified: $actualHash"
}

function Enable-SKitInstallerProcessExecution {
    param([Parameter(Mandatory)][string]$ScriptPath)

    try {
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction Stop
        Write-SKitInstallerInfo 'Enabled the execution-policy bypass for this PowerShell process only.'
    }
    catch {
        Write-Warning "Could not change the process execution policy. The installer will also use a one-time Bypass process. $($_.Exception.Message)"
    }

    try {
        Unblock-File -LiteralPath $ScriptPath -ErrorAction Stop
    }
    catch {
        Write-Warning "Could not remove the downloaded-file mark from '$ScriptPath'. $($_.Exception.Message)"
    }
}

function Invoke-SKitInstallerPowerShell {
    param([Parameter(Mandatory)][string]$ScriptPath)

    $powershellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $powershellPath -PathType Leaf)) {
        throw "Windows PowerShell 5.1 was not found at '$powershellPath'."
    }

    $childOutput = @(& $powershellPath `
        -NoLogo `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $ScriptPath `
        setup self)

    $exitCode = $LASTEXITCODE
    foreach ($line in $childOutput) {
        Write-Host $line
    }

    return $exitCode
}

function Install-SKitInstallerRelease {
    param(
        [Parameter(Mandatory)][string]$ArchivePath,
        [Parameter(Mandatory)][string]$ExtractPath
    )

    Expand-Archive -LiteralPath $ArchivePath -DestinationPath $ExtractPath -Force

    $scripts = @(
        Get-ChildItem `
            -LiteralPath $ExtractPath `
            -Filter 'SCUM-Mod-Toolkit.ps1' `
            -File `
            -Recurse
    )
    if ($scripts.Count -ne 1) {
        throw "The verified release archive must contain exactly one SCUM-Mod-Toolkit.ps1 file. Found $($scripts.Count)."
    }

    $releaseRoot = $scripts[0].Directory.FullName
    foreach ($requiredFile in @('LICENSE', 'THIRD-PARTY-NOTICES.md')) {
        if (-not (Test-Path -LiteralPath (Join-Path $releaseRoot $requiredFile) -PathType Leaf)) {
            throw "The verified release archive is missing '$requiredFile' beside SCUM-Mod-Toolkit.ps1."
        }
    }

    Enable-SKitInstallerProcessExecution -ScriptPath $scripts[0].FullName
    $exitCode = @(Invoke-SKitInstallerPowerShell -ScriptPath $scripts[0].FullName)
    if ($exitCode.Count -ne 1 -or $exitCode[0] -isnot [int]) {
        throw 'SKit self-installation did not return a valid process exit code.'
    }
    $exitCode = [int]$exitCode[0]
    if ($exitCode -ne 0) {
        throw "SKit self-installation failed with exit code $exitCode."
    }
}

function Add-SKitInstallerCurrentPath {
    param([Parameter(Mandatory)][string]$InstallRoot)

    $normalizedRoot = $InstallRoot.TrimEnd('\')
    $entries = @()
    if (-not [string]::IsNullOrWhiteSpace($env:Path)) {
        $entries = @($env:Path.Split(';'))
    }

    foreach ($entry in $entries) {
        if ([string]::IsNullOrWhiteSpace($entry)) {
            continue
        }

        $expandedEntry = [Environment]::ExpandEnvironmentVariables($entry).TrimEnd('\')
        if ($expandedEntry.Equals($normalizedRoot, [StringComparison]::OrdinalIgnoreCase)) {
            return
        }
    }

    if ([string]::IsNullOrWhiteSpace($env:Path)) {
        $env:Path = $InstallRoot
    }
    else {
        $env:Path = "$env:Path;$InstallRoot"
    }
    Write-SKitInstallerInfo 'Reloaded the SKit directory into PATH for the current shell.'
}

function Test-SKitInstallerInstallation {
    param([Parameter(Mandatory)][string]$InstallRoot)

    $installedScript = Join-Path $InstallRoot 'SCUM-Mod-Toolkit.ps1'
    $launcher = Join-Path $InstallRoot 'skit.cmd'
    foreach ($requiredPath in @($installedScript, $launcher)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "SKit installation verification failed. Missing file: $requiredPath"
        }
    }

    $versionOutput = @(& $launcher version 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "SKit installation verification failed because 'skit version' returned exit code $LASTEXITCODE."
    }

    $version = ($versionOutput | Select-Object -Last 1).ToString().Trim()
    if ($version -notmatch '^\d+\.\d+\.\d+\.\d+$') {
        throw "SKit installation verification returned an unexpected version: $version"
    }

    return $version
}

function Remove-SKitInstallerTemporaryDirectory {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return
    }

    $temporaryRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $leafName = [System.IO.Path]::GetFileName($fullPath)
    if (-not $fullPath.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase) -or
        $leafName -notmatch '^skit-installer-[0-9a-f]{32}$') {
        throw "Refusing to remove an unexpected temporary directory: $fullPath"
    }

    Remove-Item -LiteralPath $fullPath -Recurse -Force
}

function Invoke-SKitInstaller {
    Assert-SKitInstallerWindows
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    Write-SKitInstallerInfo "Checking the latest release in $script:SKitInstallerRepository..."
    $release = Get-SKitInstallerLatestRelease -Repository $script:SKitInstallerRepository
    $asset = Select-SKitInstallerReleaseAsset -Release $release

    $workDirectory = Join-Path `
        ([System.IO.Path]::GetTempPath()) `
        ('skit-installer-' + [Guid]::NewGuid().ToString('N'))
    $archivePath = Join-Path $workDirectory ([string]$asset.name)
    $extractPath = Join-Path $workDirectory 'release'
    [System.IO.Directory]::CreateDirectory($extractPath) | Out-Null

    try {
        Invoke-SKitInstallerVerifiedDownload -Asset $asset -Destination $archivePath
        Install-SKitInstallerRelease -ArchivePath $archivePath -ExtractPath $extractPath
        Add-SKitInstallerCurrentPath -InstallRoot $script:SKitInstallerInstallRoot
        $installedVersion = Test-SKitInstallerInstallation -InstallRoot $script:SKitInstallerInstallRoot

        $releaseVersion = ([string]$release.tag_name).Trim().TrimStart('v', 'V')
        if ($releaseVersion -match '^\d+\.\d+\.\d+\.\d+$' -and
            -not $installedVersion.Equals($releaseVersion, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Installed version $installedVersion does not match release tag $($release.tag_name)."
        }

        if ($null -eq (Get-Command skit -ErrorAction SilentlyContinue)) {
            throw 'SKit was installed, but the skit command could not be resolved after refreshing PATH.'
        }

        Write-SKitInstallerSuccess "Installation complete. SKit $installedVersion is ready."
        Write-Host ''
        Write-Host 'Verify the installation with: skit version'
        Write-Host "Expected result: the installed SKit version number ($installedVersion)."
    }
    finally {
        try {
            Remove-SKitInstallerTemporaryDirectory -Path $workDirectory
        }
        catch {
            Write-Warning "Could not remove the temporary installer directory. $($_.Exception.Message)"
        }
    }
}

# Dot-sourcing loads installer functions for Pester without downloading or installing.
if ($MyInvocation.InvocationName -ne '.') {
    try {
        Invoke-SKitInstaller
    }
    catch {
        Write-Host "[SKit Installer] ERROR: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}
