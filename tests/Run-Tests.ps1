#Requires -Version 5.1

[CmdletBinding()]
param()

$pester = Get-Module -ListAvailable -Name Pester |
    Where-Object {
        $_.Version -ge [version]'5.5.0' -and
        $_.Version -lt [version]'6.0.0'
    } |
    Sort-Object Version -Descending |
    Select-Object -First 1

if ($null -eq $pester) {
    throw 'Pester 5.5.0 or later is required. Run: Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser'
}

Import-Module $pester.Path -Force

$configuration = New-PesterConfiguration
$configuration.Run.Path = $PSScriptRoot
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = 'Detailed'

$result = Invoke-Pester -Configuration $configuration
if ($result.FailedCount -gt 0) {
    exit 1
}
