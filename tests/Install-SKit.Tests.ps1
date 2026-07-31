BeforeAll {
    $installerPath = Join-Path $PSScriptRoot '..\Install-SKit.ps1'
    . $installerPath
}

Describe 'SKit bootstrap installer compatibility' {
    It 'has no parser errors' {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            $installerPath,
            [ref]$tokens,
            [ref]$errors
        )

        $errors | Should -BeNullOrEmpty
    }

    It 'uses the documented GitHub API contract' {
        $headers = Get-SKitInstallerGitHubHeaders

        $headers.Accept | Should -Be 'application/vnd.github+json'
        $headers.'X-GitHub-Api-Version' | Should -Be '2026-03-10'
    }

    It 'uses the current published SKit repository' {
        $script:SKitInstallerRepository | Should -Be 'mikaelleven/SCUM-Mod-Toolkit'
    }
}

Describe 'SKit bootstrap release verification' {
    It 'selects the release archive matching the tag' {
        $release = [pscustomobject]@{
            tag_name = 'v1.2.3.4'
            assets   = @(
                [pscustomobject]@{ name = 'Source-code.zip' }
                [pscustomobject]@{ name = 'SCUM-Mod-Toolkit-1.2.3.4.zip' }
                [pscustomobject]@{ name = 'Install-SKit.ps1' }
            )
        }

        (Select-SKitInstallerReleaseAsset -Release $release).name |
            Should -Be 'SCUM-Mod-Toolkit-1.2.3.4.zip'
    }

    It 'accepts only a valid GitHub SHA-256 digest' {
        $hash = 'a' * 64
        $asset = [pscustomobject]@{
            name   = 'SCUM-Mod-Toolkit-1.2.3.4.zip'
            digest = "sha256:$hash"
        }

        Get-SKitInstallerExpectedSha256 -Asset $asset | Should -Be $hash
        {
            Get-SKitInstallerExpectedSha256 -Asset ([pscustomobject]@{
                name = 'SCUM-Mod-Toolkit-1.2.3.4.zip'
            })
        } | Should -Throw '*did not provide SHA-256 metadata*'
        {
            Get-SKitInstallerExpectedSha256 -Asset ([pscustomobject]@{
                name   = 'SCUM-Mod-Toolkit-1.2.3.4.zip'
                digest = 'md5:1234'
            })
        } | Should -Throw '*valid SHA-256 digest*'
    }

    It 'verifies downloaded bytes with the built-in SHA-256 implementation' {
        $destination = Join-Path $TestDrive 'SCUM-Mod-Toolkit-1.2.3.4.zip'
        $expectedHash = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
        $asset = [pscustomobject]@{
            name                 = 'SCUM-Mod-Toolkit-1.2.3.4.zip'
            digest               = "sha256:$expectedHash"
            size                 = 3
            browser_download_url = 'https://example.invalid/SCUM-Mod-Toolkit-1.2.3.4.zip'
        }
        Mock Invoke-WebRequest {
            [System.IO.File]::WriteAllText(
                $OutFile,
                'abc',
                [System.Text.Encoding]::ASCII
            )
        }

        Invoke-SKitInstallerVerifiedDownload -Asset $asset -Destination $destination

        (Test-Path -LiteralPath $destination -PathType Leaf) | Should -BeTrue
    }

    It 'stops when downloaded bytes do not match the digest' {
        $destination = Join-Path $TestDrive 'bad.zip'
        $asset = [pscustomobject]@{
            name                 = 'SCUM-Mod-Toolkit-1.2.3.4.zip'
            digest               = ('sha256:' + ('0' * 64))
            size                 = 3
            browser_download_url = 'https://example.invalid/SCUM-Mod-Toolkit-1.2.3.4.zip'
        }
        Mock Invoke-WebRequest {
            [System.IO.File]::WriteAllText(
                $OutFile,
                'abc',
                [System.Text.Encoding]::ASCII
            )
        }

        {
            Invoke-SKitInstallerVerifiedDownload -Asset $asset -Destination $destination
        } | Should -Throw '*SHA-256 verification failed*'
    }
}

Describe 'SKit bootstrap installation verification' {
    It 'extracts a complete release archive and starts self-installation' {
        $releaseRoot = Join-Path $TestDrive 'archive-source\SCUM-Mod-Toolkit-1.2.3.4'
        $archivePath = Join-Path $TestDrive 'SCUM-Mod-Toolkit-1.2.3.4.zip'
        $extractPath = Join-Path $TestDrive 'archive-output'
        [System.IO.Directory]::CreateDirectory($releaseRoot) | Out-Null
        [System.IO.File]::WriteAllText(
            (Join-Path $releaseRoot 'SCUM-Mod-Toolkit.ps1'),
            '# test toolkit'
        )
        [System.IO.File]::WriteAllText((Join-Path $releaseRoot 'LICENSE'), 'MIT')
        [System.IO.File]::WriteAllText(
            (Join-Path $releaseRoot 'THIRD-PARTY-NOTICES.md'),
            'Notices'
        )
        Compress-Archive `
            -LiteralPath $releaseRoot `
            -DestinationPath $archivePath
        Mock Enable-SKitInstallerProcessExecution {}
        Mock Invoke-SKitInstallerPowerShell { 0 }

        Install-SKitInstallerRelease `
            -ArchivePath $archivePath `
            -ExtractPath $extractPath

        Assert-MockCalled Invoke-SKitInstallerPowerShell -Times 1 -ParameterFilter {
            $ScriptPath -like '*SCUM-Mod-Toolkit.ps1'
        }
    }

    It 'rejects self-installation output that is not an exit code' {
        $releaseRoot = Join-Path $TestDrive 'invalid-exit-code\SCUM-Mod-Toolkit-1.2.3.4'
        $archivePath = Join-Path $TestDrive 'invalid-exit-code.zip'
        $extractPath = Join-Path $TestDrive 'invalid-exit-code-output'
        [System.IO.Directory]::CreateDirectory($releaseRoot) | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $releaseRoot 'SCUM-Mod-Toolkit.ps1'), '# test toolkit')
        [System.IO.File]::WriteAllText((Join-Path $releaseRoot 'LICENSE'), 'MIT')
        [System.IO.File]::WriteAllText((Join-Path $releaseRoot 'THIRD-PARTY-NOTICES.md'), 'Notices')
        Compress-Archive -LiteralPath $releaseRoot -DestinationPath $archivePath
        Mock Enable-SKitInstallerProcessExecution {}
        Mock Invoke-SKitInstallerPowerShell { Write-Output 'unexpected output'; return 0 }

        {
            Install-SKitInstallerRelease -ArchivePath $archivePath -ExtractPath $extractPath
        } | Should -Throw '*valid process exit code*'
    }

    It 'adds the installation directory to the current PATH only once' {
        $originalPath = $env:Path
        try {
            $installRoot = Join-Path $TestDrive 'SKit'
            $env:Path = 'C:\Windows\System32'

            Add-SKitInstallerCurrentPath -InstallRoot $installRoot
            Add-SKitInstallerCurrentPath -InstallRoot $installRoot

            @($env:Path.Split(';') | Where-Object { $_ -eq $installRoot }).Count |
                Should -Be 1
        }
        finally {
            $env:Path = $originalPath
        }
    }

    It 'requires the installed launcher and toolkit script' {
        $installRoot = Join-Path $TestDrive 'MissingSKit'
        [System.IO.Directory]::CreateDirectory($installRoot) | Out-Null

        {
            Test-SKitInstallerInstallation -InstallRoot $installRoot
        } | Should -Throw '*Missing file*'
    }
}
