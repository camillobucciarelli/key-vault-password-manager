<#
.SYNOPSIS
Installs the KeyVault Chrome native messaging host for the current Windows user.

.PARAMETER ExtensionId
Chrome extension ID copied from chrome://extensions.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidatePattern('^[a-p]{32}$')]
    [string]$ExtensionId
)

$ErrorActionPreference = 'Stop'

$HostName = 'dev.camillobucciarelli.kdbxKeyVault_native_host'
$InstallDir = Join-Path $env:LOCALAPPDATA 'KeyVault\NativeMessagingHosts'
$ManifestPath = Join-Path $InstallDir "$HostName.json"
$LauncherPath = Join-Path $InstallDir 'keyvault_native_host.cmd'
$LauncherScriptPath = Join-Path $InstallDir 'keyvault_native_host.ps1'
$RegistryPath = "HKCU:\Software\Google\Chrome\NativeMessagingHosts\$HostName"

function Write-Step {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[KeyVault native host] $Message"
}

try {
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw 'LOCALAPPDATA is not set. Run this script from a normal Windows user session.'
    }

    $ScriptPath = $PSCommandPath
    if ([string]::IsNullOrWhiteSpace($ScriptPath)) {
        $ScriptPath = $MyInvocation.MyCommand.Path
    }
    if ([string]::IsNullOrWhiteSpace($ScriptPath)) {
        throw 'Unable to determine script path.'
    }

    $ScriptDir = Split-Path -Parent $ScriptPath
    $RepoRoot = (Resolve-Path (Join-Path $ScriptDir '..\..')).ProviderPath
    $TemplatePath = Join-Path $ScriptDir "manifests\chrome\$HostName.json"
    $NativeHostDart = Join-Path $RepoRoot 'tool\native_host.dart'

    if (-not (Test-Path -LiteralPath $TemplatePath -PathType Leaf)) {
        throw "Chrome manifest template not found: $TemplatePath"
    }
    if (-not (Test-Path -LiteralPath $NativeHostDart -PathType Leaf)) {
        throw "Dart native host entry point not found: $NativeHostDart"
    }

    Write-Step "Installing for Chrome extension ID: $ExtensionId"
    Write-Step "Creating install directory: $InstallDir"
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

    $EscapedRepoRoot = $RepoRoot.Replace("'", "''")
    $LauncherScriptContent = @"
`$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath '$EscapedRepoRoot'
& dart run tool/native_host.dart
exit `$LASTEXITCODE
"@
    $Utf8WithBom = New-Object System.Text.UTF8Encoding -ArgumentList $true
    [System.IO.File]::WriteAllText($LauncherScriptPath, $LauncherScriptContent, $Utf8WithBom)

    $LauncherContent = @"
@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0keyvault_native_host.ps1"
exit /b %ERRORLEVEL%
"@
    Set-Content -LiteralPath $LauncherPath -Value $LauncherContent -Encoding ASCII -Force
    Write-Step "Wrote launcher: $LauncherPath"
    Write-Step "Wrote launcher script: $LauncherScriptPath"

    $Template = Get-Content -LiteralPath $TemplatePath -Raw -Encoding UTF8
    $Manifest = $Template.Replace('"__HOST_PATH__"', (ConvertTo-Json $LauncherPath -Compress))
    $Manifest = $Manifest.Replace('__EXTENSION_ID__', $ExtensionId)
    $Utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
    [System.IO.File]::WriteAllText($ManifestPath, $Manifest, $Utf8NoBom)
    Write-Step "Wrote manifest: $ManifestPath"

    New-Item -Path $RegistryPath -Force | Out-Null
    Set-Item -Path $RegistryPath -Value $ManifestPath
    Write-Step "Registered HKCU Chrome native messaging host: $RegistryPath"

    Write-Host ''
    Write-Host 'KeyVault Chrome native messaging host installed successfully.'
    Write-Host "Manifest: $ManifestPath"
    Write-Host "Launcher: $LauncherPath"
    Write-Host "Launcher script: $LauncherScriptPath"
    Write-Host 'Restart Chrome before testing the extension.'
}
catch {
    Write-Error "Failed to install KeyVault Chrome native messaging host. $($_.Exception.Message)"
    exit 1
}
