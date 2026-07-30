BeforeAll {
    $toolkitPath = Join-Path $PSScriptRoot '..\SCUM-Mod-Toolkit.ps1'
    . $toolkitPath
}

Describe 'PowerShell compatibility' {
    It 'has no parser errors' {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            $toolkitPath,
            [ref]$tokens,
            [ref]$errors
        )

        $errors | Should -BeNullOrEmpty
    }
}

Describe 'Version handling' {
    It 'parses and formats a four-part version' {
        $version = ConvertTo-Version -Value '1.2.3.4'

        $version.Major | Should -Be 1
        $version.Minor | Should -Be 2
        $version.Patch | Should -Be 3
        $version.Build | Should -Be 4
        (ConvertTo-VersionString -Version $version) | Should -Be '1.2.3.4'
    }

    It 'rejects versions that do not have four numeric parts' {
        { ConvertTo-Version -Value '1.2.3' } | Should -Throw
        { ConvertTo-Version -Value '1.2.x.4' } | Should -Throw
        { ConvertTo-Version -Value '-1.2.3.4' } | Should -Throw
    }

    It 'bumps <Part> from 1.2.3.4 to <Expected>' -ForEach @(
        @{ Part = 'major'; Expected = '2.0.0.0' }
        @{ Part = 'minor'; Expected = '1.3.0.0' }
        @{ Part = 'patch'; Expected = '1.2.4.0' }
        @{ Part = 'build'; Expected = '1.2.3.5' }
    ) {
        $current = ConvertTo-Version -Value '1.2.3.4'
        $next = Get-BumpedVersion -Version $current -Part $Part

        (ConvertTo-VersionString -Version $next) | Should -Be $Expected
    }

    It 'builds before performing the release bump' {
        $script:releaseCallOrder = @()
        Mock Invoke-ProjectBuild {
            $script:releaseCallOrder += 'build'
            return 'C:\temp\MyMod-1.2.3.5.pak'
        }
        Mock Invoke-VersionBump {
            param($Part)
            $script:releaseCallOrder += "bump:$Part"
        }

        Invoke-ProjectRelease -Part minor

        $script:releaseCallOrder.Count | Should -Be 2
        $script:releaseCallOrder[0] | Should -Be 'build'
        $script:releaseCallOrder[1] | Should -Be 'bump:minor'
    }
}

Describe 'Strict project YAML' {
    It 'reads a valid project with exclusions' {
        $projectPath = Join-Path $TestDrive 'skit.yml'
        @"
name: 'My Mod'
version: 1.2.3.4
exclude:
  - 'docs/**'
  - '**/*.bak'
"@ | Set-Content -LiteralPath $projectPath -Encoding UTF8

        $project = Read-Project -Path $projectPath

        $project.Name | Should -Be 'My Mod'
        (ConvertTo-VersionString -Version $project.Version) | Should -Be '1.2.3.4'
        $project.Exclude.Count | Should -Be 2
        $project.Exclude[0] | Should -Be 'docs/**'
        $project.Exclude[1] | Should -Be '**/*.bak'
    }

    It 'allows exclude to be omitted' {
        $projectPath = Join-Path $TestDrive 'skit.yml'
        @"
name: 'MyMod'
version: 0.1.0.0
"@ | Set-Content -LiteralPath $projectPath -Encoding UTF8

        $project = Read-Project -Path $projectPath

        $project.Exclude | Should -BeNullOrEmpty
    }

    It 'rejects an unknown key' {
        $projectPath = Join-Path $TestDrive 'skit.yml'
        @"
name: 'MyMod'
version: 0.1.0.0
description: 'Not allowed'
"@ | Set-Content -LiteralPath $projectPath -Encoding UTF8

        { Read-Project -Path $projectPath } | Should -Throw '*unknown project key*'
    }

    It 'rejects duplicate keys' {
        $projectPath = Join-Path $TestDrive 'skit.yml'
        @"
name: 'MyMod'
name: 'OtherMod'
version: 0.1.0.0
"@ | Set-Content -LiteralPath $projectPath -Encoding UTF8

        { Read-Project -Path $projectPath } | Should -Throw '*duplicate project key*'
    }

    It 'rejects tabs' {
        $projectPath = Join-Path $TestDrive 'skit.yml'
        $content = "name: 'MyMod'`r`nversion: 0.1.0.0`r`nexclude:`r`n`t- '*.bak'`r`n"
        [System.IO.File]::WriteAllText($projectPath, $content)

        { Read-Project -Path $projectPath } | Should -Throw '*tabs are not allowed*'
    }

    It 'rejects unsupported inline lists' {
        $projectPath = Join-Path $TestDrive 'skit.yml'
        @"
name: 'MyMod'
version: 0.1.0.0
exclude: ['*.bak']
"@ | Set-Content -LiteralPath $projectPath -Encoding UTF8

        { Read-Project -Path $projectPath } |
            Should -Throw '*exclude must be an indented list*'
    }

    It 'updates only the version line' {
        $projectPath = Join-Path $TestDrive 'skit.yml'
        @"
# Keep this comment
name: 'MyMod'
version: 0.1.0.9
exclude:
  - 'docs/**'
"@ | Set-Content -LiteralPath $projectPath -Encoding UTF8
        $project = Read-Project -Path $projectPath
        $next = Get-BumpedVersion -Version $project.Version -Part minor

        Set-ProjectVersion -Project $project -Version $next
        $updatedLines = [System.IO.File]::ReadAllLines($projectPath)

        $updatedLines | Should -Contain '# Keep this comment'
        $updatedLines | Should -Contain 'version: 0.2.0.0'
        $updatedLines | Should -Contain "  - 'docs/**'"
    }
}

