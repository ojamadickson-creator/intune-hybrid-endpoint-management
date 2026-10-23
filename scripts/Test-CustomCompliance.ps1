<#
.SYNOPSIS
    Intune custom compliance discovery script: checks that RDP is disabled and SMBv1 is removed.

.DESCRIPTION
    Custom compliance discovery script for the CMP-Win11-Custom policy. Intune runs this
    script on the device, then compares its JSON output against the rules in
    custom-compliance-rules.json (schema documented at
    https://learn.microsoft.com/intune/intune-service/protect/compliance-custom-json).

    CRITICAL: the script must write ONLY the result JSON to stdout. Diagnostics go to a
    log file under ProgramData, never to the pipeline - anything written to stderr marks
    evaluation as failed, and stray stdout breaks rule matching.

    The Intune Management Extension runs discovery every 8 hours and when the user selects
    "Check compliance" (https://learn.microsoft.com/intune/intune-service/protect/compliance-use-custom-settings).

    Fail-safe behavior: if a check cannot be verified (missing registry value, query error,
    unknown feature state), the setting reports $false (non-compliant) rather than passing.

    Checks:
      RdpDisabled   - true only when HKLM\...\Terminal Server\fDenyTSConnections = 1 (RDP refused)
      Smbv1Disabled - true only when the SMB1Protocol optional feature state is explicitly not Enabled
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$LogDir  = 'C:\ProgramData\Beginningdimension\Logs'
$LogFile = Join-Path $LogDir 'CustomCompliance.log'

function Write-Diagnostic {
    param([string]$Message)
    try {
        if (-not (Test-Path -LiteralPath $LogDir)) {
            New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        }
        Add-Content -Path $LogFile -Value ('{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message) -Encoding UTF8
    }
    catch {
        # Diagnostics must never pollute stdout; swallow log failures.
    }
}

# --- RDP check: only an explicit fDenyTSConnections = 1 passes ------------------------
$rdpDisabled = $false
try {
    $fDeny = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -ErrorAction Stop).fDenyTSConnections
    $rdpDisabled = ($fDeny -eq 1)
    Write-Diagnostic "fDenyTSConnections=$fDeny -> RdpDisabled=$rdpDisabled"
}
catch {
    Write-Diagnostic "RDP check failed (reported non-compliant): $($_.Exception.Message)"
}

# --- SMBv1 check: only an explicitly disabled feature state passes ---------------------
# Get-WindowsOptionalFeature reports states like Enabled, Disabled, and
# DisabledWithPayloadRemoved. Anything that is not an explicit disabled state
# (Enabled, Pending, unknown, or a query failure) reports non-compliant.
$explicitlyDisabled = @('Disabled', 'DisabledWithPayloadRemoved')
$smbv1Disabled = $false
try {
    $feature = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction Stop
    if ($null -ne $feature -and $feature.State) {
        $smbv1Disabled = $explicitlyDisabled -contains "$($feature.State)"
    }
    Write-Diagnostic "SMB1Protocol=$($feature.State) -> Smbv1Disabled=$smbv1Disabled"
}
catch {
    Write-Diagnostic "SMBv1 check failed (reported non-compliant): $($_.Exception.Message)"
}

# --- Emit ONLY the JSON result to stdout -----------------------------------------------
$result = [ordered]@{
    RdpDisabled   = $rdpDisabled
    Smbv1Disabled = $smbv1Disabled
}
Write-Output ($result | ConvertTo-Json -Compress)
