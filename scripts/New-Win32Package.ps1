<#
.SYNOPSIS
    Packages a Windows installer into the .intunewin format for Microsoft Intune Win32 app upload.

.DESCRIPTION
    Wraps the official Microsoft Win32 Content Prep Tool (IntuneWinAppUtil.exe) with input
    validation, MSI product-code extraction (needed for the Intune MSI detection rule),
    structured logging, and exit-code handling.

    The tool and its command-line parameters are documented by Microsoft at:
    https://learn.microsoft.com/mem/intune/apps/apps-win32-prepare
    https://github.com/microsoft/microsoft-win32-content-prep-tool

.PARAMETER SetupFolder
    Folder that contains all setup files for the app (the -c parameter of IntuneWinAppUtil).

.PARAMETER SetupFile
    The main setup file inside SetupFolder, e.g. 7z2409-x64.msi (the -s parameter).

.PARAMETER IntuneWinAppUtilPath
    Full path to IntuneWinAppUtil.exe downloaded from the Microsoft Win32 Content Prep Tool repo.

.PARAMETER OutputFolder
    Folder where the .intunewin file is written (the -o parameter).

.PARAMETER LogPath
    Folder for the script's own log file. The log is appended, never overwritten.

.EXAMPLE
    .\New-Win32Package.ps1 -SetupFolder 'C:\Staging\7zip' -SetupFile '7z2409-x64.msi' `
        -IntuneWinAppUtilPath 'C:\Tools\IntuneWinAppUtil.exe' -OutputFolder 'C:\Staging\output' -LogPath 'C:\Staging\logs'

.NOTES
    Output: <SetupFile base name>.intunewin in OutputFolder, plus the MSI product code printed
    to the console and written to the log for use in the Intune detection rule.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SetupFolder,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SetupFile,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$IntuneWinAppUtilPath,

    [Parameter(Mandatory = $false)]
    [string]$OutputFolder = '.\output',

    [Parameter(Mandatory = $false)]
    [string]$LogPath = '.\logs'
)

$ErrorActionPreference = 'Stop'

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    Add-Content -Path (Join-Path $script:LogDir 'New-Win32Package.log') -Value $line -Encoding UTF8
}

function Get-MsiProductCode {
    param([Parameter(Mandatory = $true)][string]$MsiPath)
    # Reads the ProductCode property via the Windows Installer COM interface.
    $installer = $null
    $database  = $null
    $view     = $null
    try {
        $installer = New-Object -ComObject WindowsInstaller.Installer
        $database  = $installer.GetType().InvokeMember('OpenDatabase', 'InvokeMethod', $null, $installer, @($MsiPath, 0))
        $view      = $database.GetType().InvokeMember('OpenView', 'InvokeMethod', $null, $database, @('SELECT `Value` FROM Property WHERE `Property` = ''ProductCode'''))
        $view.GetType().InvokeMember('Execute', 'InvokeMethod', $null, $view, $null) | Out-Null
        $record = $view.GetType().InvokeMember('Fetch', 'InvokeMethod', $null, $view, $null)
        if ($null -eq $record) { throw "ProductCode not found in $MsiPath" }
        return $record.GetType().InvokeMember('StringData', 'GetProperty', $null, $record, @(1))
    }
    finally {
        foreach ($obj in @($view, $database, $installer)) {
            if ($null -ne $obj) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($obj) }
        }
    }
}

# --- Initialization -----------------------------------------------------------
$script:LogDir = if ([System.IO.Path]::IsPathRooted($LogPath)) { $LogPath } else { Join-Path (Get-Location) $LogPath }
try {
    if (-not (Test-Path -LiteralPath $script:LogDir)) {
        New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null
    }
}
catch {
    throw "Cannot create log directory '$script:LogDir': $($_.Exception.Message)"
}

try {
    Write-Log 'Starting Win32 packaging job.'

    # --- Input validation ----------------------------------------------------
    if (-not (Test-Path -LiteralPath $SetupFolder -PathType Container)) {
        throw "Setup folder not found: $SetupFolder"
    }
    $setupFilePath = Join-Path $SetupFolder $SetupFile
    if (-not (Test-Path -LiteralPath $setupFilePath -PathType Leaf)) {
        throw "Setup file not found: $setupFilePath"
    }
    if (-not (Test-Path -LiteralPath $IntuneWinAppUtilPath -PathType Leaf)) {
        throw "IntuneWinAppUtil.exe not found: $IntuneWinAppUtilPath (download from https://github.com/microsoft/microsoft-win32-content-prep-tool)"
    }
    if (-not (Test-Path -LiteralPath $OutputFolder)) {
        New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
        Write-Log "Created output folder: $OutputFolder"
    }

    # --- MSI product code (used later for the Intune detection rule) ---------
    $productCode = $null
    if ($SetupFile -like '*.msi') {
        $productCode = Get-MsiProductCode -MsiPath $setupFilePath
        Write-Log "MSI ProductCode: $productCode"
    }
    else {
        Write-Log 'Setup file is not an MSI; skipping product-code extraction (use a file or custom detection rule).' -Level 'WARN'
    }

    # --- Run the Microsoft Win32 Content Prep Tool ---------------------------
    # Paths are passed as a single quoted argument string so folders with spaces survive.
    Write-Log "Running IntuneWinAppUtil for '$SetupFile'..."
    $argString = '-c "{0}" -s "{1}" -o "{2}" -q' -f $SetupFolder, $setupFilePath, $OutputFolder
    $proc = Start-Process -FilePath $IntuneWinAppUtilPath -ArgumentList $argString -NoNewWindow -PassThru -Wait
    if ($proc.ExitCode -ne 0) {
        throw "IntuneWinAppUtil exited with code $($proc.ExitCode)."
    }

    # --- Verify output --------------------------------------------------------
    $expectedOutput = Join-Path $OutputFolder ([System.IO.Path]::GetFileNameWithoutExtension($SetupFile) + '.intunewin')
    if (-not (Test-Path -LiteralPath $expectedOutput -PathType Leaf)) {
        throw "Expected package was not created: $expectedOutput"
    }

    $sizeMB = [math]::Round((Get-Item -LiteralPath $expectedOutput).Length / 1MB, 2)
    Write-Log "Package created: $expectedOutput ($sizeMB MB)"
    Write-Log 'Packaging job completed successfully.'

    [pscustomobject]@{
        Package     = $expectedOutput
        SizeMB      = $sizeMB
        ProductCode = $productCode
    }
}
catch {
    Write-Log "FAILED: $($_.Exception.Message)" -Level 'ERROR'
    throw
}