Describe 'Project exclusion patterns' {
    It 'matches <Path> against <Pattern> as <Expected>' -ForEach @(
        @{ Path = 'README.md'; Pattern = 'README.md'; Expected = $true }
        @{ Path = 'docs/guide.md'; Pattern = 'docs/**'; Expected = $true }
        @{ Path = 'a/b/file.bak'; Pattern = '**/*.bak'; Expected = $true }
        @{ Path = 'file.bak'; Pattern = '**/*.bak'; Expected = $true }
        @{ Path = 'src/a.txt'; Pattern = 'src/?.txt'; Expected = $true }
        @{ Path = 'src/nested/a.txt'; Pattern = 'src/*.txt'; Expected = $false }
        @{ Path = 'content/file.txt'; Pattern = 'docs/**'; Expected = $false }
    ) {
        Test-ProjectPathExcluded -RelativePath $Path -Patterns @($Pattern) |
            Should -Be $Expected
    }

    It 'omits built-in and project-specific exclusions from staging' {
        $projectRoot = Join-Path $TestDrive 'project'
        $stageRoot = Join-Path $TestDrive 'stage'
        [void][System.IO.Directory]::CreateDirectory((Join-Path $projectRoot '.git'))
        [void][System.IO.Directory]::CreateDirectory((Join-Path $projectRoot 'build'))
        [void][System.IO.Directory]::CreateDirectory((Join-Path $projectRoot 'docs'))
        [void][System.IO.Directory]::CreateDirectory((Join-Path $projectRoot 'Content'))
        [void][System.IO.Directory]::CreateDirectory($stageRoot)
        [System.IO.File]::WriteAllText((Join-Path $projectRoot 'skit.yml'), 'project')
        [System.IO.File]::WriteAllText((Join-Path $projectRoot '.git\config'), 'git')
        [System.IO.File]::WriteAllText((Join-Path $projectRoot 'build\old.pak'), 'old')
        [System.IO.File]::WriteAllText((Join-Path $projectRoot 'docs\guide.md'), 'docs')
        [System.IO.File]::WriteAllText((Join-Path $projectRoot 'Content\asset.uasset'), 'asset')
        $project = [pscustomobject]@{
            Directory = $projectRoot
            Exclude = @('docs/**')
        }

        $count = Copy-ProjectFilesToStage -Project $project -StagePath $stageRoot

        $count | Should -Be 1
        (Test-Path -LiteralPath (Join-Path $stageRoot 'Content\asset.uasset')) | Should -BeTrue
        (Test-Path -LiteralPath (Join-Path $stageRoot 'docs\guide.md')) | Should -BeFalse
        (Test-Path -LiteralPath (Join-Path $stageRoot 'build\old.pak')) | Should -BeFalse
    }
}

