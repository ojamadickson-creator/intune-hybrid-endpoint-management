# Shared assertions for the functional test scripts.
# Sets $global:fail to 1 when any assertion fails; test scripts dot-source
# this file and end with `exit $global:fail` so the process exit code
# reflects failures (0 = all passed, 1 = at least one failure).
$global:fail = 0

function Assert-True {
    param($cond, $name)
    if ($cond) { Write-Output "OK   $name" }
    else { $global:fail = 1; Write-Output "FAIL $name" }
}

function Assert-Equal {
    param($expected, $actual, $name)
    if ($expected -eq $actual) { Write-Output "OK   $name" }
    else { $global:fail = 1; Write-Output "FAIL $name (expected: <$expected>, actual: <$actual>)" }
}
