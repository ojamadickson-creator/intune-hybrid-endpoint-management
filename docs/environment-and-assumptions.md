
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
