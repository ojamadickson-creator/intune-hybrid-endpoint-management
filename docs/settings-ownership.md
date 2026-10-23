# Settings Ownership Matrix

Intune does not replace the on-premises domain by itself; it takes ownership of specific settings on specific devices. This matrix records, per setting area, which management authority owns it after this project, and what happens when the same setting is configured in two places.

## Authority After This Project

| Setting area | Before (AD project) | After (this project) | Notes |
|---|---|---|---|
| User identity, password policy | AD (`Sec-Domain-PasswordPolicy`) | Unchanged — AD + Entra Connect | Password policies remain on-premises; cloud password protection can be layered later. |
| Windows LAPS (local admin password) | AD GPO `Cfg-WindowsLAPS` | Unchanged — AD GPO | See "Windows LAPS decision" below. |
| DNS, DHCP, sites | AD | Unchanged — AD | Not managed by Intune. |
| DC hardening / auditing | AD GPOs | Unchanged — AD | Intune policies are never targeted at the DCs in this project. |
| Windows Update source / deferral | `Cfg-WindowsUpdate` GPO (Workstations OU) | Intune update ring for pilot devices | The GPO's update-scoped policies are set to **Not Configured** before the ring is assigned (see below and guide section 14). |
| Defender AV status | `Sec-Workstation-Baseline` GPO | Intune `ES-AV-Defender` | GPO already sets Defender enabled; the Intune policy re-enforces and reports it. |
| Firewall | `Sec-Workstation-Baseline` GPO | Intune `ES-FW-Win11` | Remove the firewall portion from the GPO or accept duplicate enforcement; see conflict note below. |
| BitLocker | Not configured on-prem | Intune `ES-BitLocker-Win11` | New setting area owned by Intune. |
| Security baseline (hardening) | `Sec-Workstation-Baseline` GPO | Both, converging on Intune | The MDM security baseline covers a superset of the workstation GPO; migrate GPO settings into Intune policies over time. |
| App delivery | Manual / GPO software installs | Intune (M365 Apps, Win32) | |
| Compliance + Conditional Access | None | Intune + Entra ID P1 | |

## Conflict Handling

**Windows Update.** The `Cfg-WindowsUpdate` GPO is linked to the **Workstations** OU (described in the AD project as update-management configuration; inspect its actual settings before assuming anything). GPO and MDM update settings are separate authorities — do not assume either wins; a GPO that configures the update service location or deferrals keeps interfering with the ring regardless of the Intune policy. Before assigning the update ring, edit the GPO and set every update-scoped policy (service location, deferrals, deadlines) to **Not Configured**, then verify on the device with before/after `gpresult` that the settings no longer apply. Record the original values for rollback. Full procedure in guide section 14.

**Firewall.** The Intune compliance policy's `Firewall: Require` can report Not compliant when a conflicting GPO turns the firewall off or allows all inbound traffic ([Windows compliance settings](https://learn.microsoft.com/en-us/intune/intune-service/protect/compliance-policy-create-windows)). The `Sec-Workstation-Baseline` GPO enables the firewall, so the two agree today; when migrating, remove firewall settings from the GPO rather than carrying both.

**Device restrictions vs. GPO.** Any setting that exists in both an Intune profile and a domain GPO has two authorities writing it, and the outcome per setting is not something to rely on for correctness. The settings-ownership rule this project follows: one setting, one owner. When a Settings Catalog or baseline setting is deployed, remove that setting from the GPO at the next maintenance window.

## Windows LAPS Decision

Windows LAPS is currently owned by on-premises AD: the schema was extended, `Cfg-WindowsLAPS` backs passwords up to Active Directory, and `GG_LAPS_Password_Readers` can read them. Intune also supports Windows LAPS policies that back passwords up to Microsoft Entra ID ([Manage Windows LAPS with Intune](https://learn.microsoft.com/en-us/intune/intune-service/protect/windows-laps-policy)), and the Intune admin center can only display passwords for accounts backed up to Entra ID.

Deploying an Intune LAPS policy to `CLIENT01` while the AD GPO also manages LAPS would create two authorities for the same local administrator password. This project keeps AD as the owner for domain-joined devices and does not deploy the Intune LAPS policy. The migration path, if later desired: disable the `Cfg-WindowsLAPS` GPO for the target OU, create an Intune Account protection profile (`Endpoint security > Account protection > Create Policy`, profile "Local admin password solution (Windows LAPS)"), set Backup Directory to "Backup to Microsoft Entra", and assign to a device group. Passwords then appear under the device's "Local admin password" blade in Intune instead of `Get-LapsADPassword`.

## Coexistence With the Baseline GPO

The `Sec-Workstation-Baseline` GPO and the MDM security baseline overlap (Defender, firewall, lock screen, audit). During the pilot both apply to `CLIENT01`; the documented plan is to move setting ownership to Intune policy-by-policy and shrink the GPO until it can be retired for cloud-managed devices.
