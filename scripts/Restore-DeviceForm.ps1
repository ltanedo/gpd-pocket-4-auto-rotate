<#
.SYNOPSIS
    Put DeviceForm back to its original value (46 on the GPD Pocket 4).

.DESCRIPTION
    Reverses the DeviceForm change made by Repair-AutoRotation.ps1. Use this if
    setting DeviceForm to 2 (Tablet) broke a handheld-oriented Windows feature
    you care about, such as the Xbox full-screen experience.

    Restoring 46 will also bring the auto-rotation problem back.

    A restart is required afterwards; this script does not restart for you.

.PARAMETER Value
    The form-factor value to restore. Defaults to 46 (gaming handheld), which is
    what the Pocket 4 shipped with. See
    https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-deployment-deviceform

.EXAMPLE
    # In an Administrator PowerShell:
    powershell -ExecutionPolicy Bypass -File .\Restore-DeviceForm.ps1
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateRange(0, 255)]
    [int] $Value = 46
)

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $identity.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'This script must run in an elevated (Administrator) PowerShell window.'
}

$oemPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\OEM'

$old = $null
try {
    $old = (Get-ItemProperty -LiteralPath $oemPath -Name 'DeviceForm' -ErrorAction Stop).DeviceForm
} catch {
    $old = '<not set>'
}

Write-Host ("OEM\DeviceForm: {0} -> {1}" -f $old, $Value)

if ($PSCmdlet.ShouldProcess("$oemPath\DeviceForm", "set to $Value")) {
    if (-not (Test-Path -LiteralPath $oemPath)) {
        New-Item -Path $oemPath -Force | Out-Null
    }
    New-ItemProperty -LiteralPath $oemPath -Name 'DeviceForm' -PropertyType DWord -Value $Value -Force | Out-Null
}

Write-Host ''
Write-Host 'Done. Restart Windows for this to take effect:' -ForegroundColor Green
Write-Host '    shutdown /r /t 0'
