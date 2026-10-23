# Functional tests for Add-IntuneBulkAssignment.ps1 against a mocked Microsoft Graph.
# No live Graph connection is needed: the module/session cmdlets and Invoke-MgGraph
# are replaced with in-process mock functions, and the test drives the script's
# logic through the same Graph call pattern it uses in production.
# Run with: pwsh -NoProfile -File tests/Test-BulkAssignment.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$subject = Join-Path $root 'scripts\Add-IntuneBulkAssignment.ps1'
. (Join-Path $PSScriptRoot '_Common.ps1')

# --- Graph mocks (session functions; removed again at the end of the file) ---
$global:RealGetModule = Get-Command -Name Get-Module -CommandType Cmdlet
$global:RealImportModule = Get-Command -Name Import-Module -CommandType Cmdlet

function global:Get-Module {
    param([string[]]$Name, [switch]$ListAvailable)
    if ($ListAvailable -and $Name -eq 'Microsoft.Graph.Authentication') {
        return [pscustomobject]@{ Name = 'Microsoft.Graph.Authentication'; Version = '2.0.0' }
    }
    return & $global:RealGetModule @PSBoundParameters
}
function global:Import-Module { param($Name, $ErrorAction) } # no-op: modules are not needed with mocks
function global:Connect-MgGraph { param($TenantId, $Scopes, [switch]$NoWelcome) }
function global:Get-MgContext { [pscustomobject]@{ Account = 'mock'; TenantId = 'mock' } }
function global:Disconnect-MgGraph { }

function global:Invoke-MgGraph {
    param([string]$Method, [string]$Uri, [string]$Body, [string]$ContentType)
    $global:Requests += [pscustomobject]@{ Method = $Method; Uri = $Uri }
    if ($Method -eq 'GET') {
        # Policy lookup: deviceManagement/<nav>?$filter=displayName eq '<name>'
        if ($Uri -match 'deviceManagement/(deviceCompliancePolicies|deviceConfigurations)\?\$filter=displayName eq ''(.+)''$') {
            $name = $Matches[2].Replace("''", "'")   # un-escape OData '' back to '
            return @{ value = @($global:Db.Policies[$name]) }
        }
        # Group lookup: groups?$filter=displayName eq '<name>'
        if ($Uri -match 'groups\?\$filter=displayName eq ''(.+)''$') {
            $name = $Matches[1].Replace("''", "'")
            return @{ value = @($global:Db.Groups[$name]) }
        }
        # Assignments collection (first page)
        if ($Uri -match 'deviceManagement/(deviceCompliancePolicies|deviceConfigurations)/([^/]+)/assignments$') {
            return $global:Db.Page1
        }
        # @odata.nextLink continuation
        if ($Uri -eq $global:Db.NextLinkUri) { return $global:Db.Page2 }
        throw "mock: unhandled GET $Uri"
    }
    if ($Uri -match '/assign$') {
        $global:PostedAssign = $Body | ConvertFrom-Json
        return @{ value = @() }
    }
    throw "mock: unhandled POST $Uri"
}

function Reset-Mock {
    param($Policies, $Groups, $Page1, $Page2 = $null, $NextLinkUri = $null)
    $global:Db = @{
        Policies    = $Policies
        Groups      = $Groups
        Page1       = $Page1
        Page2       = $Page2
        NextLinkUri = $NextLinkUri
    }
    $global:Requests = @()
    $global:PostedAssign = $null
}

function New-Group { param($Id) @{ id = $Id } }
function New-Policy { param($Id) @{ id = $Id } }
function New-Assignment { param($Target) @{ id = ([guid]::NewGuid().ToString()); target = $Target } }
function GroupTarget { param($Id) @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $Id } }
function ExclusionTarget { param($Id) @{ '@odata.type' = '#microsoft.graph.exclusionGroupAssignmentTarget'; groupId = $Id } }
function FilterTarget { param($Id, $FilterId) @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $Id; deviceAndAppManagementAssignmentFilterId = $FilterId; deviceAndAppManagementAssignmentFilterType = 'include' } }

