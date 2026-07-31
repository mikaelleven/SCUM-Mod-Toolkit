BeforeAll {
    $releaseScriptPath = Join-Path $PSScriptRoot '..\Publish-SKitRelease.ps1'
    . $releaseScriptPath
}

Describe 'SKit release publishing' {
    It 'has no parser errors' {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            $releaseScriptPath,
            [ref]$tokens,
            [ref]$errors
        )

        $errors | Should -BeNullOrEmpty
    }

    It 'creates an allowlisted end-user release archive' {
        $repositoryRoot = Join-Path $TestDrive 'repository'
        $outputDirectory = Join-Path $TestDrive 'release'
        [void][System.IO.Directory]::CreateDirectory($repositoryRoot)
        [System.IO.File]::WriteAllText(
            (Join-Path $repositoryRoot 'SCUM-Mod-Toolkit.ps1'),
            "`$script:SKitVersion = '1.2.3.4'`r`n"
        )
        [System.IO.File]::WriteAllText((Join-Path $repositoryRoot 'README.md'), 'Guide')
        [System.IO.File]::WriteAllText((Join-Path $repositoryRoot 'LICENSE'), 'MIT')
        [System.IO.File]::WriteAllText((Join-Path $repositoryRoot 'THIRD-PARTY-NOTICES.md'), 'Notices')
        [System.IO.File]::WriteAllText((Join-Path $repositoryRoot 'Install-SKit.ps1'), 'development')
        [System.IO.File]::WriteAllText((Join-Path $repositoryRoot 'DEVELOPMENT.md'), 'development')
        [System.IO.File]::WriteAllText((Join-Path $repositoryRoot '.gitignore'), 'development')
        [void][System.IO.Directory]::CreateDirectory((Join-Path $repositoryRoot 'tests'))
        [System.IO.File]::WriteAllText((Join-Path $repositoryRoot 'tests\test.ps1'), 'development')

        $release = New-SKitReleaseArchive `
            -RepositoryRoot $repositoryRoot `
            -OutputDirectory $outputDirectory
        $entries = @(Get-SKitReleaseArchiveEntries -ArchivePath $release.ArchivePath | Sort-Object)

        $release.Version | Should -Be '1.2.3.4'
        $release.Tag | Should -Be 'v1.2.3.4'
        $entries | Should -Be @(
            'SCUM-Mod-Toolkit-1.2.3.4/LICENSE',
            'SCUM-Mod-Toolkit-1.2.3.4/README.md',
            'SCUM-Mod-Toolkit-1.2.3.4/SCUM-Mod-Toolkit.ps1',
            'SCUM-Mod-Toolkit-1.2.3.4/THIRD-PARTY-NOTICES.md'
        )
    }

    It 'refuses to package a repository missing an allowlisted file' {
        $repositoryRoot = Join-Path $TestDrive 'missing-file-repository'
        [void][System.IO.Directory]::CreateDirectory($repositoryRoot)
        [System.IO.File]::WriteAllText(
            (Join-Path $repositoryRoot 'SCUM-Mod-Toolkit.ps1'),
            "`$script:SKitVersion = '1.2.3.4'`r`n"
        )

        {
            New-SKitReleaseArchive -RepositoryRoot $repositoryRoot -OutputDirectory $TestDrive
        } | Should -Throw '*Required release file was not found*'
    }
}
