# Environment and Assumptions

This document records the lab environment the Intune deployment builds on, separates what already exists from what this project adds, and lists every assumption made during the design. 

## Existing On-Premises Environment

The on-premises estate is the Active Directory forest deployed in the companion project "Secure On-Premises Active Directory Domain Services Deployment". Its relevant facts:

| Item | Value |
|---|---|
| Forest / domain | `ad.beginningdimension.com` |
| NetBIOS domain | `BEGINNINGDIM` |
| AD site | `HQ` (subnet `192.168.10.0/24`) |
| DC01 | `192.168.10.10` — primary DC, DNS, Global Catalog, initial FSMO roles |
| DC02 | `192.168.10.11` — replica DC, DNS, Global Catalog |
| Gateway | `192.168.10.1` |
| CLIENT01 | `192.168.10.20` — Windows 11 Enterprise, domain-joined, in `Beginningdimension\Computers\Workstations` |
| OU design | `Beginningdimension` > `Users`, `Computers\Workstations`, `Computers\Laptops`, `Servers`, `Groups\SecurityGroups`, `ServiceAccounts`, `Admin\Tier0`, `Pilot` |
| Standard user | `jdoe` (in `Users`) |
| Privileged user | `adm_jdoe` (in `Admin\Tier0`) |
| Security groups | `GG_IT_Helpdesk`, `GG_Tier0_Admins`, `GG_Tier1_Admins`, `GG_Tier2_Admins`, `GG_LAPS_Password_Readers`, `GG_HR_Users` |
| Windows LAPS | Deployed to AD (schema extended, `Cfg-WindowsLAPS` GPO, passwords backed up to Active Directory) |
| Key GPOs | `Sec-Domain-PasswordPolicy`, `Sec-DomainControllers-Baseline`, `Sec-DomainControllers-Auditing`, `Sec-Workstation-Baseline`, `Cfg-WindowsLAPS`, `Cfg-WindowsUpdate` |
| Backups | Daily System State backups of both DCs |

## Existing Cloud Tenant

| Item | Value |
|---|---|
| Tenant | `beginningdimension.onmicrosoft.com` |
| Licensing | Microsoft 365 Business Premium trial (25-seat pool) |
| Included services relevant here | Intune Plan 1, Microsoft Entra ID P1 (Conditional Access), Microsoft Defender for Business, Microsoft 365 Apps for business |