function Invoke-Subject {
    param([string]$PolicyName, [string[]]$GroupNames, [string]$BackupPath)
    $global:SubjectThrew = $null
    try {
        & $subject -PolicyType Compliance -PolicyName $PolicyName -GroupNames $GroupNames -TenantId '00000000-0000-0000-0000-000000000000' -BackupPath $BackupPath 6>&1 | Out-Null
    }
    catch {
        $global:SubjectThrew = $_
    }
}

# --- T1: empty policy, one new group -> single target, backup is an empty JSON array ---
$bk1 = Join-Path ([System.IO.Path]::GetTempPath()) ('bulk-test-' + [guid]::NewGuid().ToString())
$null = New-Item -ItemType Directory -Path $bk1 -Force
Reset-Mock -Policies @{ 'CMP-Win11-Health' = @(New-Policy 'pol-1') } `
    -Groups @{ 'GRP-INT-Pilot-Devices' = @(New-Group 'grp-pilot') } `
    -Page1 @{ value = @() }
Invoke-Subject -PolicyName 'CMP-Win11-Health' -GroupNames 'GRP-INT-Pilot-Devices' -BackupPath $bk1
Assert-True ($null -eq $global:SubjectThrew) 'T1: script succeeds with no existing assignments'
$targets = @($global:PostedAssign.assignments | ForEach-Object { $_.target })
Assert-Equal 1 $targets.Count 'T1: one target posted'
Assert-Equal 'grp-pilot' $targets[0].groupId 'T1: posted target is the requested group'
Assert-Equal '#microsoft.graph.groupAssignmentTarget' $targets[0].'@odata.type' 'T1: posted target is a group assignment target'
$backup = Get-ChildItem -LiteralPath $bk1 -Filter 'assignments-backup-*.json'
Assert-Equal 1 @($backup).Count 'T1: one backup file written'
$raw = Get-Content -LiteralPath $backup[0].FullName -Raw
Assert-True ($raw.TrimStart().StartsWith('[')) 'T1: backup root is a JSON array'
$parsed = @($raw | ConvertFrom-Json)
Assert-True (($parsed -is [array]) -and ($parsed.Count -eq 0)) 'T1: backup of empty assignment list is a JSON array with zero elements'
Remove-Item -LiteralPath $bk1 -Recurse -Force

# --- T2: existing group skipped; exclusion and filter targets preserved verbatim ---
$bk2 = Join-Path ([System.IO.Path]::GetTempPath()) ('bulk-test-' + [guid]::NewGuid().ToString())
$null = New-Item -ItemType Directory -Path $bk2 -Force
Reset-Mock -Policies @{ 'CMP-Win11-Health' = @(New-Policy 'pol-1') } `
    -Groups @{
        'GRP-INT-Pilot-Devices'  = @(New-Group 'grp-pilot')
        'GRP-INT-Win11-Corporate' = @(New-Group 'grp-corp')
    } `
    -Page1 @{ value = @(
        (New-Assignment (GroupTarget 'grp-pilot'))
        (New-Assignment (ExclusionTarget 'grp-blocked'))
        (New-Assignment (FilterTarget 'grp-filtered' 'f1'))
    ) }
