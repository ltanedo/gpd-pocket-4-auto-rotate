# GPD Pocket 4 — restoring Windows 11 auto-rotation

Auto-rotation on the GPD Pocket 4 stopped working after a Windows update, and the
**Rotation lock** toggle disappeared from Quick Settings and from
*Settings → System → Display* entirely.

The accelerometer and its driver turned out to be fine. The problem was two
Windows registry values. This repo documents the diagnosis, the fix that worked,
the things that did **not** work, and how to roll it back.

Verified on a GPD Pocket 4 (AMD Ryzen AI 300 / 8840U family) running Windows 11 24H2.

---

## TL;DR

Run in an **Administrator** PowerShell, then restart:

```powershell
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AutoRotation' -Name SensorPresent -Type DWord -Value 1
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\OEM' -Name DeviceForm -Type DWord -Value 2
```

- `SensorPresent = 1` brings the **Rotation lock** control back.
- `DeviceForm = 2` (Tablet) makes Windows actually *act* on the sensor.

You need **both**. `SensorPresent` alone restores the toggle but the screen still
won't rotate. See [the caveat about `DeviceForm`](#caveat-what-deviceform--2-changes).

Or use the scripts: [`scripts/Repair-AutoRotation.ps1`](scripts/Repair-AutoRotation.ps1).

---

## Symptoms

- The screen does not rotate when the device is turned.
- **Rotation lock** is missing from Quick Settings, and *Display orientation* in
  Settings offers only Landscape / Portrait / Landscape (flipped) / Portrait
  (flipped) — there is no "Auto".
- Device Manager shows no error: the sensor reports *"This device is working
  properly"* with problem code `0`.

## What was ruled out

Everything in this list was checked and was **not** the cause:

| Checked | Result |
| --- | --- |
| `Memsic Accelerometer MXC6655` in Device Manager | Present, no warning triangle, status OK |
| Both `AMD I2C Controller` entries under System devices | No warning triangles; no rollback needed |
| `Sensor Service` and `Sensor Monitoring Service` | Both already Running |
| Disable + re-enable the sensor device, then restart | No change |
| GPD **MotionAssistant** → Advanced → "Disable Tablet Mode" | Already unchecked |
| Hibernation / Fast Startup (`powercfg /h off`) | No change |
| Reinstalling the sensor driver from GPD's package | Driver was already correct; no change |
| Cold reset (hold power 20–30s, everything unplugged) | No change |

A small UWP `Windows.Devices.Sensors.Accelerometer` reader confirmed the hardware
was healthy: live X/Y/Z values changed as the device moved, while Windows still
refused to rotate the display. That is what narrowed it down to Windows' rotation
handling rather than the sensor stack.

## Root cause

Two registry values were wrong:

| Value | Was | Should be | Effect |
| --- | --- | --- | --- |
| `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AutoRotation\SensorPresent` | `0` | `1` | While `0`, Windows believes there is no rotation sensor and hides the Rotation lock UI |
| `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\OEM\DeviceForm` | `46` | `2` | `46` is the *gaming handheld* form factor. Windows does not drive display rotation from the sensor in that form factor. `2` is *Tablet* |

`DeviceForm = 46` is the interesting one — it is a legitimate value that GPD and
other handheld vendors set, and it is why the usual "enable auto-rotate" advice
on the internet does not fix this machine. The same symptom and fix have been
reported on other Windows handhelds.

Microsoft's list of form-factor values:
[Microsoft-Windows-Deployment DeviceForm](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-deployment-deviceform).

## The fix

### 1. Make Windows admit the sensor exists

```powershell
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AutoRotation' -Name SensorPresent -Type DWord -Value 1
```

`Enable` and `SlateEnable` under the same key should also be `1`.

### 2. Set the form factor to Tablet

```powershell
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\OEM' -Name DeviceForm -Type DWord -Value 2
```

### 3. Restart

```powershell
shutdown /r /t 0
```

A sign-out is not enough — these are read at boot.

### 4. Test

Make sure **Rotation lock is off**, then turn the whole device. Note that the
accelerometer is in the Pocket 4's **body**, not the display hinge: swivelling
only the screen will never trigger rotation.

## Caveat: what `DeviceForm = 2` changes

`DeviceForm` tells Windows what kind of machine this is. Moving the Pocket 4 from
*gaming handheld* (`46`) to *Tablet* (`2`) can change handheld-oriented Windows
behaviour — most visibly the Xbox full-screen / handheld experience on Windows 11
builds that ship it.

It is fully reversible:

```powershell
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\OEM' -Name DeviceForm -Type DWord -Value 46
```

...then restart. Restoring `46` will also bring the auto-rotation problem back.
Pick whichever matters more to you.

## Optional: clean sensor-driver reinstall

The driver was *not* the problem on this machine, but if your sensor shows a
**Code 10** or a warning triangle, reinstall it from GPD's own package rather
than a generic MXC6655 driver from a driver site — third-party packages lack the
Pocket 4 configuration.

Download the **GPD Pocket 4 drivers** from the official page
(<https://www.gpd.hk/gpdpocket4firmware>) and extract it. The sensor drivers are
under `Drivers\Sensors`. On the machine tested here the correct one was:

```text
<extracted>\GPD_AMD_Drivers-V4.2.0\Drivers\Sensors\mxc6655.inf_amd64_b99f8fc64ab4f1f0\MXC6655.inf
```

- Device: **MEMSIC Accelerometer MXC6655**, hardware ID `ACPI\MXC6655`
- Driver: `MXC6655.inf`, version `11.5.11.123` (package dated 2025-03-07)

The same folder also contains a **BMI160** driver. Do not install it unless
Device Manager identifies *your* sensor as BMI160 — the two are different parts
and Pocket 4 units are not all identical.

See [`scripts/Reinstall-Mxc6655Driver.ps1`](scripts/Reinstall-Mxc6655Driver.ps1).

## Scripts

| Script | What it does |
| --- | --- |
| [`scripts/Get-AutoRotationState.ps1`](scripts/Get-AutoRotationState.ps1) | Read-only. Prints the sensor device, driver version, services, and both registry values, so you can see whether this is your problem |
| [`scripts/Repair-AutoRotation.ps1`](scripts/Repair-AutoRotation.ps1) | Sets `SensorPresent = 1` and `DeviceForm = 2`, printing the previous values first. Needs admin |
| [`scripts/Restore-DeviceForm.ps1`](scripts/Restore-DeviceForm.ps1) | Puts `DeviceForm` back (defaults to `46`). Needs admin |
| [`scripts/Reinstall-Mxc6655Driver.ps1`](scripts/Reinstall-Mxc6655Driver.ps1) | Removes and reinstalls the MXC6655 sensor driver from a GPD driver package you point it at. Needs admin |

None of them restart the machine for you.

## References

- [Microsoft: `DeviceForm` unattend values](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-deployment-deviceform)
- [Microsoft Q&A: auto-rotate option gone after an update (`SensorPresent`)](https://learn.microsoft.com/en-us/answers/questions/2313451/surface-book-2-auto-rotate-option-is-gone-after-th)
- [DroiX: fix GPD Pocket 4 auto-rotation Code 10](https://droix.net/knowledge-base/article/fix-gpd-pocket-4-auto-rotation-code-10/)
- [GPD Pocket 4 firmware and drivers](https://www.gpd.hk/gpdpocket4firmware)

## Disclaimer

These are registry edits on your own machine, offered as-is with no warranty.
Read what each command does before running it, and keep the rollback values
handy.
