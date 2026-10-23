# Script Tests

Static and functional checks for the PowerShell in `scripts/`. The functional tests mock the Windows-only cmdlets (registry, TPM, BitLocker, CIM) so the on-device scripts can be exercised on any host, including Linux CI.

Run both:

```powershell
pwsh -NoProfile -File tests/Parse-Check.ps1        # AST parse of every script
pwsh -NoProfile -File tests/Test-DeviceScripts.ps1 # functional tests with mocks
```

Covered:

- Parse check: every script in `scripts/` compiles without syntax errors (PowerShell 7.4).
- `Test-CustomCompliance.ps1` — RDP pass case, SMBv1 explicit-disabled pass case, enabled/unknown/failed fail-safe cases, stdout emits exactly one JSON line.
- `Get-DeviceInventory.ps1` — successful run writes one JSON log line and exits 0; failed log write exits 1.

The Graph scripts (`Add-IntuneBulkAssignment.ps1`, `Sync-IntuneDevices.ps1`, `Get-IntuneComplianceReport.ps1`) are parse-checked here; their logic requires a live Graph connection and is exercised in the lab per the guide.
