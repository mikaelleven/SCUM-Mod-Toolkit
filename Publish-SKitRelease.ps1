#Requires -Version 5.1

<#!
.SYNOPSIS
    Creates and optionally publishes a verified SKit GitHub release archive.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string]$RepositoryRoot,

    [string]$OutputDirectory,

    [switch]$Publish
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = $PSScriptRoot
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $PSScriptRoot 'release'
}

$script:SKitReleaseFiles = @(
    'SCUM-Mod-Toolkit.ps1',
    'README.md',
    'LICENSE',
    'THIRD-PARTY-NOTICES.md'
)

function Get-SKitReleaseVersion {
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $scriptPath = Join-Path $RepositoryRoot 'SCUM-Mod-Toolkit.ps1'
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        throw "SKit script was not found: $scriptPath"
    }

    $content = [System.IO.File]::ReadAllText($scriptPath)
    $match = [regex]::Match($content, '(?m)^\$script:SKitVersion\s*=\s*''(?<version>\d+\.\d+\.\d+\.\d+)''\s*$')
    if (-not $match.Success) {
        throw "Could not read a four-part SKit version from: $scriptPath"
    }

    return $match.Groups['version'].Value
}

function Assert-SKitReleaseFiles {
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    foreach ($fileName in $script:SKitReleaseFiles) {
        $path = Join-Path $RepositoryRoot $fileName
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Required release file was not found: $path"
        }
    }
}

function Get-SKitReleaseArchiveEntries {
    param([Parameter(Mandatory)][string]$ArchivePath)

    if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
        throw "Release archive was not found: $ArchivePath"
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        return @($archive.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
    }
    finally {
        $archive.Dispose()
    }
}

function Assert-SKitReleaseArchive {
    param(
        [Parameter(Mandatory)][string]$ArchivePath,
        [Parameter(Mandatory)][string]$RootDirectoryName
    )

    $expectedEntries = @($script:SKitReleaseFiles | ForEach-Object {
            "$RootDirectoryName/$_"
        } | Sort-Object)
    $actualEntries = @(Get-SKitReleaseArchiveEntries -ArchivePath $ArchivePath | Sort-Object)
    $difference = Compare-Object -ReferenceObject $expectedEntries -DifferenceObject $actualEntries
    if ($null -ne $difference) {
        $details = ($difference | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }) -join '; '
        throw "Release archive contents do not match the allowlist. $details"
    }
}

function New-SKitReleaseArchive {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$OutputDirectory
    )

    $repositoryPath = [System.IO.Path]::GetFullPath($RepositoryRoot)
    Assert-SKitReleaseFiles -RepositoryRoot $repositoryPath
    $version = Get-SKitReleaseVersion -RepositoryRoot $repositoryPath
    $rootDirectoryName = "SCUM-Mod-Toolkit-$version"
    $outputPath = [System.IO.Path]::GetFullPath($OutputDirectory)
    [System.IO.Directory]::CreateDirectory($outputPath) | Out-Null
    $archivePath = Join-Path $outputPath "$rootDirectoryName.zip"
    $stagingParent = Join-Path ([System.IO.Path]::GetTempPath()) ('skit-release-' + [Guid]::NewGuid().ToString('N'))
    $stagingRoot = Join-Path $stagingParent $rootDirectoryName

    try {
        [System.IO.Directory]::CreateDirectory($stagingRoot) | Out-Null
        foreach ($fileName in $script:SKitReleaseFiles) {
            Copy-Item `
                -LiteralPath (Join-Path $repositoryPath $fileName) `
                -Destination (Join-Path $stagingRoot $fileName) `
                -Force
        }

        Compress-Archive -LiteralPath $stagingRoot -DestinationPath $archivePath -Force
        Assert-SKitReleaseArchive -ArchivePath $archivePath -RootDirectoryName $rootDirectoryName
    }
    finally {
        if (Test-Path -LiteralPath $stagingParent -PathType Container) {
            Remove-Item -LiteralPath $stagingParent -Recurse -Force
        }
    }

    return [pscustomobject]@{
        Version     = $version
        Tag          = "v$version"
        RepositoryRoot = $repositoryPath
        ArchivePath  = $archivePath
        Published    = $false
    }
}

function Invoke-SKitReleasePublication {
    param([Parameter(Mandatory)]$Release)

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'Git is required to create and push the release tag.'
    }
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw 'GitHub CLI is required to publish a release. Install it from https://cli.github.com/.'
    }

    $status = @(& git -C $Release.RepositoryRoot status --porcelain)
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not read the Git working tree status.'
    }
    if ($status.Count -gt 0) {
        throw 'Refusing to publish from a dirty Git working tree. Commit or stash the changes first.'
    }

    $existingTag = @(& git -C $Release.RepositoryRoot tag --list $Release.Tag)
    if ($LASTEXITCODE -ne 0) {
        throw "Could not check whether tag $($Release.Tag) already exists."
    }
    if ($existingTag.Count -gt 0) {
        throw "Tag $($Release.Tag) already exists. Refusing to overwrite it."
    }

    & gh auth status | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw 'GitHub CLI is not authenticated. Run: gh auth login'
    }

    & git -C $Release.RepositoryRoot tag -a $Release.Tag -m "SKit $($Release.Version)"
    if ($LASTEXITCODE -ne 0) {
        throw "Could not create tag $($Release.Tag)."
    }
    & git -C $Release.RepositoryRoot push origin $Release.Tag
    if ($LASTEXITCODE -ne 0) {
        throw "Could not push tag $($Release.Tag)."
    }
    & gh release create $Release.Tag $Release.ArchivePath --title "SKit $($Release.Version)" --generate-notes
    if ($LASTEXITCODE -ne 0) {
        throw "Could not publish GitHub release $($Release.Tag). The tag was created and pushed."
    }

    $Release.Published = $true
    return $Release
}

if ($MyInvocation.InvocationName -ne '.') {
    $release = New-SKitReleaseArchive -RepositoryRoot $RepositoryRoot -OutputDirectory $OutputDirectory
    if ($Publish -and $PSCmdlet.ShouldProcess($release.Tag, 'Create, push, and publish GitHub release')) {
        $release = Invoke-SKitReleasePublication -Release $release
    }
    $release
}