Describe 'Release asset verification' {
    It 'uses the current versioned GitHub API contract' {
        $headers = Get-GitHubHeaders

        $headers.Accept | Should -Be 'application/vnd.github+json'
        $headers.'X-GitHub-Api-Version' | Should -Be '2026-03-10'
    }

    It 'accepts a valid GitHub SHA-256 digest' {
        $hash = 'a' * 64
        $asset = [pscustomobject]@{
            name = 'tool.zip'
            digest = "sha256:$hash"
        }

        Get-ExpectedSha256 -Asset $asset | Should -Be $hash
    }

    It 'calculates SHA-256 without the Get-FileHash cmdlet' {
        $path = Join-Path $TestDrive 'hash-test.txt'
        [System.IO.File]::WriteAllText($path, 'abc', [System.Text.Encoding]::ASCII)

        Get-FileSha256 -Path $path |
            Should -Be 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
    }

    It 'verifies a downloaded file with the built-in SHA-256 implementation' {
        $destination = Join-Path $TestDrive 'downloaded-tool.zip'
        $expectedHash = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
        $asset = [pscustomobject]@{
            name = 'tool.zip'
            digest = "sha256:$expectedHash"
            size = 3
            browser_download_url = 'https://example.invalid/tool.zip'
        }
        Mock Invoke-WebRequest {
            [System.IO.File]::WriteAllText(
                $OutFile,
                'abc',
                [System.Text.Encoding]::ASCII
            )
        }

        Invoke-VerifiedDownload -Asset $asset -Destination $destination

        (Test-Path -LiteralPath $destination -PathType Leaf) | Should -BeTrue
    }

    It 'rejects missing or malformed GitHub digests' {
        { Get-ExpectedSha256 -Asset ([pscustomobject]@{ name = 'tool.zip' }) } |
            Should -Throw '*did not provide SHA-256 metadata*'
        {
            Get-ExpectedSha256 -Asset ([pscustomobject]@{
                name = 'tool.zip'
                digest = 'md5:1234'
            })
        } | Should -Throw '*valid SHA-256 digest*'
    }

    It 'selects the preferred Windows repak archive' {
        $release = [pscustomobject]@{
            assets = @(
                [pscustomobject]@{ name = 'repak-source.zip' }
                [pscustomobject]@{ name = 'repak-x86_64-unknown-linux.zip' }
                [pscustomobject]@{ name = 'repak-x86_64-pc-windows-msvc.zip' }
            )
        }

        $selected = Select-ReleaseAsset -Release $release -Tool repak

        $selected.name | Should -Be 'repak-x86_64-pc-windows-msvc.zip'
    }
}

Describe 'External tool execution' {
    It 'does not fail when an invoked command does not set LASTEXITCODE' {
        $testScript = Join-Path $TestDrive 'success.ps1'
        [System.IO.File]::WriteAllText($testScript, "Write-Output 'completed'`r`n")
        Remove-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue

        { Invoke-ExternalTool -Executable $testScript -ToolArguments @('ignored') } |
            Should -Not -Throw
    }

    It 'throws when an external process returns a nonzero exit code' {
        $commandProcessor = Join-Path $env:SystemRoot 'System32\cmd.exe'

        { Invoke-ExternalTool -Executable $commandProcessor -ToolArguments @('/c', 'exit', '7') } |
            Should -Throw '*exited with code 7*'
    }
}

