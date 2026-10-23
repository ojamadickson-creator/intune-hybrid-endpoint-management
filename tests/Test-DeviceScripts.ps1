# Functional tests for the two on-device scripts using session-function mocks.
# Run with: pwsh -NoProfile -File tests/Test-DeviceScripts.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$script1 = Join-Path $root 'scripts\Test-CustomCompliance.ps1'
$script2 = Join-Path $root 'scripts\Get-DeviceInventory.ps1'
. (Join-Path $PSScriptRoot '_Common.ps1')

# The scripts hard-code Windows paths (they run on Windows devices); on the Linux
# test host, Join-Path cannot resolve the C: drive, so mock it to concatenate
# — the inventory test uses a temp path that must still resolve normally.
if (-not $IsWindows) {
    function Join-Path {
        param($Path, $ChildPath)
        if ($Path -match '^[A-Za-z]:\\') { "$Path\$ChildPath" }
        else { Microsoft.PowerShell.Management\Join-Path -Path $Path -ChildPath $ChildPath }
    }
}

# ---- Test-CustomCompliance: mock the queried cmdlets via session functions ----
function Get-ItemProperty { param($Path, $ErrorAction) if ($Path -like '*Terminal Server*') { [pscustomobject]@{ fDenyTSConnections = 1 } } else { throw "not found" } }
function Get-WindowsOptionalFeature { param([switch]$Online, $FeatureName, $ErrorAction) $global:smbState }
function New-Item { param($ItemType, $Path, [switch]$Force) }
function Add-Content { param($Path, $Value, $Encoding) $global:diag += $Value }

# Case 1: RDP refused + SMBv1 explicitly disabled -> both true
$global:smbState = [pscustomobject]@{ State = 'Disabled' }
$global:diag = @()
$out = & $script1
$json = $out | ConvertFrom-Json
Assert-True ($json.RdpDisabled -eq $true) 'custom compliance: RdpDisabled true when fDenyTSConnections=1'
Assert-True ($json.Smbv1Disabled -eq $true) 'custom compliance: Smbv1Disabled true when feature Disabled'
Assert-True (($out | Measure-Object).Count -eq 1) 'custom compliance: single JSON line on stdout'

# Case 2: SMBv1 enabled -> false
$global:smbState = [pscustomobject]@{ State = 'Enabled' }
$out = & $script1 | ConvertFrom-Json
Assert-True ($out.Smbv1Disabled -eq $false) 'custom compliance: Smbv1Disabled false when feature Enabled'

# Case 3: SMBv1 state null/missing -> false (fail-safe)
$global:smbState = $null
$out = & $script1 | ConvertFrom-Json
Assert-True ($out.Smbv1Disabled -eq $false) 'custom compliance: Smbv1Disabled false when state unknown'

# Case 4: feature query throws -> false (fail-safe)
function Get-WindowsOptionalFeature { param($Online, $FeatureName, $ErrorAction) throw 'WOF broken' }
$out = & $script1 | ConvertFrom-Json
Assert-True ($out.Smbv1Disabled -eq $false) 'custom compliance: Smbv1Disabled false when query fails'
Assert-True ($out.RdpDisabled -eq $true) 'custom compliance: RDP check unaffected by SMB failure'

# Case 5: RDP registry missing -> false (fail-safe)
function Get-ItemProperty { param($Path, $ErrorAction) throw 'regkey missing' }
$out = & $script1 | ConvertFrom-Json
Assert-True ($out.RdpDisabled -eq $false) 'custom compliance: RdpDisabled false when registry missing'

# Remove the custom-compliance mocks so the inventory test uses real cmdlets.
Remove-Item Function:Add-Content, Function:New-Item, Function:Join-Path, Function:Get-ItemProperty, Function:Get-WindowsOptionalFeature -ErrorAction SilentlyContinue

# Linux test host lacks SystemDrive; set it so the script's disk matching works.
if (-not $IsWindows) { $env:SystemDrive = 'C:' }

# ---- Get-DeviceInventory: mock all data cmdlets ----
function Get-CimInstance { param($ClassName, $Filter) switch ($ClassName) {
    'Win32_OperatingSystem'    { [pscustomobject]@{ Caption = 'Microsoft Windows 11 Pro'; Version = '10.0.26200'; BuildNumber = '26200'; LastBootUpTime = (Get-Date).AddHours(-2) } }
    'Win32_ComputerSystem'     { [pscustomobject]@{ Manufacturer = 'Contoso'; Model = 'VM'; TotalPhysicalMemory = 8GB; PartOfDomain = $true } }
    'Win32_LogicalDisk'        { @([pscustomobject]@{ DeviceID = 'C:'; DriveType = 3; FreeSpace = 40GB }) }
} }
function Get-Tpm { [pscustomobject]@{ TpmPresent = $true; TpmReady = $true } }
function Confirm-SecureBootUEFI { $true }
function Get-BitLockerVolume { param($MountPoint) [pscustomobject]@{ VolumeStatus = 'FullyEncrypted'; ProtectionStatus = 'On' } }
function Get-MpComputerStatus { [pscustomobject]@{ AMServiceEnabled = $true; AntivirusSignatureLastUpdated = (Get-Date).AddDays(-1) } }

$log = Join-Path ([System.IO.Path]::GetTempPath()) ('device-inventory-test-' + [guid]::NewGuid().ToString() + '.log')
& $script2 -LogPath $log
$exit1 = $LASTEXITCODE
Assert-True ($exit1 -eq 0) "inventory: exit code 0 on success (got $exit1)"
$lines = @(Get-Content -LiteralPath $log)
Assert-True ($lines.Count -eq 1) 'inventory: exactly one log line'
$inv = $lines[0] | ConvertFrom-Json
Assert-True ($inv.ComputerName -eq $env:COMPUTERNAME) 'inventory: JSON parses with ComputerName'
Assert-True ($inv.TpmPresent -eq $true) 'inventory: TpmPresent coerced to bool true'
Assert-True ($inv.SystemDriveFreeGB -gt 30) 'inventory: free space computed'
Remove-Item -LiteralPath $log -Force

# Failure path: make the write fail -> exit 1
function Add-Content { param($LiteralPath, $Path, $Value, $Encoding) throw 'disk full' }
$log2 = Join-Path ([System.IO.Path]::GetTempPath()) ('device-inventory-test-' + [guid]::NewGuid().ToString() + '.log')
& $script2 -LogPath $log2 2>$null
$exit2 = $LASTEXITCODE
Assert-True ($exit2 -eq 1) "inventory: exit code 1 when log write fails (got $exit2)"

exit $global:fail
