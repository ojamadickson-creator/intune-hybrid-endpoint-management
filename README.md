# Hybrid Identity and Intune Endpoint Management Deployment

Portfolio project: extending a hardened on-premises Active Directory environment (Windows Server 2025, `ad.beginningdimension.com`) into a Microsoft 365 tenant using Microsoft Entra Connect, Microsoft Entra hybrid join, and Microsoft Intune — then enforcing Zero Trust access with Conditional Access.

![Lab diagram](docs/assets/lab-diagram.svg)

## Repository Layout

```
intune-hybrid-endpoint-management/
├── README.md                          this file
├── validation-and-troubleshooting.md  proving it works + incident runbooks
├── docs/
│   ├── architecture.md                component and Zero Trust flow breakdown
│   ├── step-by-step-guide.md          the work packages, GUI + PowerShell
│   ├── environment-and-assumptions.md existing AD/tenant facts + design decisions
│   ├── implementation-ledger.md        the package by package
│   ├── verification-manifest.md       every configured setting with its Microsoft Learn source
│   ├── settings-ownership.md           who owns which setting (GPO vs Intune)
│   ├── evidence-checklist.md           screenshot + redaction plan per work package
│   └── assets/lab-diagram.svg         the diagram above
├── scripts/                           PowerShell automation + JSON
└── tests/                             parse + functional checks for the scripts
```

## Business Case

The starting point is a working AD deployment: two domain controllers, one Windows 11 client, GPO-based hardening, Windows LAPS, and System State backups. What it lacks is what every organization needs next:

- **Remote management.** GPO only reaches devices on the LAN; Intune manages devices wherever they are.
- **Modern provisioning.** No imaging, no domain-join USB rituals — hybrid join and automatic enrollment.
- **Health-based access.** GPO can enforce settings, but it cannot *gate access* on device health. Intune compliance + Conditional Access can.
- **App delivery.** Win32 packaging and click-to-run Office replace manual installs.

The project delivers all four on a Microsoft 365 Business Premium license footprint — the same stack a small business actually buys.

## Architecture Overview

| Layer | On-premises (existing) | Cloud (this project) |
|---|---|---|
| Identity | AD DS on DC01/DC02, Kerberos, Windows LAPS | Entra ID via Entra Connect (PHS + OU filtering), Conditional Access |
| Devices | Domain join via GPO | Microsoft Entra hybrid join + automatic MDM enrollment to Intune |
| Policy | GPO baselines (`Sec-Workstation-Baseline`, `Cfg-WindowsUpdate`) | Intune compliance, MDM security baseline, endpoint security, Settings Catalog |
| Apps | Manual / GPO installs | Microsoft 365 Apps suite, Win32 app, platform script |
| Enforcement | Perimeter + GPO | Zero Trust: MFA + compliant-device gates |

Full component breakdown and the Zero Trust flow: [docs/architecture.md](docs/architecture.md).

## Deployment Workflow

```
Phase 1  Foundation        Tenant/licensing/UPN prep -> Entra Connect (PHS, OU filter) -> hybrid join (SCP)
Phase 2  Enrollment        Automatic MDM enrollment (MDM scope + GPO) -> dynamic groups -> pilot device enrolled
Phase 3  Security          Compliance policy -> custom compliance -> MDM baseline -> Defender -> BitLocker
Phase 4  Configuration     Device restrictions + Settings Catalog -> update rings
Phase 5  Apps              M365 Apps suite + Win32 app (packaged with PowerShell) + platform script
Phase 6  Enforcement      Conditional Access (report-only -> on): MFA + compliant device
Phase 7  Operations       Graph reporting,troubleshooting
```

The exhaustive, click-by-click procedure is [docs/step-by-step-guide.md](docs/step-by-step-guide.md) — 20 Intune work packages plus foundation prerequisites.

## Implementation Ratio: Intune Admin Center /  PowerShell

The Intune implementation is split so the ratio is auditable, not claimed — see [docs/implementation-ledger.md](docs/implementation-ledger.md) for the counting rules:

