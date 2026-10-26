# Evidence Checklist

Every work package in `docs/implementation-ledger.md` has an evidence item. Capture the screenshot or command output at the moment the step succeeds, name it with the code below, and commit it under `evidence/`. Nothing ships to a portfolio repo unverified: if an item cannot be captured, the step is not done.

## Redaction Rules (Before Committing)

Evidence from a real tenant contains secrets. Before committing any capture:

- **Never capture actual BitLocker recovery passwords.** For E-12, show the key's existence (key ID + date) with the key value itself cropped, covered, or blurred. The Entra "BitLocker keys" blade and `manage-bde` output both display full recovery passwords — redact them.
- Never capture real passwords, LAPS passwords, MFA codes, or sign-in session tokens.
- Crop or blur license/product **keys**; license *assignments* are fine to show.
- Trial tenants with throwaway data still follow these rules — screenshots get reused and recycled.
- When in doubt, redact and note in the commit message what was hidden.

| Code | Evidence | Where to capture | Package |
|---|---|---|---|
| E-01 | Business Premium licenses assigned to `jdoe` and the admin account | M365 admin center > Billing > Licenses (or Users > Active users) | 1 |
| E-02 | Entra Connect sync complete: `jdoe` visible in Entra with source "Windows Server AD"; sync service export shows no errors | Entra admin center > Identity > Users; Entra Connect portal sync service view | 2 |
| E-03 | SCP present in AD and hybrid join configured | Discovery query on DC01: `$configNC = (Get-ADRootDSE).ConfigurationNamingContext; Get-ADObject -SearchBase "CN=Device Registration Configuration,CN=Services,$configNC" -SearchScope Subtree -Filter * -Properties cn` shows the SCP object; Entra Connect "Configuration complete" page | 3 |
| E-04 | MDM user scope = Some (pilot group); device limit and platform restriction policy created | Intune admin center > Devices > Device onboarding > Enrollment | 4 |
| E-05 | `Cfg-AutoMDMEnrollment` GPO linked to Workstations OU, settings applied on CLIENT01 | GPMC report; `gpresult /r` on CLIENT01 | 5 |
| E-06 | Dynamic groups with membership rules and validation results | Entra admin center > Groups (rule builder + "Validate rules" output) | 6 |
| E-07 | CLIENT01 hybrid-joined and enrolled: `dsregcmd /status` shows AzureAdJoined YES + DomainJoined YES, MDM enrollment URL; device object in Intune | `dsregcmd /status` on CLIENT01; Intune admin center > Devices > All devices | 7 |
| E-08 | Tenant compliance setting + `CMP-Win11-Health` policy assigned to pilot group | Intune admin center > Devices > Compliance | 8 |
| E-09 | `CMP-Win11-Custom` policy with discovery script + JSON; custom setting results visible in per-setting status | Devices > Compliance > policy > Monitor > Per-setting status | 9 |
| E-10 | `SB-MDM-Win11` baseline assigned; device-level assignment status shows "Succeeded" | Endpoint security > Security baselines > profile | 10 |
| E-11 | Defender for Business portal showing CLIENT01 onboarded; AV + firewall policies assigned in Intune | Defender portal > Assets > Devices; Intune Endpoint security > Antivirus / Firewall | 11 |
| E-12 | BitLocker enabled on CLIENT01 OS drive; recovery key escrowed to Entra | `manage-bde -status`; Entra admin center device > BitLocker keys; Intune encryption report | 12 |
| E-13 | Both configuration profiles assigned with device status "Succeeded" | Devices > Manage devices > Configuration | 13 |
| E-14 | Update ring assigned; CLIENT01 reporting under the ring | Devices > By platform > Windows > Manage updates > Update rings | 14 |
| E-15 | M365 Apps installed on CLIENT01; 7-Zip installed via Win32; MSIX app installed via LOB + trusted cert profile; inventory script output in log file | Settings > Apps > Installed apps on CLIENT01; Intune Apps > All apps install status; `C:\ProgramData\Beginningdimension\Logs\DeviceInventory.log` | 15 |
| E-16 | Conditional Access policies in report-only then On; sign-in log showing policy applied and device compliance gate | Intune admin center > Conditional Access node; Entra admin center > Monitoring > Sign-in logs | 16 |
| E-17 | `.intunewin` package generated with log output | Console output of `New-Win32Package.ps1` | 17 |
| E-18 | Compliance report CSV exported with device rows | Console output + CSV in `scripts\output\` | 18 |