Describe 'External command contracts' {
    BeforeEach {
        $script:testAesKey = '0x0B1F4E543FB798EFC5BD861BB405BE7081CD03698EA9BA06469462A3B113CA81'
        Mock Get-ToolExecutable { 'C:\Tools\mock.exe' }
        Mock Invoke-ExternalTool {}
        Mock Get-RepakAesArguments {
            if ($OmitKey) {
                return @()
            }
            return @('--aes-key', $script:testAesKey)
        }
    }

    It 'uses the configured AES key and PAK V11 when packing' {
        $source = Join-Path $TestDrive 'input'
        [void][System.IO.Directory]::CreateDirectory($source)
        $output = Join-Path $TestDrive 'output.pak'

        Invoke-Pack -SourcePath $source -OutputPath $output

        Assert-MockCalled Invoke-ExternalTool -Times 1 -ParameterFilter {
            $Executable -eq 'C:\Tools\mock.exe' -and
            $ToolArguments[0] -eq '--aes-key' -and
            $ToolArguments[1] -eq $script:testAesKey -and
            $ToolArguments[2] -eq 'pack' -and
            $ToolArguments[3] -eq '--version' -and
            $ToolArguments[4] -eq 'V11' -and
            $ToolArguments[5] -eq $source -and
            $ToolArguments[6] -eq $output
        }
    }

    It 'uses the configured AES key and an explicit output directory when unpacking' {
        $pak = Join-Path $TestDrive 'input.pak'
        [System.IO.File]::WriteAllText($pak, 'pak')
        $output = Join-Path $TestDrive 'unpacked'

        Invoke-Unpack -PakPath $pak -OutputPath $output

        Assert-MockCalled Invoke-ExternalTool -Times 1 -ParameterFilter {
            $ToolArguments -join '|' -eq "--aes-key|$script:testAesKey|unpack|--output|$output|$pak"
        }
    }

    It 'omits the AES key from pack when requested' {
        $source = Join-Path $TestDrive 'input'
        [void][System.IO.Directory]::CreateDirectory($source)
        $output = Join-Path $TestDrive 'output.pak'

        Invoke-Pack -SourcePath $source -OutputPath $output -OmitKey

        Assert-MockCalled Invoke-ExternalTool -Times 1 -ParameterFilter {
            $ToolArguments -join '|' -eq "pack|--version|V11|$source|$output"
        }
    }

    It 'omits the AES key from unpack when requested' {
        $pak = Join-Path $TestDrive 'input.pak'
        [System.IO.File]::WriteAllText($pak, 'pak')
        $output = Join-Path $TestDrive 'unpacked'

        Invoke-Unpack -PakPath $pak -OutputPath $output -OmitKey

        Assert-MockCalled Invoke-ExternalTool -Times 1 -ParameterFilter {
            $ToolArguments -join '|' -eq "unpack|--output|$output|$pak"
        }
    }

    It 'recognizes both omit-key CLI aliases in any position' {
        $short = Split-SKitFileArguments -FileArguments @('-o', 'input', 'output')
        $long = Split-SKitFileArguments -FileArguments @('input', '-omit-key')

        $short.OmitKey | Should -BeTrue
        $short.Paths -join '|' | Should -Be 'input|output'
        $long.OmitKey | Should -BeTrue
        $long.Paths -join '|' | Should -Be 'input'
    }

    It 'exports UAsset JSON with VER_UE4_27 by default' {
        $asset = Join-Path $TestDrive 'Asset.uasset'
        [System.IO.File]::WriteAllText($asset, 'asset')
        $expectedJson = Join-Path $TestDrive 'Asset.full.json'

        Convert-UAssetToJson -UAssetPath $asset

        Assert-MockCalled Invoke-ExternalTool -Times 1 -ParameterFilter {
            $ToolArguments -join '|' -eq "tojson|$asset|$expectedJson|VER_UE4_27"
        }
    }

    It 'converts a full JSON filename back to UAsset' {
        $json = Join-Path $TestDrive 'Asset.full.json'
        [System.IO.File]::WriteAllText($json, '{}')
        $expectedAsset = Join-Path $TestDrive 'Asset.uasset'

        Convert-JsonToUAsset -JsonPath $json

        Assert-MockCalled Invoke-ExternalTool -Times 1 -ParameterFilter {
            $ToolArguments -join '|' -eq "fromjson|$json|$expectedAsset"
        }
    }
}

