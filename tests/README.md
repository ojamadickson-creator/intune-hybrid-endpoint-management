# Script Tests

Static and functional checks for the PowerShell in `scripts/`. The functional tests mock the Windows-only cmdlets (registry, TPM, BitLocker, CIM) and the Microsoft Graph session cmdlets so every script can be exercised on any host, including Linux CI — no live tenant is required to run the suite.

Run all three:

```powershell
pwsh -NoProfile -File tests/Parse-Check.ps1          # AST parse of every script
pwsh -NoProfile -File tests/Test-DeviceScripts.ps1   # on-device scripts, mocked cmdlets
pwsh -NoProfile -File tests/Test-BulkAssignment.ps1  # Graph script against a mocked Graph
```

Covered:

- Parse check: every script in `scripts/` compiles without syntax errors (PowerShell 7.4).
- `Test-CustomCompliance.ps1` — RDP pass case, SMBv1 explicit-disabled pass case, enabled/unknown/failed fail-safe cases, stdout emits exactly one JSON line.
- `Get-DeviceInventory.ps1` — successful run writes one JSON log line and exits 0; failed log write exits 1.
- `Add-IntuneBulkAssignment.ps1` — exercised against a mocked `Invoke-MgGraph`/session cmdlet set:
  - happy path (no existing assignments) with a JSON-array backup file;
  - merge behavior: already-assigned group skipped, exclusion targets and assignment-filter targets preserved verbatim;
  - `@odata.nextLink` pagination (all pages read before merging);
  - policy-not-found and ambiguous-policy-name errors (no POST on failure);
  - OData single-quote escaping in `$filter` for policy and group names.
- Assertion helpers live in `tests/_Common.ps1`; every test script exits nonzero if any assertion fails (verified with an intentional failing assertion).

`Sync-IntuneDevices.ps1` and `Get-IntuneComplianceReport.ps1` are parse-checked here; they are thin per-device wrappers over the same Graph patterns and are exercised in the lab per the guide.
