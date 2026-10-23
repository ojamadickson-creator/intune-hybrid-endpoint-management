<#
.SYNOPSIS
    Triggers an on-demand Intune device sync (check-in) for one or more devices.

.DESCRIPTION
    Finds each device by name in Intune and calls the Graph syncDevice action - the same
    operation as Devices > All devices > select device > Sync in the Intune admin center
    (https://learn.microsoft.com/intune/intune-service/remote-actions/device-sync).
    The sync forces a check-in so the device receives pending policies and apps; how
    quickly they then apply depends on the device (track it in the device's sync status).

    This is an OPTIONAL operational utility - it is not one of the four counted
    automation packages in docs/implementation-ledger.md.

.PARAMETER DeviceName
    One or more device names, e.g. 'CLIENT01'. Exact match (no wildcards).

.PARAMETER TenantId
    The Entra tenant ID.

.EXAMPLE
    .\Sync-IntuneDevices.ps1 -DeviceName 'CLIENT01' -TenantId '00000000-0000-0000-0000-000000000000'

.NOTES
    Required Graph scopes (delegated):
      DeviceManagementManagedDevices.Read.All
      DeviceManagementManagedDevices.PrivilegedOperations.All
    If you extend this script, verify scopes with:
      Find-MgGraphCommand -command <cmdlet> | Select -First 1 -ExpandProperty Permissions
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$DeviceName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId
)

$ErrorActionPreference = 'Stop'
$requiredScopes = @(
    'DeviceManagementManagedDevices.Read.All',
    'DeviceManagementManagedDevices.PrivilegedOperations.All'
)

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )
    Write-Host ('{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message)
}

function Invoke-Graph {
    # Resolves whichever invoke cmdlet is available: Invoke-MgGraph and
    # Invoke-MgGraphRequest both ship in current Microsoft.Graph.Authentication
    # releases; resolving by name keeps the script working across module versions.
    param(
        [Parameter(Mandatory = $true)][ValidateSet('GET', 'POST')][string]$Method,
        [Parameter(Mandatory = $true)][string]$Uri,
        [string]$Body
    )
    $cmd = Get-Command -Name 'Invoke-MgGraph' -ErrorAction SilentlyContinue
    if (-not $cmd) { $cmd = Get-Command -Name 'Invoke-MgGraphRequest' -ErrorAction Stop }
    $params = @{ Method = $Method; Uri = $Uri }
    if ($Method -eq 'POST') {
        $params.Body = $Body
        $params.ContentType = 'application/json'
    }
    return & $cmd.Name @params
}

function ConvertTo-ODataLiteral {
    # Escapes single quotes for OData $filter literals.
    param([Parameter(Mandatory = $true)][string]$Value)
    return $Value -replace "'", "''"
}

try {
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
        throw 'Microsoft.Graph.Authentication is not installed. Run: Install-Module Microsoft.Graph.Authentication'
    }
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    Import-Module Microsoft.Graph.DeviceManagement -ErrorAction Stop

    Write-Log 'Connecting to Microsoft Graph (interactive sign-in)...'
    $null = Connect-MgGraph -TenantId $TenantId -Scopes $requiredScopes -NoWelcome
    if (-not (Get-MgContext)) { throw 'Graph connection failed.' }

    foreach ($name in $DeviceName) {
        $filterName = ConvertTo-ODataLiteral -Value $name
        $devices = @(Get-MgDeviceManagementManagedDevice -Filter "deviceName eq '$filterName'")
        if ($devices.Count -eq 0) {
            Write-Log "Device '$name' not found in Intune." -Level 'WARN'
            continue
        }
        if ($devices.Count -gt 1) {
            Write-Log "Device name '$name' matches $($devices.Count) Intune records; syncing each one." -Level 'WARN'
        }

        foreach ($device in $devices) {
            $lastSync = if ($device.LastSyncDateTime) { $device.LastSyncDateTime.ToString('yyyy-MM-dd HH:mm:ss') } else { 'never' }
            Write-Log "Device '$($device.DeviceName)' (id $($device.Id)) - last check-in before sync: $lastSync"

            # syncDevice is a POST action on the managedDevice resource; it takes no parameters.
            $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/$($device.Id)/syncDevice"
            $null = Invoke-Graph -Method POST -Uri $uri -Body '{}'

            Write-Log "Sync requested for '$($device.DeviceName)'. The device checks in and receives pending policies/apps; watch the device's Last check-in time and policy status in the admin center to confirm processing."
        }
    }
}
catch {
    Write-Log "FAILED: $($_.Exception.Message)" -Level 'ERROR'
    throw
}
finally {
    if (Get-MgContext) {
        $null = Disconnect-MgGraph
        Write-Log 'Disconnected from Microsoft Graph.'
    }
}
