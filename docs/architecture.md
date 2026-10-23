# Architecture

![Lab diagram](assets/lab-diagram.svg)

## Design Summary

The lab connects an existing Windows Server 2025 Active Directory domain (`ad.beginningdimension.com`, two domain controllers, one Windows 11 Pro client) to a Microsoft 365 Business Premium tenant (`beginningdimension.onmicrosoft.com`) and moves client management from Group Policy to Microsoft Intune. The identity bridge is Microsoft Entra Connect with password hash synchronization; the device bridge is Microsoft Entra hybrid join plus automatic MDM enrollment; the enforcement bridge is Intune compliance evaluated by Entra Conditional Access.

## Component Breakdown

### Identity Layer

| Component | Role | Notes |
|---|---|---|
| AD DS on DC01/DC02 | Authoritative identity store, DNS, Kerberos/NTLM for on-prem resources | Unchanged from the AD project; DCs are never Intune-managed in this design. |
| Microsoft Entra Connect | Syncs the `Beginningdimension` OU tree (users, groups, devices) to Entra ID with password hash sync | OU filtering keeps service accounts, Tier-0 admin OUs, and default containers out of sync scope. Requires Entra Connect 1.1.819.0+ ([hybrid join prerequisites](https://learn.microsoft.com/en-us/entra/identity/devices/how-to-hybrid-join)). |
| Microsoft Entra ID | Cloud identity, device identities, Conditional Access | Entra ID P1 is included in Business Premium ([security overview](https://learn.microsoft.com/en-us/microsoft-365/admin/security-and-compliance/m365b-security-overview?view=o365-worldwide)). |
| Service connection point (SCP) | Published by Entra Connect "Configure device options" in the AD configuration partition | Lets domain-joined devices discover the tenant and hybrid-join without user interaction. |

### Device Layer

| Component | Role | Notes |
|---|---|---|
| Microsoft Entra hybrid join | CLIENT01 exists in both AD and Entra ID | Dual state: Kerberos/NTLM for on-prem, Entra tokens + SSO for cloud ([hybrid join](https://learn.microsoft.com/en-us/entra/identity/devices/how-to-hybrid-join)). |
| Automatic MDM enrollment | GPO "Enable automatic MDM enrollment using default Microsoft Entra credentials" + Intune MDM user scope | Enrollment happens at sign-in/GPO refresh, no user action needed ([GPO enrollment](https://learn.microsoft.com/en-us/windows/client-management/enroll-a-windows-10-device-automatically-using-group-policy)). |
| Intune (MDM) | Configuration, compliance, apps, updates, reporting | Intune Plan 1 via Business Premium. |

### Management and Security Layers

| Layer | Objects | Enforcement point |
|---|---|---|
| Configuration | `CFG-Workstation-Restrictions` (Device Restrictions template), `CFG-OneDrive-Win11` (Settings Catalog) | Intune policy CSPs |
| Compliance | `CMP-Win11-Health` (built-in rules), `CMP-Win11-Custom` (discovery script + JSON) | Intune evaluation + Entra device compliance claim |
| Endpoint security | `SB-MDM-Win11` (MDM security baseline), `ES-AV-Defender`, `ES-FW-Win11`, `ES-BitLocker-Win11` | Intune CSPs; BitLocker keys escrow to Entra ID |
| Updates | `UPD-Win11-Ring1-Pilot` (Windows Update for Business rings) | Windows Update client; replaces the on-prem update GPO for pilot devices |
| Apps | `APP-M365Apps-Business` (Microsoft 365 Apps suite), `APP-7zip-Win32` (Win32), `SCR-DeviceInventory` (platform script) | Intune Management Extension for Win32/scripts |
| Access control | `CA-MFA-AllUsers`, `CA-RequireCompliantDevice` | Entra Conditional Access (P1) |

### Zero Trust Flow

1. User signs in to CLIENT01 with `jdoe`; AD authenticates, Entra Connect has already synced the identity and password hash.
2. CLIENT01 hybrid-joins via SCP and enrolls to Intune via the automatic MDM enrollment GPO.
3. Intune applies baseline, security, configuration, app, and update policies; the device evaluates compliance (including the custom check) and reports the result.
4. The user requests a cloud resource (e.g., Exchange Online). Conditional Access evaluates: identity (who), MFA (CA-MFA-AllUsers), and device compliance (CA-RequireCompliantDevice).
5. A compliant device gets access; a non-compliant device is blocked and the user is routed to the Company Portal to remediate.

### Extension Path (Not Deployed Here)

- **Windows Autopilot**: register CLIENT01's hardware hash, assign an Autopilot profile with hybrid join, add an Enrollment Status Page. The ESP applies to OOBE/Autopilot scenarios and tracks device setup, security policies, certificates, and app installation ([ESP](https://learn.microsoft.com/en-us/mem/intune/enrollment/windows-enrollment-status)) — it is not part of existing-device enrollment, which is why it is out of scope for this phase.
- **Intune-managed Windows LAPS**: move local admin password backup from AD to Entra ID ([Intune LAPS](https://learn.microsoft.com/en-us/intune/intune-service/protect/windows-laps-policy)). Requires retiring the AD LAPS GPO for the target devices first.
- **Group Policy analytics**: import the `Sec-Workstation-Baseline` GPO into Intune to see which settings already have MDM equivalents, and use that report to drive the GPO-to-Intune migration.

## Failure Domains

| Failure | Impact | Mitigation in design |
|---|---|---|
| Entra Connect server down | No new identity sync; existing synced identities keep working | Two DCs already provide AD redundancy; sync server is a single box by design (lab). |
| Intune policy conflict with GPO | Unpredictable setting values, non-compliance flapping | Settings-ownership matrix (`docs/settings-ownership.md`): one setting, one owner; GPO links removed from pilot scope for migrated settings. |
| Trial license expiry | Intune enrollment and CA stop applying | Evidence collected continuously; environment can be rebuilt from this repo. |
| BitLocker key not escrowed | Device encrypts without a recoverable key | Policy sets recovery-key backup to Entra ID as required before encryption. |