The Business Premium inclusions are the reason this project can run end-to-end on one trial subscription: Business Premium bundles Intune Plan 1 for MDM/MAM, Entra ID P1 for Conditional Access, and Defender for Business for endpoint protection ([Microsoft 365 for business security overview](https://learn.microsoft.com/en-us/microsoft-365/admin/security-and-compliance/m365b-security-overview?view=o365-worldwide)).

## What This Project Adds

- Microsoft Entra Connect on a new sync server (or an existing member server), with password hash synchronization and OU filtering to the `Beginningdimension` OU tree.
- Microsoft Entra hybrid join for `CLIENT01` via the Entra Connect "Configure device options" flow (service connection point).
- Automatic MDM enrollment to Intune (MDM user scope + the "Enable automatic MDM enrollment using default Microsoft Entra credentials" GPO).
- Intune policies: compliance (standard + custom), security baseline, endpoint security (antivirus, firewall), BitLocker, configuration profiles, update rings, Microsoft 365 Apps, a Win32 app, and a platform script.
- Conditional Access requiring compliant devices and MFA for the pilot.
- Graph PowerShell SDK automation for packaging, reporting, sync, and bulk assignment.

## Explicitly Out of Scope

- **Configuration Manager co-management.** There is no Configuration Manager hierarchy in this environment, so co-management is not deployed. Intune managing previously GPO-managed settings is a migration of management authority, not co-management.
- **Windows Autopilot.** Autopilot is documented as a future extension in `docs/architecture.md`; it is not required to enroll existing hybrid-joined devices.
- **Intune-managed Windows LAPS.** Windows LAPS is already managed through on-premises AD (existing GPO). Deploying an Intune LAPS policy against the same devices would create two management authorities for one setting. The migration path is documented in `docs/settings-ownership.md` but not executed.
- **Enrollment Status Page.** The ESP applies to Microsoft Entra join and Autopilot provisioning scenarios, not to existing domain-joined clients; it is not configured in this phase.

## Assumptions and Decisions

| # | Assumption / decision | Impact if wrong |
|---|---|---|
| A1 | The `beginningdimension.com` (or `ad.beginningdimension.com`) public DNS zone is controlled by you, so the domain can be verified in the tenant. | If the UPN suffix is not a verified domain, Entra ID replaces synced users' UPNs with the default `.onmicrosoft.com` value after synchronization ([Entra Connect user sign-in](https://learn.microsoft.com/en-us/entra/identity/hybrid/connect/plan-connect-user-signin)) — sign-in still works but with different UPNs than on-premises; verify the domain or add an alternate UPN suffix matching the tenant name before syncing. |
| A2 | `CLIENT01` runs Windows 11 Pro with a supported build. As of October 2026 the compliance OS floor is 10.0.26200 (25H2) — 24H2 Home/Pro is end-of-updates per the [Windows 11 release information](https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information) page. Verify the actual build with `ver` and re-check that page at execution time. Business Premium includes rights to upgrade Windows Pro devices ([Upgrade Windows devices](https://learn.microsoft.com/en-us/microsoft-365/business-premium/m365bp-upgrade-windows-pro?view=o365-worldwide)). | Update rings and BitLocker policies still apply to Pro; adjust the minimum OS compliance rule to the actual supported build. |
| A3 | `CLIENT01` has TPM 1.2+ and boots in UEFI mode. | Silent BitLocker enablement fails without TPM/UEFI ([BitLocker prerequisites](https://learn.microsoft.com/en-us/mem/intune/protect/encrypt-devices)). Verify before deploying the encryption policy. |
| A4 | The trial tenant has security defaults disabled or will be reconfigured when Conditional Access is enabled. | Security defaults force MFA for all users and can conflict with custom Conditional Access; resolve before phase 7. |
| A5 | `jdoe` receives one of the 25 Business Premium licenses; the global admin account is licensed separately. | Unlicensed users cannot be targeted by Intune enrollment or receive app assignments. |
| A6 | DNS (forwarders to 1.1.1.1 / 8.8.8.8 on the DCs) and outbound HTTPS from the LAN work; the tenant is reachable from `CLIENT01`. | Hybrid join and enrollment fail without outbound access to Entra/Intune endpoints. |
| A7 | The `Pilot` OU exists (created in the AD project) and is used to stage GPO conflicts. | If it does not exist, create it before phase 5, or link policy changes directly to `Workstations` with care. |
| A8 | The Intune MDM authority is already set to Intune (default for tenants where Intune licenses exist). | If a tenant was previously Config Manager-managed, set the MDM authority first ([MDM authority](https://learn.microsoft.com/en-us/intune/intune-service/fundamentals/mdm-authority-set)). |

## Administrative Accounts Used

| Task | Account |
|---|---|
| Entra Connect install / tenant configuration | Cloud `admin@beginningdimension.onmicrosoft.com` with Global Administrator (Hybrid Identity Administrator for device options) |
| On-premises configuration | `BEGINNINGDIM\adm_jdoe` (Enterprise Admins equivalent for the SCP step) |
| Day-to-day pilot testing | `BEGINNINGDIM\jdoe` (licensed, non-privileged) |

The Global Administrator / Hybrid Identity Administrator roles must be assigned directly to the user (not via group) for Entra Connect installation ([Entra Connect prerequisites](https://learn.microsoft.com/en-us/entra/identity/hybrid/connect/how-to-connect-install-prerequisites)).

## Naming Conventions

| Object | Name |
|---|---|
| Dynamic device group | `GRP-INT-Win11-Corporate` |
| Assigned pilot user group | `GRP-INT-Pilot-Users` |
| Assigned pilot device group | `GRP-INT-Pilot-Devices` |
| Compliance policy | `CMP-Win11-Health` |
| Custom compliance policy | `CMP-Win11-Custom` |
| Security baseline profile | `SB-MDM-Win11` |
| Antivirus policy | `ES-AV-Defender` |
| Firewall policy | `ES-FW-Win11` |
| BitLocker policy | `ES-BitLocker-Win11` |
| Device restrictions profile | `CFG-Workstation-Restrictions` |
| Settings Catalog profile | `CFG-OneDrive-Win11` |
| Update ring | `UPD-Win11-Ring1-Pilot` |
| M365 Apps suite | `APP-M365Apps-Business` |
| Win32 app | `APP-7zip-Win32` |
| MSIX trusted certificate profile | `CFG-MSIX-Trust` |
| Device limit restriction | `LIM-Pilot` |
| Platform script | `SCR-DeviceInventory` |
| GPO | `Cfg-AutoMDMEnrollment` |
| Conditional Access policies | `CA-MFA-AllUsers`, `CA-RequireCompliantDevice` |