Invoke-Subject -PolicyName 'CMP-Win11-Health' -GroupNames @('GRP-INT-Pilot-Devices', 'GRP-INT-Win11-Corporate') -BackupPath $bk2
Assert-True ($null -eq $global:SubjectThrew) 'T2: script succeeds with mixed existing targets'
$targets = @($global:PostedAssign.assignments | ForEach-Object { $_.target })
Assert-Equal 4 $targets.Count 'T2: existing 3 targets + 1 new = 4 posted'
$excl = @($targets | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.exclusionGroupAssignmentTarget' })
Assert-Equal 1 $excl.Count 'T2: exclusion target preserved'
Assert-Equal 'grp-blocked' $excl[0].groupId 'T2: exclusion target group preserved'
$filt = @($targets | Where-Object { $_.groupId -eq 'grp-filtered' })
Assert-Equal 'f1' $filt[0].deviceAndAppManagementAssignmentFilterId 'T2: assignment filter preserved on existing target'
Assert-Equal 'include' $filt[0].deviceAndAppManagementAssignmentFilterType 'T2: assignment filter type preserved'
Assert-True ((@($targets | Where-Object { $_.groupId -eq 'grp-pilot' }).Count -eq 1) -and (@($targets | Where-Object { $_.groupId -eq 'grp-corp' }).Count -eq 1)) 'T2: already-assigned group not duplicated, new group added once'
$backup = Get-ChildItem -LiteralPath $bk2 -Filter 'assignments-backup-*.json'
$raw = Get-Content -LiteralPath $backup[0].FullName -Raw
Assert-True ($raw.TrimStart().StartsWith('[')) 'T2: backup root is a JSON array'
$parsed = @($raw | ConvertFrom-Json)
Assert-True ($parsed -is [array]) 'T2: backup file parses as a JSON array'
Assert-Equal 3 $parsed.Count 'T2: backup contains all three pre-existing assignments'
Remove-Item -LiteralPath $bk2 -Recurse -Force

# --- T3: @odata.nextLink pagination - all pages read before merging ---
$bk3 = Join-Path ([System.IO.Path]::GetTempPath()) ('bulk-test-' + [guid]::NewGuid().ToString())
$null = New-Item -ItemType Directory -Path $bk3 -Force
$nextUri = 'https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicies/pol-1/assignments?%24skiptoken=mock'
Reset-Mock -Policies @{ 'CMP-Win11-Health' = @(New-Policy 'pol-1') } `
    -Groups @{ 'GRP-INT-Win11-Corporate' = @(New-Group 'grp-corp') } `
    -Page1 @{ value = @((New-Assignment (GroupTarget 'grp-a'))); '@odata.nextLink' = $nextUri } `
    -Page2 @{ value = @((New-Assignment (GroupTarget 'grp-b')), (New-Assignment (GroupTarget 'grp-c'))) } `
    -NextLinkUri $nextUri
Invoke-Subject -PolicyName 'CMP-Win11-Health' -GroupNames 'GRP-INT-Win11-Corporate' -BackupPath $bk3
Assert-True ($null -eq $global:SubjectThrew) 'T3: script succeeds across paginated assignments'
Assert-True (@($global:Requests | Where-Object { $_.Uri -eq $nextUri }).Count -eq 1) 'T3: nextLink page requested exactly once'
$targets = @($global:PostedAssign.assignments | ForEach-Object { $_.target })
Assert-Equal 4 $targets.Count 'T3: 2 pages (3 existing) + 1 new = 4 posted'
Assert-True (($targets | Where-Object { $_.groupId -eq 'grp-a' }) -and ($targets | Where-Object { $_.groupId -eq 'grp-c' })) 'T3: targets from both pages included'
Remove-Item -LiteralPath $bk3 -Recurse -Force

# --- T7: single existing assignment, requested group already assigned -> no-op ---
$bk7 = Join-Path ([System.IO.Path]::GetTempPath()) ('bulk-test-' + [guid]::NewGuid().ToString())
$null = New-Item -ItemType Directory -Path $bk7 -Force
Reset-Mock -Policies @{ 'CMP-Win11-Health' = @(New-Policy 'pol-1') } `
    -Groups @{ 'GRP-INT-Pilot-Devices' = @(New-Group 'grp-pilot') } `
    -Page1 @{ value = @((New-Assignment (GroupTarget 'grp-pilot'))) }
Invoke-Subject -PolicyName 'CMP-Win11-Health' -GroupNames 'GRP-INT-Pilot-Devices' -BackupPath $bk7
Assert-True ($null -eq $global:SubjectThrew) 'T7: already-assigned group is a no-op, not an error'
Assert-True ($null -eq $global:PostedAssign) 'T7: no assign POST when nothing needs adding'
Assert-True (@($global:Requests | Where-Object { $_.Method -eq 'POST' }).Count -eq 0) 'T7: zero POST requests issued'
$backup = Get-ChildItem -LiteralPath $bk7 -Filter 'assignments-backup-*.json'
$raw = Get-Content -LiteralPath $backup[0].FullName -Raw
Assert-True ($raw.TrimStart().StartsWith('[')) 'T7: backup root is a JSON array'
$parsed = @($raw | ConvertFrom-Json)
Assert-True (($parsed -is [array]) -and ($parsed.Count -eq 1)) 'T7: backup of a single assignment is a JSON array with one element'
Remove-Item -LiteralPath $bk7 -Recurse -Force

# --- T4: policy not found -> script throws, nothing posted ---
$bk4 = Join-Path ([System.IO.Path]::GetTempPath()) ('bulk-test-' + [guid]::NewGuid().ToString())
$null = New-Item -ItemType Directory -Path $bk4 -Force
Reset-Mock -Policies @{} -Groups @{ 'GRP-INT-Pilot-Devices' = @(New-Group 'grp-pilot') } -Page1 @{ value = @() }
Invoke-Subject -PolicyName 'CMP-Missing' -GroupNames 'GRP-INT-Pilot-Devices' -BackupPath $bk4
Assert-True ($null -ne $global:SubjectThrew) 'T4: missing policy makes the script throw'
Assert-True ($global:SubjectThrew.Exception.Message -match 'not found') 'T4: error names the missing policy'
Assert-True ($null -eq $global:PostedAssign) 'T4: no assign POST when policy is missing'
Remove-Item -LiteralPath $bk4 -Recurse -Force

# --- T5: ambiguous policy name (two matches) -> script throws ---
$bk5 = Join-Path ([System.IO.Path]::GetTempPath()) ('bulk-test-' + [guid]::NewGuid().ToString())
$null = New-Item -ItemType Directory -Path $bk5 -Force
Reset-Mock -Policies @{ 'CMP-Dup' = @((New-Policy 'pol-a'), (New-Policy 'pol-b')) } `
    -Groups @{ 'GRP-INT-Pilot-Devices' = @(New-Group 'grp-pilot') } -Page1 @{ value = @() }
Invoke-Subject -PolicyName 'CMP-Dup' -GroupNames 'GRP-INT-Pilot-Devices' -BackupPath $bk5
Assert-True ($null -ne $global:SubjectThrew) 'T5: ambiguous policy name makes the script throw'
Assert-True ($global:SubjectThrew.Exception.Message -match 'matches 2 policies') 'T5: error reports the ambiguity'
Remove-Item -LiteralPath $bk5 -Recurse -Force

# --- T6: OData single-quote escaping in $filter ---
$bk6 = Join-Path ([System.IO.Path]::GetTempPath()) ('bulk-test-' + [guid]::NewGuid().ToString())
$null = New-Item -ItemType Directory -Path $bk6 -Force
Reset-Mock -Policies @{ "CMP-O'Neil" = @(New-Policy 'pol-1') } `
    -Groups @{ "GRP-O'Neil" = @(New-Group 'grp-oneil') } -Page1 @{ value = @() }
Invoke-Subject -PolicyName "CMP-O'Neil" -GroupNames "GRP-O'Neil" -BackupPath $bk6
Assert-True ($null -eq $global:SubjectThrew) 'T6: apostrophe in names does not fail the run'
Assert-True (@($global:Requests | Where-Object { $_.Uri -like "*eq 'CMP-O''Neil'" }).Count -eq 1) 'T6: policy $filter escapes the apostrophe'
Assert-True (@($global:Requests | Where-Object { $_.Uri -like "*eq 'GRP-O''Neil'" }).Count -eq 1) 'T6: group $filter escapes the apostrophe'
Assert-Equal 'grp-oneil' @($global:PostedAssign.assignments | ForEach-Object { $_.target })[0].groupId 'T6: assignment still resolves to the right group'
Remove-Item -LiteralPath $bk6 -Recurse -Force

# Remove the mocks again so nothing leaks into other scripts run in this session.
Remove-Item Function:Get-Module, Function:Import-Module, Function:Connect-MgGraph, Function:Get-MgContext, Function:Disconnect-MgGraph, Function:Invoke-MgGraph -ErrorAction SilentlyContinue

exit $global:fail
