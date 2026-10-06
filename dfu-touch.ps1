<#
.SYNOPSIS
    Put a NocFree & half into its UF2 bootloader from Windows, by opening its
    USB CDC serial port at 1200 baud.

.DESCRIPTION
    This is the Windows equivalent of the `stty ... 1200` commands in
    docs/recovery.md. Both halves of this firmware expose a CDC ACM serial
    interface; setting the line rate to 1200 baud asks the half to warm-reboot
    into its preserved UF2 bootloader, the same convention Arduino and
    Adafruit tooling use.

    This path does NOT depend on the keymap, the split link, Bluetooth or
    pairing. It is the route that still works when Fn+Esc / Fn+Delete cannot,
    which is why the right half carries the CDC interface at all.

    It does NOT work on factory NocFree firmware. Confirmed on v2.4.5: the
    port refuses to open. Coming from stock, or after rolling back to it, the
    only routes are Fn+5 (left) and Fn+0 (right), each held 5 seconds.

.EXAMPLE
    .\dfu-touch.ps1
    Lists the NocFree serial ports it can see and which half each one is.

.EXAMPLE
    .\dfu-touch.ps1 -Half Right
    Finds the right half by its USB product string and touches it.

.EXAMPLE
    .\dfu-touch.ps1 -Port COM5
#>
[CmdletBinding(DefaultParameterSetName = 'List')]
param(
    [Parameter(ParameterSetName = 'Port')]
    [string]$Port,

    [Parameter(ParameterSetName = 'Half')]
    [ValidateSet('Left', 'Right')]
    [string]$Half
)

# ZMK's USB identity, as built into these images.
$VidPid = 'VID_1D50&PID_615E'

function Get-NocFreePort {
    # Windows shows CDC ports with the generic friendly name "USB Serial
    # Device (COMn)", which carries no product information -- both halves look
    # identical there. The USB product string ("NocFree &" vs "NocFree &
    # Right") is only exposed as the bus-reported device description, so read
    # that. Board-ID on the bootloader drive is identical on both halves too,
    # making this the only reliable way to tell them apart on Windows.
    #
    # -PresentOnly: Windows keeps every port it has ever enumerated, so
    # without it a half cabled on some earlier day is listed as if it were
    # plugged in now -- and -Half then picks a COM port that is not there.
    Get-PnpDevice -Class Ports -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -like "*$VidPid*" } |
        ForEach-Object {
            $desc = (Get-PnpDeviceProperty -InstanceId $_.InstanceId `
                        -KeyName 'DEVPKEY_Device_BusReportedDeviceDesc' `
                        -ErrorAction SilentlyContinue).Data
            $parent = (Get-PnpDeviceProperty -InstanceId $_.InstanceId `
                        -KeyName 'DEVPKEY_Device_Parent' `
                        -ErrorAction SilentlyContinue).Data
            [pscustomobject]@{
                Port    = [regex]::Match($_.FriendlyName, '\((COM\d+)\)').Groups[1].Value
                Half    = if ($desc -match 'Right') { 'Right' } else { 'Left' }
                Product = $desc
                Serial  = ($parent -split '\\')[-1]
            }
        } | Where-Object Port
}

function Invoke-Touch {
    param([string]$ComPort, [string]$Which)

    Write-Host "Touching $ComPort ($Which) at 1200 baud..." -ForegroundColor Cyan
    $sp = New-Object System.IO.Ports.SerialPort $ComPort, 1200, 'None', 8, 'One'
    try {
        $sp.DtrEnable = $true
        $sp.Open()
        Start-Sleep -Milliseconds 250
    }
    catch {
        Write-Error "Could not open ${ComPort}: $($_.Exception.Message)"
        Write-Host "If this half is running factory firmware, use Fn+5 (left) or Fn+0 (right), held 5 s."
        exit 1
    }
    finally {
        if ($sp.IsOpen) { $sp.Close() }
        $sp.Dispose()
    }
    Write-Host "Sent. A drive named 'NocFree &' should appear within a few seconds." -ForegroundColor Green
    Write-Host "The drive does not say which half it is -- CURRENT.UF2 is the only proof." -ForegroundColor Yellow
    Write-Host "Back up CURRENT.UF2 off it before writing anything." -ForegroundColor Yellow
}

$found = @(Get-NocFreePort)

switch ($PSCmdlet.ParameterSetName) {
    'Port' {
        $known = $found | Where-Object Port -eq $Port
        Invoke-Touch -ComPort $Port -Which $(if ($known) { $known[0].Half } else { 'unidentified' })
    }

    'Half' {
        $match = @($found | Where-Object Half -eq $Half)
        if (-not $match) {
            Write-Error "No $Half half found. Is it cabled? Seen: $(($found | ForEach-Object { "$($_.Port)=$($_.Half)" }) -join ', ')"
            exit 1
        }
        if ($match.Count -gt 1) {
            Write-Error "Ambiguous: $Half matched $($match.Count) ports. Use -Port explicitly."
            exit 1
        }
        Invoke-Touch -ComPort $match[0].Port -Which $Half
    }

    default {
        if (-not $found) {
            Write-Warning "No NocFree CDC port found ($VidPid)."
            Write-Host "Check the half is cabled directly. Factory firmware does not expose this interface --"
            Write-Host "from stock, use Fn+5 (left) or Fn+0 (right), held 5 seconds."
            exit 1
        }
        $found | Format-Table Port, Half, Product, Serial -AutoSize
        Write-Host "Run with -Half Left|Right or -Port COMn to trigger the bootloader."
    }
}
