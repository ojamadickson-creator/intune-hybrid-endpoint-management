# Parse-check harness: reports syntax errors for every script.
$ErrorActionPreference = 'Stop'
$fail = 0
Get-ChildItem "$PSScriptRoot\..\scripts\*.ps1" | ForEach-Object {
    $tokens = $null; $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) {
        $fail = 1
        Write-Output "FAIL $($_.Name)"
        $errors | ForEach-Object { Write-Output "  line $($_.Extent.StartLineNumber): $($_.Message)" }
    } else {
        Write-Output "OK   $($_.Name)"
    }
}
exit $fail
