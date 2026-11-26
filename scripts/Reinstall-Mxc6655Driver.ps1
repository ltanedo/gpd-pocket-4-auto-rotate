<#
.SYNOPSIS
    Cleanly remove and reinstall the MEMSIC MXC6655 accelerometer driver from
    GPD's own driver package.

.DESCRIPTION
    Only useful if your sensor shows a warning triangle or Code 10 in Device
    Manager. On the machine this repo documents, the driver was already correct
    and this step changed nothing -- the fix was Repair-AutoRotation.ps1.

    Point -InfPath at MXC6655.inf inside an extracted GPD Pocket 4 driver
    package (Drivers\Sensors\mxc6655.inf_amd64_*\MXC6655.inf), or point
    -SearchRoot at the extracted package and let the script find it.

    Do NOT install the BMI160 driver that ships in the same folder unless Device
    Manager identifies your sensor as BMI160.

    A restart is required afterwards; this script does not restart for you.

.PARAMETER InfPath
    Full path to MXC6655.inf.

.PARAMETER SearchRoot
    A folder to search for MXC6655.inf, e.g. the extracted driver package.

.PARAMETER InstanceId
    Device instance id of the sensor. Defaults to 'ACPI\MXC6655\1'. Check yours
    with Get-AutoRotationState.ps1 if the default does not match.

.EXAMPLE
    # In an Administrator PowerShell:
    .\Reinstall-Mxc6655Driver.ps1 -SearchRoot 'C:\Users\you\Downloads\GPD_AMD_Drivers-V4.2.0'

.EXAMPLE
    .\Reinstall-Mxc6655Driver.ps1 -InfPath 'C:\drivers\Sensors\mxc6655.inf_amd64_b99f8fc64ab4f1f0\MXC6655.inf' -WhatIf
#>

[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Search')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Inf')]
    [string] $InfPath,

    [Parameter(Mandatory = $true, ParameterSetName = 'Search')]
    [string] $SearchRoot,

    [string] $InstanceId = 'ACPI\MXC6655\1'
)

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $identity.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'This script must run in an elevated (Administrator) PowerShell window.'
}

if ($PSCmdlet.ParameterSetName -eq 'Search') {
    if (-not (Test-Path -LiteralPath $SearchRoot -PathType Container)) {
        throw "SearchRoot not found: $SearchRoot"
    }

    $found = Get-ChildItem -LiteralPath $SearchRoot -Filter 'MXC6655.inf' -Recurse -File -ErrorAction SilentlyContinue
    if (-not $found) {
        throw "No MXC6655.inf under $SearchRoot. Check that you extracted the GPD driver package."
    }
    if ($found.Count -gt 1) {
        Write-Host 'Several matches found:' -ForegroundColor Yellow
        $found | ForEach-Object { Write-Host "  $($_.FullName)" }
        throw 'More than one MXC6655.inf found. Re-run with -InfPath to pick one.'
    }

    $InfPath = $found[0].FullName
    Write-Host "Using driver: $InfPath"
}

if (-not (Test-Path -LiteralPath $InfPath -PathType Leaf)) {
    throw "Sensor driver not found: $InfPath"
}

$device = Get-PnpDevice -InstanceId $InstanceId -ErrorAction SilentlyContinue
if (-not $device) {
    Write-Host "No device with instance id '$InstanceId'. Sensors currently present:" -ForegroundColor Yellow
    Get-PnpDevice -Class 'Sensor' -ErrorAction SilentlyContinue |
        Select-Object Status, FriendlyName, InstanceId |
        Format-Table -AutoSize |
        Out-String |
        Write-Host
    throw 'Re-run with -InstanceId set to your sensor.'
}

Write-Host "Current device: $($device.FriendlyName) [$($device.Status)]"

$publishedInf = (
    Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue |
    Where-Object { $_.DeviceID -eq $InstanceId }
).InfName

if ($publishedInf) {
    Write-Host "Currently published INF: $publishedInf"
}

if (-not $PSCmdlet.ShouldProcess($InstanceId, "reinstall driver from $InfPath")) {
    return
}

Write-Host ''
Write-Host 'Removing the device...' -ForegroundColor Cyan
pnputil /remove-device $InstanceId

if ($publishedInf) {
    Write-Host 'Deleting the old published driver...' -ForegroundColor Cyan
    pnputil /delete-driver $publishedInf /uninstall
}

Write-Host 'Adding and installing the driver...' -ForegroundColor Cyan
pnputil /add-driver $InfPath /install

Write-Host 'Rescanning for devices...' -ForegroundColor Cyan
pnputil /scan-devices

Write-Host ''
Write-Host 'Result:' -ForegroundColor Cyan
Get-PnpDevice -InstanceId $InstanceId -ErrorAction SilentlyContinue |
    Select-Object FriendlyName, Status |
    Format-List |
    Out-String |
    Write-Host

Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
    Where-Object { $_.DeviceID -eq $InstanceId } |
    Select-Object Name, @{ Name = 'ProblemCode'; Expression = { $_.ConfigManagerErrorCode } } |
    Format-List |
    Out-String |
    Write-Host

Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue |
    Where-Object { $_.DeviceID -eq $InstanceId } |
    Select-Object DeviceName, InfName, DriverVersion |
    Format-List |
    Out-String |
    Write-Host

Write-Host 'Expected: Status OK, problem code 0, driver version 11.5.11.123.'
Write-Host 'Now restart Windows:' -ForegroundColor Green
Write-Host '    shutdown /r /t 0'