Describe 'Global SKit configuration' {
    BeforeEach {
        $script:originalInstallRoot = $script:InstallRoot
        $script:originalToolsRoot = $script:ToolsRoot
        $script:originalGlobalConfigPath = $script:GlobalConfigPath
        $script:originalPreviousGlobalConfigPath = $script:PreviousGlobalConfigPath
        $script:originalLegacyGlobalConfigPath = $script:LegacyGlobalConfigPath

        $script:InstallRoot = Join-Path $TestDrive 'SKit'
        $script:ToolsRoot = Join-Path $script:InstallRoot 'tools'
        $script:GlobalConfigPath = Join-Path $script:InstallRoot 'SCUM-Mod-Toolkit.yaml'
        $script:PreviousGlobalConfigPath = Join-Path $script:InstallRoot 'SKit.yaml'
        $script:LegacyGlobalConfigPath = Join-Path $script:InstallRoot 'skit.config.yml'
        [void][System.IO.Directory]::CreateDirectory($script:InstallRoot)
    }

    AfterEach {
        $script:InstallRoot = $script:originalInstallRoot
        $script:ToolsRoot = $script:originalToolsRoot
        $script:GlobalConfigPath = $script:originalGlobalConfigPath
        $script:PreviousGlobalConfigPath = $script:originalPreviousGlobalConfigPath
        $script:LegacyGlobalConfigPath = $script:originalLegacyGlobalConfigPath
    }

    It 'reads the legacy configuration when the current file does not exist' {
        [System.IO.File]::WriteAllText(
            $script:LegacyGlobalConfigPath,
            "scumPath: 'C:\Games\SCUM'`r`n"
        )

        $config = Read-SKitConfig

        $config.ScumPath | Should -Be 'C:\Games\SCUM'
        $config.ScumExecutable | Should -Be ''
    }

    It 'merges legacy configuration files into SCUM-Mod-Toolkit.yaml' {
        [System.IO.File]::WriteAllText(
            $script:LegacyGlobalConfigPath,
            "scumPath: 'C:\Legacy\SCUM'`r`nscumExecutable: 'C:\Legacy\SCUM.exe'`r`n"
        )
        [System.IO.File]::WriteAllText(
            $script:PreviousGlobalConfigPath,
            "scumExecutable: 'D:\Steam\SCUM.exe'`r`n"
        )

        Initialize-SKitConfig
        $config = Read-SKitConfigFile -Path $script:GlobalConfigPath

        $config.ScumPath | Should -Be 'C:\Legacy\SCUM'
        $config.ScumExecutable | Should -Be 'D:\Steam\SCUM.exe'
    }

    It 'uses the current configuration value when the same key exists in every file' {
        [System.IO.File]::WriteAllText(
            $script:LegacyGlobalConfigPath,
            "scumPath: 'C:\Legacy'`r`n"
        )
        [System.IO.File]::WriteAllText(
            $script:PreviousGlobalConfigPath,
            "scumPath: 'C:\Previous'`r`n"
        )
        [System.IO.File]::WriteAllText(
            $script:GlobalConfigPath,
            "scumPath: 'C:\Current'`r`n"
        )

        (Read-SKitConfig).ScumPath | Should -Be 'C:\Current'
    }

    It 'merges and reads AES key and custom start parameters' {
        $expectedKey = '0x0B1F4E543FB798EFC5BD861BB405BE7081CD03698EA9BA06469462A3B113CA81'
        [System.IO.File]::WriteAllText(
            $script:LegacyGlobalConfigPath,
            "scumAesKey: '$expectedKey'`r`nscumStartParams: '-windowed'`r`n"
        )
        [System.IO.File]::WriteAllText(
            $script:GlobalConfigPath,
            "scumStartParams: '-windowed -ResX=1920'`r`n"
        )

        $config = Read-SKitConfig

        $config.ScumAesKey | Should -Be $expectedKey
        $config.ScumStartParams | Should -Be '-windowed -ResX=1920'
    }

    It 'rejects an invalid configured AES key' {
        [System.IO.File]::WriteAllText(
            $script:GlobalConfigPath,
            "scumAesKey: '0x1234'`r`n"
        )

        { Read-SKitConfig } | Should -Throw '*valid 256-bit AES key*'
    }

    It 'stores custom start parameters without changing other settings' {
        $expectedKey = '0x0B1F4E543FB798EFC5BD861BB405BE7081CD03698EA9BA06469462A3B113CA81'
        Write-SKitConfig -ScumPath 'C:\Games\SCUM' -ScumAesKey $expectedKey

        Set-SKitStartParameters -StartParameters '-windowed -ResX=1920'
        $config = Read-SKitConfig

        $config.ScumPath | Should -Be 'C:\Games\SCUM'
        $config.ScumAesKey | Should -Be $expectedKey
        $config.ScumStartParams | Should -Be '-windowed -ResX=1920'
    }

    It 'provides the configured AES key to repak unless omitted' {
        $expectedKey = '0x0B1F4E543FB798EFC5BD861BB405BE7081CD03698EA9BA06469462A3B113CA81'
        Write-SKitConfig -ScumAesKey $expectedKey

        @(Get-RepakAesArguments) -join '|' |
            Should -BeExactly "--aes-key|$expectedKey"
        @(Get-RepakAesArguments -OmitKey).Count | Should -Be 0
    }

    It 'normalizes an uppercase AES prefix before passing the key to repak' {
        $storedKey = '0X0b1f4e543fb798efc5bd861bb405be7081cd03698ea9ba06469462a3b113ca81'
        $expectedKey = '0x0B1F4E543FB798EFC5BD861BB405BE7081CD03698EA9BA06469462A3B113CA81'
        [System.IO.File]::WriteAllText(
            $script:GlobalConfigPath,
            "scumAesKey: '$storedKey'`r`n"
        )

        (Read-SKitConfig).ScumAesKey | Should -BeExactly $expectedKey
        @(Get-RepakAesArguments) -join '|' |
            Should -BeExactly "--aes-key|$expectedKey"
    }

    It 'stores the detected executable and installation root in SCUM-Mod-Toolkit.yaml' {
        $scumRoot = Join-Path $TestDrive 'SteamLibrary\steamapps\common\SCUM'
        $executable = Join-Path $scumRoot 'SCUM\Binaries\Win64\SCUM.exe'
        [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $executable))
        [System.IO.File]::WriteAllText($executable, 'exe')

        Set-SKitScumExecutable -ExecutablePath $executable
        $config = Read-SKitConfig

        $config.ScumPath | Should -Be $scumRoot
        $config.ScumExecutable | Should -Be $executable
        (Test-Path -LiteralPath $script:GlobalConfigPath -PathType Leaf) | Should -BeTrue
    }

    It 'suggests automatic detection when the SCUM path is empty' {
        Write-SKitConfig

        { Get-ConfiguredScumPath } |
            Should -Throw '*Run: skit setup detect-path*'
    }

    It 'creates and opens the global configuration' {
        Mock Start-Process {}

        Open-SKitConfig

        (Test-Path -LiteralPath $script:GlobalConfigPath -PathType Leaf) |
            Should -BeTrue
        Assert-MockCalled Start-Process -Times 1 -ParameterFilter {
            $FilePath -eq $script:GlobalConfigPath
        }
    }

    It 'falls back to Notepad when the YAML association cannot be opened' {
        Write-SKitConfig
        Mock Start-Process {
            if ($FilePath -ne 'notepad.exe') {
                throw 'No YAML file association'
            }
        }

        Open-SKitConfig

        Assert-MockCalled Start-Process -Times 1 -ParameterFilter {
            $FilePath -eq 'notepad.exe' -and
            $ArgumentList[0] -eq $script:GlobalConfigPath
        }
    }

    It 'installs the renamed script and removes the legacy installed script' {
        $legacyInstalledScript = Join-Path $script:InstallRoot 'skit.ps1'
        [System.IO.File]::WriteAllText($legacyInstalledScript, 'legacy')
        Mock Add-InstallRootToUserPath {}

        Install-Self

        (Test-Path -LiteralPath (Join-Path $script:InstallRoot 'SCUM-Mod-Toolkit.ps1')) |
            Should -BeTrue
        (Test-Path -LiteralPath $legacyInstalledScript) | Should -BeFalse
        [System.IO.File]::ReadAllText((Join-Path $script:InstallRoot 'skit.cmd')) |
            Should -Match 'SCUM-Mod-Toolkit\.ps1'
    }
}

