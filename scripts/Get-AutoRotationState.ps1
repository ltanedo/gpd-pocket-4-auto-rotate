<#
.SYNOPSIS
    Read-only report on why Windows auto-rotation may not be working.

.DESCRIPTION
    Prints the rotation sensor device, its driver, the two sensor services, and
    the two registry values that controlled auto-rotation on a GPD Pocket 4.
    Changes nothing. Does not need administrator rights.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Get-AutoRotationState.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

function Write-Section {
    param([string] $Title)
    Write-Host ''
    Write-Host "== $Title" -ForegroundColor Cyan
}

function Get-RegValue {
    param(
        [string] $Path,
        [string] $Name
    )
    try {
        $item = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
        return $item.$Name
    } catch {
        return $null
    }
}

Write-Section 'Rotation sensor devices'
$sensors = Get-PnpDevice -Class 'Sensor' -ErrorAction SilentlyContinue
if (-not $sensors) {
    Write-Host 'No devices in the Sensor class. Windows sees no rotation sensor at all.' -ForegroundColor Yellow
} else {
    $sensors |
        Select-Object Status, Class, FriendlyName, InstanceId |
        Format-Table -AutoSize |
        Out-String |
        Write-Host
}

Write-Section 'Sensor drivers'
$driverRows = Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue |
    Where-Object { $_.DeviceClass -eq 'SENSOR' -or $_.DeviceName -match 'accelerom|MXC6655|BMI160' }
if ($driverRows) {
    $driverRows |
        Select-Object DeviceName, DeviceID, InfName, DriverVersion, DriverDate |
        Format-List |
        Out-String |
        Write-Host
} else {
    Write-Host 'No accelerometer driver found.' -ForegroundColor Yellow
}

Write-Section 'Problem codes'
Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'accelerom|MXC6655|BMI160' } |
    Select-Object Name,
        @{ Name = 'ProblemCode'; Expression = { $_.ConfigManagerErrorCode } },
        DeviceID |
    Format-List |
    Out-String |
    Write-Host

Write-Section 'Services'
Get-Service -Name 'SensorService', 'SensrSvc', 'SensorDataService' -ErrorAction SilentlyContinue |
    Select-Object Name, DisplayName, Status, StartType |
    Format-Table -AutoSize |
    Out-String |
    Write-Host

Write-Section 'Registry'
$autoRotationPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AutoRotation'
$oemPath          = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\OEM'

$sensorPresent = Get-RegValue -Path $autoRotationPath -Name 'SensorPresent'
$enable        = Get-RegValue -Path $autoRotationPath -Name 'Enable'
$slateEnable   = Get-RegValue -Path $autoRotationPath -Name 'SlateEnable'
$deviceForm    = Get-RegValue -Path $oemPath -Name 'DeviceForm'

[pscustomobject]@{
    'AutoRotation\SensorPresent' = $sensorPresent
    'AutoRotation\Enable'        = $enable
    'AutoRotation\SlateEnable'   = $slateEnable
    'OEM\DeviceForm'             = $deviceForm
} | Format-List | Out-String | Write-Host

Write-Section 'Verdict'

if ($sensorPresent -ne 1) {
    Write-Host "SensorPresent is '$sensorPresent', not 1. Windows thinks there is no rotation sensor, so Rotation lock is hidden. Repair-AutoRotation.ps1 fixes this." -ForegroundColor Yellow
} else {
    Write-Host 'SensorPresent = 1. Good.' -ForegroundColor Green
}

if ($null -eq $deviceForm) {
    Write-Host 'DeviceForm is not set. That is normal on many machines and is not itself a problem.'
} elseif ($deviceForm -eq 2) {
    Write-Host 'DeviceForm = 2 (Tablet). Good.' -ForegroundColor Green
} else {
    Write-Host "DeviceForm = $deviceForm. On the Pocket 4 this was 46 (gaming handheld), and Windows would not rotate the display in that form factor. Setting it to 2 (Tablet) fixed it. See the README for the caveat." -ForegroundColor Yellow
}

Write-Host ''
Write-Host 'Note: the Pocket 4 accelerometer is in the body, not the display hinge. Swivelling only the screen never triggers rotation.'
