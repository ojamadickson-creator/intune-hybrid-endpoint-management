<#
.SYNOPSIS
    Collects a hardware/software inventory snapshot and writes it to a log file.

.DESCRIPTION
    Intune platform script (deployed via Devices > Scripts and remediations > Platform
    scripts). Runs in SYSTEM context, writes a timestamped inventory to
    C:\ProgramData\Beginningdimension\Logs\DeviceInventory.log, and is idempotent -
    each run appends one JSON line so the log becomes a history of check-ins.

    Docs for Intune platform scripts:
    https://learn.microsoft.com/intune/intune-service/apps/powershell-scripts

    Exit codes: 0 = inventory collected and written; 1 = the inventory could not be
    written (Intune reports the script as failed). Individual fields that are
    unavailable on a device are reported as null rather than failing the run.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$LogPath = 'C:\ProgramData\Beginningdimension\Logs\DeviceInventory.log'
)

$ErrorActionPreference = 'Stop'

function Get-SafeValue {
    # Individual fields that are unavailable on a device report as null
    # instead of failing the whole run.
    param([scriptblock]$Script)
    try { & $Script } catch { $null }
}

$os         = Get-SafeValue { Get-CimInstance Win32_OperatingSystem }
$computer   = Get-SafeValue { Get-CimInstance Win32_ComputerSystem }
$tpm        = Get-SafeValue { Get-Tpm }
$secureBoot = Get-SafeValue { Confirm-SecureBootUEFI }
$bitLocker  = Get-SafeValue { Get-BitLockerVolume -MountPoint $env:SystemDrive }
$defender   = Get-SafeValue { Get-MpComputerStatus }
$disks      = Get-SafeValue { Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" }
$systemDisk = if ($disks) { $disks | Where-Object DeviceID -eq $env:SystemDrive } else { $null }

$inventory = [ordered]@{
    Timestamp          = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    ComputerName       = $env:COMPUTERNAME
    Manufacturer       = $computer.Manufacturer
    Model              = $computer.Model
    OsName             = $os.Caption
    OsVersion          = $os.Version
    OsBuild            = $os.BuildNumber
    LastBootUpTime     = if ($os.LastBootUpTime) { $os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm:ss') } else { $null }
    TotalMemoryGB      = if ($computer.TotalPhysicalMemory) { [math]::Round($computer.TotalPhysicalMemory / 1GB, 1) } else { $null }
    DomainJoined       = if ($computer) { [bool]$computer.PartOfDomain } else { $null }
    TpmPresent         = if ($tpm) { [bool]$tpm.TpmPresent } else { $null }
    TpmReady           = if ($tpm) { [bool]$tpm.TpmReady } else { $null }
    SecureBootEnabled  = if ($null -ne $secureBoot) { [bool]$secureBoot } else { $null }
    BitLockerStatus    = if ($bitLocker) { "$($bitLocker.VolumeStatus)" } else { $null }
    ProtectionOn       = if ($bitLocker) { "$($bitLocker.ProtectionStatus)" } else { $null }
    AvEnabled          = if ($defender) { [bool]$defender.AMServiceEnabled } else { $null }
    AvSignatureAgeDays = if ($defender -and $defender.AntivirusSignatureLastUpdated) {
        [int]((Get-Date) - $defender.AntivirusSignatureLastUpdated).TotalDays }
    else { $null }
    SystemDriveFreeGB  = if ($systemDisk) { [math]::Round($systemDisk.FreeSpace / 1GB, 1) } else { $null }
}

$json = $inventory | ConvertTo-Json -Compress

# Write with verification - exit code tells Intune whether the run succeeded.
# The write itself and the read-back both use terminating errors so failures
# land in the catch block instead of being silently continued.
$writeOk = $false
try {
    $logDir = Split-Path -Parent $LogPath
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $sizeBefore = if (Test-Path -LiteralPath $LogPath) { (Get-Item -LiteralPath $LogPath).Length } else { 0 }
    Add-Content -LiteralPath $LogPath -Value $json -Encoding UTF8 -ErrorAction Stop
    # Verify the record actually landed: file grew and last line parses as JSON.
    $item = Get-Item -LiteralPath $LogPath
    $lastLine = Get-Content -LiteralPath $LogPath -Tail 1
    $parsed = $null
    try { $parsed = $lastLine | ConvertFrom-Json } catch { }
    $writeOk = ($item.Length -gt $sizeBefore) -and ($null -ne $parsed) -and ($parsed.Timestamp -eq $inventory.Timestamp)
}
catch {
    Write-Error "Inventory log could not be written to '$LogPath': $($_.Exception.Message)"
}

if ($writeOk) { exit 0 } else { exit 1 }
