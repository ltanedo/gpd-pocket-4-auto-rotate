<#
.SYNOPSIS
    Restore Windows auto-rotation on a GPD Pocket 4 (and similar handhelds).

.DESCRIPTION
    Sets two registry values:
      HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AutoRotation\SensorPresent = 1
      HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\OEM\DeviceForm          = 2

    The previous values are printed before anything is written, so note them
    down. A restart is required afterwards; this script does not restart for you.

    Read the README before running this. DeviceForm = 2 (Tablet) can change
    handheld-oriented Windows behaviour; Restore-DeviceForm.ps1 reverses it.

.PARAMETER SkipDeviceForm
    Only set SensorPresent. This brings the Rotation lock control back but, on
    the Pocket 4, was not enough to make the display actually rotate.

.PARAMETER WhatIf
    Show what would change without writing anything.

.EXAMPLE
    # In an Administrator PowerShell:
    powershell -ExecutionPolicy Bypass -File .\Repair-AutoRotation.ps1
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch] $SkipDeviceForm
)

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $identity.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'This script must run in an elevated (Administrator) PowerShell window.'
}

$autoRotationPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AutoRotation'
$oemPath          = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\OEM'

function Get-RegValue {
    param(
        [string] $Path,
        [string] $Name
    )
    try {
        return (Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop).$Name
    } catch {
        return $null
    }
}

function Set-RegDword {
    param(
        [string] $Path,
        [string] $Name,
        [int]    $Value
    )

    $old = Get-RegValue -Path $Path -Name $Name
    if ($null -eq $old) { $old = '<not set>' }

    Write-Host ("{0}\{1}: {2} -> {3}" -f $Path, $Name, $old, $Value)

    if ($PSCmdlet.ShouldProcess("$Path\$Name", "set to $Value")) {
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        New-ItemProperty -LiteralPath $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
    }
}

Write-Host 'Previous values:' -ForegroundColor Cyan
[pscustomobject]@{
    'AutoRotation\SensorPresent' = Get-RegValue -Path $autoRotationPath -Name 'SensorPresent'
    'AutoRotation\Enable'        = Get-RegValue -Path $autoRotationPath -Name 'Enable'
    'AutoRotation\SlateEnable'   = Get-RegValue -Path $autoRotationPath -Name 'SlateEnable'
    'OEM\DeviceForm'             = Get-RegValue -Path $oemPath -Name 'DeviceForm'
} | Format-List | Out-String | Write-Host

Write-Host 'Applying:' -ForegroundColor Cyan
Set-RegDword -Path $autoRotationPath -Name 'SensorPresent' -Value 1
Set-RegDword -Path $autoRotationPath -Name 'Enable'        -Value 1
Set-RegDword -Path $autoRotationPath -Name 'SlateEnable'   -Value 1

if ($SkipDeviceForm) {
    Write-Host 'Skipping DeviceForm, as requested.'
} else {
    Set-RegDword -Path $oemPath -Name 'DeviceForm' -Value 2
}

Write-Host ''
Write-Host 'Done. Restart Windows for this to take effect:' -ForegroundColor Green
Write-Host '    shutdown /r /t 0'
Write-Host ''
Write-Host 'After the restart, make sure Rotation lock is OFF, then turn the whole device.'