Describe 'Setup command dispatch' {
    BeforeEach {
        Mock Install-Self {}
        Mock Install-Tools {}
        Mock Set-SKitScumPath {}
        Mock Find-AndConfigureScum {}
        Mock Find-AndSaveScumAesKey { 'C:\Temp\SCUM-AES-Key.txt' }
        Mock Get-AndConfigureScumAesKey {}
        Mock Open-SKitConfig {}
        Mock Set-SKitStartParameters {}
    }

    It 'shows dedicated setup help' {
        $help = Invoke-SKitSetupCommand -SetupArguments @('help') | Out-String

        $help | Should -Match 'skit setup open-config'
        $help | Should -Match 'skit setup detect-path'
    }

    It 'installs all tools by default' {
        Invoke-SKitSetupCommand -SetupArguments @('tools')

        Assert-MockCalled Install-Tools -Times 1 -ParameterFilter {
            $Selection -eq 'all'
        }
    }

    It 'dispatches a selected tool' {
        Invoke-SKitSetupCommand -SetupArguments @('tools', 'repak')

        Assert-MockCalled Install-Tools -Times 1 -ParameterFilter {
            $Selection -eq 'repak'
        }
    }

    It 'dispatches set-path with the complete path argument' {
        Invoke-SKitSetupCommand -SetupArguments @('set-path', 'D:\Steam Library\SCUM')

        Assert-MockCalled Set-SKitScumPath -Times 1 -ParameterFilter {
            $ScumPath -eq 'D:\Steam Library\SCUM'
        }
    }

    It 'dispatches setup commands without legacy command names' {
        Invoke-SKitSetupCommand -SetupArguments @('detect-path')
        Invoke-SKitSetupCommand -SetupArguments @('find-key')
        Invoke-SKitSetupCommand -SetupArguments @('get-key')
        Invoke-SKitSetupCommand -SetupArguments @('open-config')

        Assert-MockCalled Find-AndConfigureScum -Times 1
        Assert-MockCalled Find-AndSaveScumAesKey -Times 1
        Assert-MockCalled Get-AndConfigureScumAesKey -Times 1
        Assert-MockCalled Open-SKitConfig -Times 1
    }

    It 'dispatches the complete custom start parameter string' {
        Invoke-SKitSetupCommand -SetupArguments @(
            'set-startparams',
            '-windowed',
            '-ResX=1920'
        )

        Assert-MockCalled Set-SKitStartParameters -Times 1 -ParameterFilter {
            $StartParameters -eq '-windowed -ResX=1920'
        }
    }

    It 'rejects an unknown setup command' {
        { Invoke-SKitSetupCommand -SetupArguments @('detect-scum') } |
            Should -Throw '*Run: skit setup help*'
    }
}

