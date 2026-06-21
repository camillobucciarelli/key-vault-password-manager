<#
.SYNOPSIS
Installs the KeyVault Chrome/Edge native messaging host for the current Windows user.

.PARAMETER Browser
Browser to register. Supported values: Chrome, Edge. Default: Chrome.

.PARAMETER ExtensionId
Extension ID copied from chrome://extensions or edge://extensions.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidatePattern('^[a-p]{32}$')]
    [string]$ExtensionId,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Chrome', 'Edge')]
    [string]$Browser = 'Chrome'
)

$ErrorActionPreference = 'Stop'

$HostName = 'dev.camillobucciarelli.keyvault_native_host'
$InstallDir = Join-Path $env:LOCALAPPDATA 'KeyVault\NativeMessagingHosts'
$ManifestPath = Join-Path $InstallDir "$HostName.json"
$LauncherPath = Join-Path $InstallDir 'keyvault_native_host.cmd'
$LauncherScriptPath = Join-Path $InstallDir 'keyvault_native_host.ps1'
$BrowserRegistryRoot = if ($Browser -eq 'Edge') { 'HKCU:\Software\Microsoft\Edge\NativeMessagingHosts' } else { 'HKCU:\Software\Google\Chrome\NativeMessagingHosts' }
$BrowserTemplateDir = if ($Browser -eq 'Edge') { 'edge' } else { 'chrome' }
$RegistryPath = Join-Path $BrowserRegistryRoot $HostName

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
    $TemplatePath = Join-Path $ScriptDir "manifests\$BrowserTemplateDir\$HostName.json"
    $NativeHostDart = Join-Path $RepoRoot 'tool\native_host.dart'

    if (-not (Test-Path -LiteralPath $TemplatePath -PathType Leaf)) {
        throw "Chrome manifest template not found: $TemplatePath"
    }
    if (-not (Test-Path -LiteralPath $NativeHostDart -PathType Leaf)) {
        throw "Dart native host entry point not found: $NativeHostDart"
    }

    Write-Step "Installing for $Browser extension ID: $ExtensionId"
    Write-Step "Creating install directory: $InstallDir"
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

    $EscapedNativeHostDart = $NativeHostDart.Replace("'", "''")
    $LauncherScriptContent = @"
`$ErrorActionPreference = 'Stop'
`$NativeHostExe = Join-Path `$PSScriptRoot 'keyvault_native_host.exe'
if (Test-Path -LiteralPath `$NativeHostExe -PathType Leaf) {
    & `$NativeHostExe
    exit `$LASTEXITCODE
}
# TODO(autofill-v2-packaging): ship a signed native_host exe next to this script.
& dart '$EscapedNativeHostDart'
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
    Write-Step "Registered HKCU $Browser native messaging host: $RegistryPath"

    Write-Host ''
    Write-Host "KeyVault $Browser native messaging host installed successfully."
    Write-Host "Manifest: $ManifestPath"
    Write-Host "Launcher: $LauncherPath"
    Write-Host "Launcher script: $LauncherScriptPath"
    Write-Host "Restart $Browser before testing the extension."
}
catch {
    Write-Error "Failed to install KeyVault $Browser native messaging host. $($_.Exception.Message)"
    exit 1
}
