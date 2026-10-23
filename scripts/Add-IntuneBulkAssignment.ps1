<#
.SYNOPSIS
    Adds one or more Entra ID groups to an Intune policy's assignments via Microsoft Graph.

.DESCRIPTION
    Demonstrates assignment automation for Intune compliance and device-configuration
    policies. The Graph "assign" action REPLACES the policy's full assignment list, so
    this script first reads the current assignments, merges the requested groups while
    preserving every existing target unchanged (including exclusions and assignment
    filters), backs up the current assignments to a JSON file, and posts the combined list.

    Supported policy types: Compliance (deviceCompliancePolicies) and Configuration
    (deviceConfigurations). Other Intune objects (security baselines, Settings Catalog
    profiles) use different assignment models and are out of scope for this script.

.PARAMETER PolicyType
    'Compliance' or 'Configuration'.

.PARAMETER PolicyName
    Exact display name of the policy in Intune, e.g. 'CMP-Win11-Health'.

.PARAMETER GroupNames
    One or more Entra ID group display names to add as included assignments.

.PARAMETER TenantId
    The Entra tenant ID.

.EXAMPLE
    .\Add-IntuneBulkAssignment.ps1 -PolicyType Compliance -PolicyName 'CMP-Win11-Health' `
        -GroupNames 'GRP-INT-Win11-Corporate' -TenantId '00000000-0000-0000-0000-000000000000'

.NOTES
    Required Graph scopes (delegated):
      DeviceManagementConfiguration.ReadWrite.All
      Group.Read.All

    The script resolves the invoke cmdlet by name (Invoke-MgGraph in current SDK
    releases; Invoke-MgGraphRequest also ships in current Microsoft.Graph.Authentication
    releases), which keeps it working across module versions.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Compliance', 'Configuration')]
    [string]$PolicyType,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$GroupNames,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$BackupPath = '.\output'
)

$ErrorActionPreference = 'Stop'
$requiredScopes = @(
    'DeviceManagementConfiguration.ReadWrite.All',
    'Group.Read.All'
)

$policyTypesMap = @{
    'Compliance'     = 'deviceCompliancePolicies'
    'Configuration'  = 'deviceConfigurations'
}

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
    Import-Module Microsoft.Graph.Groups -ErrorAction Stop

    Write-Log 'Connecting to Microsoft Graph (interactive sign-in)...'
    $null = Connect-MgGraph -TenantId $TenantId -Scopes $requiredScopes -NoWelcome
    if (-not (Get-MgContext)) { throw 'Graph connection failed.' }

    # --- Resolve the policy (exact match required) -------------------------------------
    $nav = $policyTypesMap[$PolicyType]
    $filterName = ConvertTo-ODataLiteral -Value $PolicyName
    $policy = Invoke-Graph -Method GET -Uri "https://graph.microsoft.com/v1.0/deviceManagement/${nav}?`$filter=displayName eq '$filterName'"
    if (-not $policy.value) {
        throw "Policy '$PolicyName' not found under $nav (exact display-name match required)."
    }
    if ($policy.value.Count -gt 1) {
        throw "Policy name '$PolicyName' matches $($policy.value.Count) policies; rename for an unambiguous match."
    }
    $policyId = $policy.value[0].id
    Write-Log "Found policy '$PolicyName' (id: $policyId)."

    # --- Resolve the groups ---------------------------------------------------------------
    $groupIds = foreach ($name in $GroupNames) {
        $filterGroup = ConvertTo-ODataLiteral -Value $name
        $groups = Invoke-Graph -Method GET -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$filterGroup'"
        if (-not $groups.value) { throw "Group '$name' not found in Entra ID." }
        if ($groups.value.Count -gt 1) { throw "Group name '$name' matches $($groups.value.Count) groups; rename for an unambiguous match." }
        Write-Log "Resolved group '$name' ($($groups.value[0].id))."
        $groups.value[0].id
    }

    # --- Read current assignments (assign REPLACES the list, so preserve everything) ----
    # Follow @odata.nextLink so the complete collection is read, not just the last page.
    $allAssignments = @()
    $current = Invoke-Graph -Method GET -Uri "https://graph.microsoft.com/v1.0/deviceManagement/$nav/$policyId/assignments"
    $allAssignments += $current.value
    while ($current.'@odata.nextLink') {
        $current = Invoke-Graph -Method GET -Uri $current.'@odata.nextLink'
        $allAssignments += $current.value
    }
    $existingTargets = @()
    foreach ($a in $allAssignments) {
        $existingTargets += $a.target   # kept verbatim: filters, exclusions, and group targets
    }

    # --- Back up the complete current assignments before changing anything -----------------
    if (-not (Test-Path -LiteralPath $BackupPath)) {
        New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupFile = Join-Path $BackupPath "assignments-backup-$([System.IO.Path]::GetFileName($nav))-$stamp.json"
    # Wrap in @() so ConvertTo-Json emits a JSON array even for a single assignment.
    ConvertTo-Json -InputObject @($allAssignments) -Depth 8 | Set-Content -Path $backupFile -Encoding UTF8
    Write-Log "Current assignments backed up to: $backupFile"

    $existingGroupIds = @(
        $existingTargets |
            Where-Object { $_.'@odata.type' -eq '#microsoft.graph.groupAssignmentTarget' } |
            ForEach-Object { $_.groupId }
    )

    # --- Merge: existing targets are reused verbatim; only new group targets are built ----
    $added = 0
    foreach ($gid in $groupIds) {
        if ($gid -in $existingGroupIds) {
            Write-Log "Group $gid is already assigned; skipping." -Level 'WARN'
            continue
        }
        $existingTargets += @{
            '@odata.type' = '#microsoft.graph.groupAssignmentTarget'
            groupId        = $gid
        }
        # Keep the membership check current in case the same group is listed twice.
        $existingGroupIds += $gid
        $added++
    }

    if ($added -eq 0) {
        Write-Log 'Nothing to do - all requested groups are already assigned.'
        return
    }

    # --- POST the merged assignment list ---------------------------------------------------
    $body = @{ assignments = @($existingTargets | ForEach-Object { @{ target = $_ } }) } | ConvertTo-Json -Depth 8
    $null = Invoke-Graph -Method POST -Uri "https://graph.microsoft.com/v1.0/deviceManagement/$nav/$policyId/assign" -Body $body
    Write-Log "Assigned $added group(s); all pre-existing targets preserved. Total targets: $($existingTargets.Count)."
    Write-Log "Verify in the admin center: the policy's Assignments list should now include $($GroupNames -join ', ')."
    Write-Log "Rollback: restore from the backup file using the same assign action, or edit assignments in the admin center."
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
