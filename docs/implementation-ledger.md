# Implementation Ledger

The Intune implementation is divided into 20 work packages: 16 performed in the Microsoft Intune admin center and 4 executed as PowerShell. 16/20 = 80% Intune admin center (GUI), 4/20 = 20% PowerShell.

## Counting Rules

- The denominator is **Intune implementation work packages** — not clicks, screens, or minutes.
- A package counts as **Intune GUI** when every configuration step in it is performed in the Microsoft Intune admin center — including its Conditional Access node, which Microsoft documents as the same Conditional Access node as the Entra admin center's and as the place where device-based Conditional Access policies for Microsoft 365 products are configured ([Conditional Access with Intune](https://learn.microsoft.com/en-us/mem/intune/protect/conditional-access-intune-common-ways-use)).
- A package counts as **PowerShell** when the actual work is a script: a local Microsoft Graph PowerShell SDK / tooling script (packaging, reporting) or a script that executes on managed devices through Intune's platform-scripts and custom-compliance features — the "Intune PowerShell scripts" the ratio was defined for. The GUI upload that delivers an on-device script is part of its deployment package, but the executable work is PowerShell.
- **Foundation prerequisites are outside the ratio and disclosed below**: tenant licensing, UPN/domain preparation, the Defender for Business tenant connection (a Defender-portal wizard, not Intune admin center work), Entra Connect installation, hybrid join (SCP), the automatic-enrollment GPO, dynamic groups, and AD-side changes. These make the Intune work possible; the guide walks through them because the project must be reproducible end-to-end.

## Intune Admin Center Packages (16)

| # | Package | Guide section | Evidence |
|---|---|---|---|
| G1 | Enrollment: automatic enrollment (MDM user scope, MAM scope) | 4 | E-04 |
| G2 | Enrollment: platform restrictions + device limit restriction | 4 | E-04 |
| G3 | Tenant compliance settings + compliance notification template | 8 | E-08 |
| G4 | Compliance policy `CMP-Win11-Health` + actions for noncompliance | 8 | E-08 |
| G5 | Custom compliance policy `CMP-Win11-Custom` (script + JSON upload) | 9 | E-09 |
| G6 | MDM security baseline `SB-MDM-Win11` | 10 | E-10 |
| G7 | Antivirus policy `ES-AV-Defender` | 11 | E-11 |
| G8 | Firewall policy `ES-FW-Win11` | 11 | E-11 |
| G9 | BitLocker policy `ES-BitLocker-Win11` | 12 | E-12 |
| G10 | Device restrictions profile `CFG-Workstation-Restrictions` | 13 | E-13 |
| G11 | Settings Catalog profile `CFG-OneDrive-Win11` (OneDrive known folder move) | 13 | E-13 |
| G12 | Update ring `UPD-Win11-Ring1-Pilot` | 14 | E-14 |
| G13 | Microsoft 365 Apps suite `APP-M365Apps-Business` | 15a | E-15 |
| G14 | Win32 app `APP-7zip-Win32` | 15b | E-15 |
| G16 | Conditional Access: `CA-MFA-AllUsers` and `CA-RequireCompliantDevice` (Intune admin center Conditional Access node) | 16 | E-16 |

## PowerShell Packages (4)

| # | Package | Artifact | Guide section | Evidence |
|---|---|---|---|---|
| P1 | Win32 app packaging (local PowerShell wrapping the Microsoft content prep tool) | `New-Win32Package.ps1` | 17 | E-17 |
| P2 | Graph compliance reporting export | `Get-IntuneComplianceReport.ps1` | 18 | E-18 |
| P3 | Intune platform script — device inventory (executed on device in SYSTEM context) | `Get-DeviceInventory.ps1` | 15c | E-15 |
| P4 | Custom compliance discovery script + rules JSON | `Test-CustomCompliance.ps1`, `custom-compliance-rules.json` | 9 | E-09 |

P3 and P4 are configured through admin-center uploads (as part of sections 15c and 9) but their execution is PowerShell running on managed devices.

## Beyond-Ratio Utilities (Not Counted)

| Script | Purpose | Guide section |
|---|---|---|
| `Sync-IntuneDevices.ps1` | On-demand device check-in via the Graph sync action | 19 |
| `Add-IntuneBulkAssignment.ps1` | Bulk group assignment with backup and full-target preservation | 20 |

Useful during validation and scale-out, but the mandatory workflow does not depend on them, so they are excluded from the ratio denominator. To be explicit: the four PowerShell packages inside the ratio (P1-P4 above) are all mandatory; these two scripts are additions on top of it, not two of the four.

## Foundation Prerequisites (Outside the Ratio)

| Work | Guide section |
|---|---|
| Licensing, admin roles, emergency access accounts, UPN suffixes | 1 |
| Entra Connect: install, PHS, OU filtering | 2 |
| Hybrid join via Entra Connect device options (SCP) | 3 |
| Defender for Business tenant connection (Defender portal wizard: choose Intune, onboard Intune-enrolled devices) | 11 |
| GPO: automatic MDM enrollment | 5 |
| Dynamic groups in Entra | 6 |
| Pilot enrollment and validation of CLIENT01 | 7 |

## Execution Order

Prerequisites (sections 1-7) run first, then G1-G16 with P1 before G14 (the Win32 upload needs the packaged `.intunewin`). P3/P4 are deployed as part of their sections. Optional utilities run on demand. Phase ordering inside the guide: enrollment plumbing → compliance → baseline → Defender policies → BitLocker → configuration → updates → apps → Conditional Access last (enforce access only after the devices can actually be compliant).

## Out-of-Scope Work

Not counted anywhere: the Active Directory deployment, DC hardening, Windows LAPS in AD, and System State backups (they belong to the companion AD project). Where an Intune package touches these (for example, editing `Cfg-WindowsUpdate` in section 14), the change is included in that package.
