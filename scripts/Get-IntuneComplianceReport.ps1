<#
.SYNOPSIS
    Exports the compliance state of every Intune-managed device to a timestamped CSV.

.DESCRIPTION
    Connects to Microsoft Graph with least-privilege read-only permissions, walks all
    managed devices (pagination handled by -All), and writes a per-device compliance
    report. Designed for portfolio evidence and interview walkthroughs.

    Microsoft Graph PowerShell SDK: https://learn.microsoft.com/powershell/microsoftgraph/get-started
    Intune Graph overview:         https://learn.microsoft.com/graph/api/resources/intune-graph-overview

.PARAMETER TenantId
    The Entra tenant ID (find it in the Entra admin center > Overview).

.PARAMETER OutputPath
    Folder for the CSV report. Created if missing.

.PARAMETER OpenReport
    Opens the CSV in the default application after the run (Windows only).

.EXAMPLE
    .\Get-IntuneComplianceReport.ps1 -TenantId '00000000-0000-0000-0000-000000000000' -OutputPath .\output

.NOTES
    Required Graph scopes (delegated, admin consent prompted at sign-in):
      DeviceManagementManagedDevices.Read.All
      DeviceManagementConfiguration.Read.All
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = '.\output',

    [Parameter(Mandatory = $false)]
    [switch]$OpenReport
)

$ErrorActionPreference = 'Stop'
$requiredScopes = @(
    'DeviceManagementManagedDevices.Read.All',
    'DeviceManagementConfiguration.Read.All'
)

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )
    Write-Host ('{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message)
}

try {
    # --- Module check ----------------------------------------------------------
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
        throw 'Microsoft.Graph.Authentication is not installed. Run: Install-Module Microsoft.Graph.Authentication'
    }
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    Import-Module Microsoft.Graph.DeviceManagement -ErrorAction Stop

    # --- Connect (delegated, least-privilege read) ------------------------------
    Write-Log 'Connecting to Microsoft Graph (interactive sign-in)...'
    $null = Connect-MgGraph -TenantId $TenantId -Scopes $requiredScopes -NoWelcome
    $context = Get-MgContext
    if (-not $context) { throw 'Graph connection failed.' }
    Write-Log "Connected to tenant $($context.TenantId) as $($context.Account)."

    # --- Collect managed devices -------------------------------------------------
    Write-Log 'Retrieving managed devices (all pages)...'
    $devices = Get-MgDeviceManagementManagedDevice -All
    if (-not $devices) {
        Write-Log 'No managed devices returned.' -Level 'WARN'
    }
    Write-Log "Retrieved $($devices.Count) managed device(s)."

    # --- Build the report ----------------------------------------------------------
    $rows = foreach ($device in $devices) {
        # complianceState is a device-level rollup reported by the Intune service.
        [pscustomobject]@{
            DeviceName            = $device.DeviceName
            UserPrincipalName     = $device.UserPrincipalName
            OperatingSystem       = $device.OperatingSystem
            OsVersion             = $device.OsVersion
            ComplianceState       = $device.ComplianceState
            ManagedDeviceOwnerType = $device.ManagedDeviceOwnerType
            EnrolledDateTime      = if ($device.EnrolledDateTime) { $device.EnrolledDateTime.ToString('yyyy-MM-dd HH:mm') } else { $null }
            LastSyncDateTime      = if ($device.LastSyncDateTime) { $device.LastSyncDateTime.ToString('yyyy-MM-dd HH:mm') } else { $null }
            DeviceId              = $device.Id
        }
    }

    # --- Write CSV -------------------------------------------------------------------
    if (-not (Test-Path -LiteralPath $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $csvPath = Join-Path $OutputPath "IntuneComplianceReport-$stamp.csv"
    $rows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

    Write-Log "Report written: $csvPath"
    $compliant = ($rows | Where-Object { $_.ComplianceState -eq 'compliant' }).Count
    Write-Log "Summary: $compliant compliant / $($rows.Count) total device(s)."

    if ($OpenReport -and $rows.Count -gt 0) {
        Start-Process -FilePath $csvPath
    }
}
catch {
    Write-Log "FAILED: $($_.Exception.Message)" -Level 'ERROR'
    throw
}
finally {
    $ctx = Get-MgContext
    if ($ctx) {
        $null = Disconnect-MgGraph
        Write-Log 'Disconnected from Microsoft Graph.'
    }
}