Describe 'SCUM discovery' {
    It 'finds SCUM.exe in a Steam library from libraryfolders.vdf' {
        $steamRoot = Join-Path $TestDrive 'Steam'
        $libraryRoot = Join-Path $TestDrive 'SteamLibrary'
        $steamExecutable = Join-Path $steamRoot 'steam.exe'
        $libraryFile = Join-Path $steamRoot 'steamapps\libraryfolders.vdf'
        $scumExecutable = Join-Path $libraryRoot 'steamapps\common\SCUM\SCUM\Binaries\Win64\SCUM.exe'
        [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $libraryFile))
        [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $scumExecutable))
        [System.IO.File]::WriteAllText($steamExecutable, 'steam')
        [System.IO.File]::WriteAllText($scumExecutable, 'scum')
        $escapedLibraryRoot = $libraryRoot.Replace('\', '\\')
        [System.IO.File]::WriteAllText(
            $libraryFile,
            "`"libraryfolders`"`r`n{`r`n    `"1`"`r`n    {`r`n        `"path`" `"$escapedLibraryRoot`"`r`n    }`r`n}`r`n"
        )
        Mock Find-SteamExecutable { $steamExecutable }

        Find-ScumExecutable | Should -Be $scumExecutable
    }
}

Describe 'SCUM AES key discovery' {
    BeforeEach {
        $script:originalInstallRoot = $script:InstallRoot
        $script:originalToolsRoot = $script:ToolsRoot
        $script:originalGlobalConfigPath = $script:GlobalConfigPath
        $script:originalPreviousGlobalConfigPath = $script:PreviousGlobalConfigPath
        $script:originalLegacyGlobalConfigPath = $script:LegacyGlobalConfigPath
        $script:InstallRoot = Join-Path $TestDrive 'SKit'
        $script:ToolsRoot = Join-Path $script:InstallRoot 'tools'
        $script:GlobalConfigPath = Join-Path $script:InstallRoot 'SCUM-Mod-Toolkit.yaml'
        $script:PreviousGlobalConfigPath = Join-Path $script:InstallRoot 'SKit.yaml'
        $script:LegacyGlobalConfigPath = Join-Path $script:InstallRoot 'skit.config.yml'
        [void][System.IO.Directory]::CreateDirectory($script:InstallRoot)
        Push-Location $TestDrive
    }

    AfterEach {
        Pop-Location
        $script:InstallRoot = $script:originalInstallRoot
        $script:ToolsRoot = $script:originalToolsRoot
        $script:GlobalConfigPath = $script:originalGlobalConfigPath
        $script:PreviousGlobalConfigPath = $script:originalPreviousGlobalConfigPath
        $script:LegacyGlobalConfigPath = $script:originalLegacyGlobalConfigPath
    }

    It 'finds the key by game name instead of line number' {
        $expectedKey = '0x0B1F4E543FB798EFC5BD861BB405BE7081CD03698EA9BA06469462A3B113CA81'
        $content = @"
<div>Another Game 0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA</div>
<p><strong>SCUM</strong>&nbsp;&nbsp; $expectedKey</p>
"@

        Get-ScumAesKeyFromContent -Content $content | Should -BeExactly $expectedKey
    }

    It 'downloads and saves only the SCUM AES key' {
        $expectedKey = '0x0B1F4E543FB798EFC5BD861BB405BE7081CD03698EA9BA06469462A3B113CA81'
        Mock Invoke-WebRequest {
            [pscustomobject]@{ Content = "<p>598. <b>SCUM</b> $expectedKey</p>" }
        }

        $savedPath = Find-AndSaveScumAesKey

        $savedPath | Should -Be (Join-Path $TestDrive 'SCUM-AES-Key.txt')
        [System.IO.File]::ReadAllText($savedPath).Trim() | Should -Be $expectedKey
    }

    It 'stores the downloaded key in the global configuration' {
        $expectedKey = '0x0B1F4E543FB798EFC5BD861BB405BE7081CD03698EA9BA06469462A3B113CA81'
        Write-SKitConfig -ScumPath 'C:\Games\SCUM'
        Mock Get-ScumAesKeyFromWeb { $expectedKey }
        Mock Update-FModelScumAesKey { $false }

        Get-AndConfigureScumAesKey

        (Read-SKitConfig).ScumAesKey | Should -Be $expectedKey
        Assert-MockCalled Update-FModelScumAesKey -Times 1 -ParameterFilter {
            $Key -eq $expectedKey
        }
    }

    It 'updates an existing SCUM entry in FModel settings' {
        $expectedKey = '0x0B1F4E543FB798EFC5BD861BB405BE7081CD03698EA9BA06469462A3B113CA81'
        $settingsPath = Join-Path $TestDrive 'FModel\AppSettings.json'
        [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $settingsPath))
        Write-SKitConfig -ScumPath 'C:\Games\SCUM'
        [System.IO.File]::WriteAllText(
            $settingsPath,
            '{"OtherSetting":true,"PerDirectory":{"C:\\Games\\SCUM":{"GameDirectory":"C:\\Games\\SCUM","AesKeys":{"mainKey":"","dynamicKeys":[]}}}}'
        )
        Mock Get-FModelSettingsPath { $settingsPath }
        Mock Get-Process { $null }

        Update-FModelScumAesKey -Key $expectedKey | Should -BeTrue

        $updatedSettings = [System.IO.File]::ReadAllText($settingsPath) | ConvertFrom-Json
        $updatedSettings.OtherSetting | Should -BeTrue
        $updatedSettings.PerDirectory.'C:\Games\SCUM'.AesKeys.mainKey |
            Should -Be $expectedKey
        (Test-Path -LiteralPath "$settingsPath.skit-backup" -PathType Leaf) |
            Should -BeTrue
    }

    It 'rejects content without a valid SCUM key' {
        { Get-ScumAesKeyFromContent -Content '<p>SCUM 0x1234</p>' } |
            Should -Throw '*valid 256-bit AES key*'
    }
}

Describe 'SCUM launch modes' {
    BeforeEach {
        Mock Get-ConfiguredScumExecutable { 'C:\Games\SCUM\SCUM.exe' }
        Mock Read-SKitConfig {
            [pscustomobject]@{ ScumStartParams = '' }
        }
        Mock Start-Process {}
    }

    It 'uses mod arguments when no mode is supplied' {
        Start-Scum

        Assert-MockCalled Start-Process -Times 1 -ParameterFilter {
            $FilePath -eq 'C:\Games\SCUM\SCUM.exe' -and
            $ArgumentList.Count -eq 2 -and
            $ArgumentList[0] -eq '-fileopenlog' -and
            $ArgumentList[1] -eq '-nobattleye'
        }
    }

    It 'uses mod arguments for the modded mode' {
        Start-Scum -Mode modded

        Assert-MockCalled Start-Process -Times 1 -ParameterFilter {
            $ArgumentList -join '|' -eq '-fileopenlog|-nobattleye'
        }
    }

    It 'uses no mod arguments for the default mode' {
        Start-Scum -Mode default

        Assert-MockCalled Start-Process -Times 1 -ParameterFilter {
            $FilePath -eq 'C:\Games\SCUM\SCUM.exe' -and
            $null -eq $ArgumentList
        }
    }

    It 'adds custom parameters after the mod arguments' {
        Mock Read-SKitConfig {
            [pscustomobject]@{ ScumStartParams = '-windowed -ResX=1920' }
        }

        Start-Scum -Mode modded

        Assert-MockCalled Start-Process -Times 1 -ParameterFilter {
            $ArgumentList -join '|' -eq '-fileopenlog|-nobattleye|-windowed -ResX=1920'
        }
    }

    It 'uses custom parameters without mod arguments in default mode' {
        Mock Read-SKitConfig {
            [pscustomobject]@{ ScumStartParams = '-windowed' }
        }

        Start-Scum -Mode default

        Assert-MockCalled Start-Process -Times 1 -ParameterFilter {
            $ArgumentList -join '|' -eq '-windowed'
        }
    }
}