- **16 work packages ** are configured in the **Microsoft Intune admin center** (its Conditional Access node included) — enrollment, compliance, custom compliance, security baseline, endpoint security (antivirus/firewall), BitLocker, configuration profiles, update rings, apps, and Conditional Access.
- **4 work packages ** are PowerShell: one local packaging script (wrapping the Microsoft Win32 content prep tool), one Graph PowerShell SDK reporting script, and two scripts that execute on managed devices through Intune's platform-script and custom-compliance features.

| Script | Where it runs | Purpose |
|---|---|---|
| [New-Win32Package.ps1](scripts/New-Win32Package.ps1) | Admin workstation | Wrap `IntuneWinAppUtil.exe` with validation, logging, and MSI product-code extraction |
| [Get-IntuneComplianceReport.ps1](scripts/Get-IntuneComplianceReport.ps1) | Admin workstation | Export every managed device's compliance state to CSV via Graph |
| [Get-DeviceInventory.ps1](scripts/Get-DeviceInventory.ps1) | Managed device (platform script) | Inventory snapshot with exit codes reported to Intune |
| [Test-CustomCompliance.ps1](scripts/Test-CustomCompliance.ps1) + [custom-compliance-rules.json](scripts/custom-compliance-rules.json) | Managed device (custom compliance) | RDP/SMBv1 discovery with fail-safe JSON rules |

Tenant setup, Entra Connect, hybrid join, the Defender for Business portal connection, the enrollment GPO, and dynamic groups are **foundation prerequisites **. The four PowerShell packages (P1-P4 in the ledger: sections 17, 18, 15c, and 9) are all mandatory. 
## Security and Compliance Objectives

1. **Every managed device is measured** — BitLocker, Secure Boot, code integrity, firewall, antivirus, OS build floor — and the measurement is enforced at sign-in, not just reported.
2. **Access requires health** — Conditional Access policies deny cloud access from non-compliant or unmanaged devices; MFA is universal.
3. **Least privilege at the boundary** — only the `Beginningdimension` OU tree syncs to Entra ID; Tier-0 admin OUs and service accounts stay on-prem.
4. **One setting, one owner** — the [settings-ownership matrix](docs/settings-ownership.md) prevents GPO/Intune conflicts instead of discovering them in production.
5. **Recoverable encryption** — BitLocker keys escrow to Entra ID before encryption starts; LAPS continues to guard the local admin password.

## Skills Demonstrated

| Area | Evidence in this repo |
|---|---|
| Hybrid identity | Entra Connect with PHS and OU filtering; SCP-based hybrid join |
| Intune administration | Enrollment, compliance, baselines, endpoint security, configuration, updates |
| App engineering | Win32 packaging pipeline with detection rules; M365 Apps XML configuration |
| Automation | Graph PowerShell SDK: reporting, sync, assignment management |
| Zero Trust | Conditional Access design with report-only rollout and break-glass exclusion |
| Operational readiness | Evidence plan, troubleshooting runbooks, rollback per package |

## Getting Started

If you want to reproduce this environment: start from the AD project (the domain `ad.beginningdimension.com`, DC01/DC02, CLIENT01 as described in [docs/environment-and-assumptions.md](docs/environment-and-assumptions.md)), obtain a Microsoft 365 Business Premium trial, then follow [docs/step-by-step-guide.md](docs/step-by-step-guide.md) top to bottom. Each section lists its prerequisites, the exact clicks, the expected result, the evidence to capture, and the rollback.

## Status

Design complete; every configuration path and setting was checked against Microsoft Learn at authoring time (October 2026) and each one is recorded with its source in [docs/verification-manifest.md](docs/verification-manifest.md) — with one disclosed exception: the current Windows Firewall profile's per-setting GUI labels are not published by Microsoft (Settings Catalog-based), so those fields are prescribed by meaning and confirmed in the admin center at execution. The scripts are not executed against a live tenant in this repository — that execution, and the evidence in [docs/evidence-checklist.md](docs/evidence-checklist.md), happens as each package is run in the lab. All scripts pass an AST parse check, the on-device scripts pass mocked functional tests, and the bulk-assignment Graph script passes a mocked-Graph behavioral suite (merge preservation, pagination, error paths, OData escaping) under PowerShell 7.4 (see `tests/`). Expect to confirm values like OS build floors and baseline versions against the linked Microsoft pages at execution time, since Intune updates its UI and baselines continuously.
