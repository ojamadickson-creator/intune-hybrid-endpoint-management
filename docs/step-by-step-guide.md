# Step-by-Step Implementation Guide

This guide implements the project as 20 Intune work packages — 16 in the Microsoft Intune admin center and 4 in PowerShell — plus foundation prerequisites outside that ratio (see `docs/implementation-ledger.md` for the counting rules). Every setting, path, and prerequisite below was checked against Microsoft Learn; the source link appears next to each procedure. Anything marked **lab decision** is a design choice for this environment, not a Microsoft-documented requirement.

A settings-verification manifest recording each configured field with its supporting Microsoft Learn URL is in `docs/verification-manifest.md`.

Before starting, read `docs/environment-and-assumptions.md` and keep `docs/evidence-checklist.md` open — each section ends with the evidence item to capture.

## Phase 1 — Foundation

### Section 1: Tenant, Licensing, and UPN Preparation (GUI)

**Purpose.** Make the trial tenant ready to sync identities and manage devices: licenses assigned, admin roles separated, and user UPNs that will synchronize cleanly.

**Prerequisites.**

- Trial tenant `beginningdimension.onmicrosoft.com` with Microsoft 365 Business Premium (25 seats).
- Business Premium includes Intune Plan 1, Microsoft Entra ID P1 (Conditional Access), Microsoft Defender for Business, and Microsoft 365 Apps for business ([Microsoft 365 for business security overview](https://learn.microsoft.com/en-us/microsoft-365/admin/security-and-compliance/m365b-security-overview?view=o365-worldwide)).
- On-premises users exist in `ad.beginningdimension.com` under `Beginningdimension\Users`.

**Steps.**

1. Sign in to the [Microsoft 365 admin center](https://admin.microsoft.com) as the cloud global admin.
2. Go to **Billing** > **Licenses** > **Microsoft 365 Business Premium** and confirm available seats.
3. Go to **Users** > **Active users**, select `jdoe` (synced later in section 2 — if the user does not exist in the tenant yet, that is expected; assign the license after the first sync), and assign a Business Premium license. Repeat for the admin account you will use day-to-day.
4. Create break-glass cloud-only account(s) for emergency access, per Microsoft's guidance ([manage emergency access accounts](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/security-emergency-access)): at least two if possible, in the tenant's default `onmicrosoft.com` domain, assigned Global Administrator permanently (not just eligible), authenticating with a method different from your normal admins (passkey/FIDO2 or certificate-based), credentials stored in separate secure locations, excluded from every Conditional Access policy, with sign-in and activity alerts monitored and validity re-checked at least every 90 days.
5. **UPN suffix decision (lab decision).** This must be resolved before the first sync: Microsoft documents that when a synced user's UPN suffix is not a verified domain in the tenant, Entra ID **replaces** the UPN with the default `.onmicrosoft.com` value after synchronization ([Entra Connect user sign-in](https://learn.microsoft.com/en-us/entra/identity/hybrid/connect/plan-connect-user-signin)) — the user still signs in, but with a different UPN than on-premises. Choose one:
   - **Option A (cleanest):** in the Microsoft 365 admin center go to **Settings** > **Domains** > **Add domain**, add the public domain you control that matches the on-prem UPN suffix (e.g., `beginningdimension.com` or `ad.beginningdimension.com`), and complete the TXT/MX verification at your DNS provider. Then the on-prem UPN suffix matches a verified tenant domain.
   - **Option B (no custom domain):** add the `beginningdimension.onmicrosoft.com` suffix in **Active Directory Domains and Trusts** (Forests > ad.beginningdimension.com > Properties > UPN Suffixes), then stamp it on the pilot user in ADUC.
   Verify the final UPN with the tenant's verified domains list before syncing — Entra Connect flags objects whose UPN suffix is not a verified tenant domain ([Entra Connect user sign-in](https://learn.microsoft.com/en-us/entra/identity/hybrid/connect/plan-connect-user-signin)).
6. On DC01, set the pilot user's UPN to match the verified domain (Option A): open **Active Directory Users and Computers** > `Beginningdimension\Users` > `jdoe` > **User logon name** > select the verified suffix. Record the final UPN — it is the identity that enrolls devices and gets Conditional Access policies.

**Expected result.** Licenses are available, the break-glass account(s) exist per the emergency-access guidance, and `jdoe` has a UPN whose suffix matches a verified tenant domain — so Entra ID keeps the on-prem UPN instead of replacing it.

**Evidence.** E-01 — license assignment screenshot.

**Rollback.** Remove licenses; delete the break-glass account (keep it if you continue).

### Section 2: Install Entra Connect with Password Hash Sync and OU Filtering (GUI)

**Purpose.** Bridge on-prem identity to Entra ID, syncing only the `Beginningdimension` OU tree with password hash synchronization (PHS).

**Prerequisites.** The Entra Connect server must be domain-joined Windows Server with full GUI (Server Core unsupported), Windows Server 2016+ (2022/2025 recommended), .NET Framework 4.6.2+, PowerShell 5.0+, and the Global Administrator or Hybrid Identity Administrator role assigned **directly** to the cloud account (group-assigned roles do not work for the installer). The default install uses SQL Server Express LocalDB, which suits this directory size. ([Entra Connect prerequisites](https://learn.microsoft.com/en-us/entra/identity/hybrid/connect/how-to-connect-install-prerequisites))

**Steps.**

1. Build (or designate) a domain-joined member server, e.g. `SYNCSRV01`, joined to `ad.beginningdimension.com`, with outbound HTTPS to Microsoft 365.
2. Download Microsoft Entra Connect from [Microsoft's download page](https://learn.microsoft.com/en-us/entra/identity/hybrid/connect/whatis-entra-connect) and run `MicrosoftEntraConnect.exe` as a domain admin.
3. On the welcome page, accept the license terms and select **Continue**.
4. On **Express Settings**, select **Customize** (express settings would sync the entire domain — this project syncs a filtered scope).
5. **Install required components** — leave defaults, select **Install**.
6. **User sign-in**: select **Password Hash Synchronization** and **Next**. (Lab decision: PHS over pass-through because it removes the dependency on on-prem availability for cloud sign-in and is the simplest supported hybrid option.)
7. **Connect to Microsoft Entra ID**: sign in with the Global Administrator / Hybrid Identity Administrator account.
8. **Connect your directories**: add the `ad.beginningdimension.com` forest with an Enterprise Admins credential (lab decision: `BEGINNINGDIM\adm_jdoe`).
9. **Domain and OU filtering**: select **Sync selected domains and OUs**, expand the forest, and check only the OUs this project needs: `Users`, `Computers` (with its `Workstations`/`Laptops` children), and `Groups\SecurityGroups`. Leave `Admin` (Tier 0-2), `ServiceAccounts`, `Servers`, and the domain's built-in containers unchecked — admin and service accounts are intentionally excluded from directory synchronization. ([OU filtering guidance](https://learn.microsoft.com/en-us/entra/identity/hybrid/how-to-connect/configure-filtering))
10. **Uniquely identifying your users** — keep defaults (userPrincipalName for matching).
11. **Optional features**: keep **Password hash synchronization** checked. Leave Exchange hybrid deployment, directory extension, and device writeback unchecked.
12. **Ready to configure** > **Install**. When complete, verify:
    - Sign in to the [Entra admin center](https://entra.microsoft.com) > **Identity** > **Users** > `jdoe` shows **Source: Windows Server AD**.
    - On the Entra Connect server, open the **Microsoft Entra Connect** desktop app > **View current configuration** and confirm the OU filter scope.

**Expected result.** `jdoe`, the security groups, and `CLIENT01`'s computer object appear in Entra ID within two sync cycles (30 minutes default). Admin and service accounts stay on-premises only, by design.

**Evidence.** E-02 — synced user + sync service export without errors.

**Rollback.** To change the synced scope later, re-run Entra Connect > **Configure** > **Customize synchronization options** and adjust the OU selection. For full removal, uninstall Entra Connect from the sync server; synchronized cloud objects become stale and must be handled deliberately (deleting the connector does not delete Entra objects). In a disposable trial tenant, rebuilding the tenant is also acceptable.

### Section 3: Configure Microsoft Entra Hybrid Join (GUI)

**Purpose.** Let domain-joined devices register with Entra ID automatically by publishing the service connection point (SCP) through Entra Connect.

**Prerequisites.** Entra Connect 1.1.819.0+, the target computer objects inside synced OUs (section 2 handled this: `Computers\Workstations` is under `Beginningdimension`), Hybrid Identity Administrator for the tenant and Enterprise Administrator credentials for the forest ([hybrid join with Entra Connect](https://learn.microsoft.com/en-us/entra/identity/devices/how-to-hybrid-join)).

**Steps.**

1. On the Entra Connect server, open **Microsoft Entra Connect** and select **Configure**.
2. Under **Additional tasks**, select **Configure device options** > **Next**.
3. On **Overview** > **Next**.
4. On **Connect to Microsoft Entra ID**, enter Hybrid Identity Administrator credentials.
5. On **Device options**, select **Configure Microsoft Entra hybrid join** > **Next**.
6. On **Device operating systems**, select **Windows 10 or later** (lab decision: CLIENT01 is Windows 11) > **Next**.
7. On **SCP configuration**: select the `ad.beginningdimension.com` forest, choose the authentication service (Entra ID for this PHS setup), select **Add**, and provide Enterprise Administrator credentials. **Next**.
8. On **Ready to configure** > **Configure**. Confirm "Configuration complete" and **Exit**.
9. Verify the SCP was created in AD. Rather than guessing the object's GUID, discover it in the configuration partition (run on DC01 as admin) and confirm the object exists under the Device Registration Configuration container:
   ```powershell
   $configNC = (Get-ADRootDSE).ConfigurationNamingContext
   Get-ADObject -SearchBase "CN=Device Registration Configuration,CN=Services,$configNC" `
     -SearchScope Subtree -Filter * -Properties cn
   ```
   The authoritative proof is end-to-end: the Entra Connect configuration-complete page plus CLIENT01 hybrid-joining successfully in section 7 (runbook A uses this discovery query for troubleshooting).
10. Confirm outbound connectivity for device registration from CLIENT01 works under the SYSTEM account; Microsoft provides the Test Device Registration Connectivity script referenced in [hybrid join troubleshooting](https://learn.microsoft.com/en-us/entra/identity/devices/how-to-hybrid-join).

**Expected result.** The SCP exists in the AD configuration partition; CLIENT01 will hybrid-join at next policy evaluation.

**Evidence.** E-03 — SCP object properties + "Configuration complete" page.

**Rollback.** Re-run Configure device options and disable hybrid join for the forest (removes the SCP).

### Section 4: Enrollment Plumbing — Automatic Enrollment, Restrictions, Device Limits (GUI)

**Purpose.** Configure the tenant so that the pilot group's devices automatically enroll in Intune when they hybrid-join, and set guard rails on what can enroll.

**Steps.**

1. Open the [Microsoft Intune admin center](https://intune.microsoft.com) and confirm the MDM authority is Intune (default for a tenant where Intune licenses exist; see [MDM authority](https://learn.microsoft.com/en-us/intune/intune-service/fundamentals/mdm-authority-set)).
2. **Enable automatic enrollment.** Go to **Devices** > **Enrollment** (shown as **Devices** > **Device onboarding** > **Enrollment** in some tenants) > **Windows** tab > **Automatic Enrollment** > select **Microsoft Intune** ([enable automatic enrollment](https://learn.microsoft.com/en-us/intune/intune-service/enrollment/windows-enroll)):
   - **MDM user scope**: **Some** — select the pilot group (create `GRP-INT-Pilot-Users` first if you have not; see section 6). Devices of users in scope enroll automatically when they join or register with Entra ID.
   - **MAM user scope**: **None** (lab decision: no BYOD app-protection scope in this phase).
3. **Platform restrictions.** Go to **Devices** > **Device onboarding** > **Enrollment** > **Device platform restrictions** > **Windows** ([enrollment restrictions](https://learn.microsoft.com/en-us/intune/device-enrollment/restrictions)):
   - Open the **All Users** default restriction. Under **Personally owned**, set **Block** for Windows enrollment. Devices enrolling via the automatic MDM enrollment GPO are treated as corporate-authorized (GPO is one of the documented authorized corporate enrollment methods), so hybrid-joined machines still enroll — this blocks only random personal devices.
4. **Device limit.** Go to **Devices** > **Enrollment** > **Windows** > **Device limit restriction** > **Create restriction** ([device limits](https://learn.microsoft.com/en-us/intune/intune-service/enrollment/create-device-limit-restrictions)): name it `LIM-Pilot`, set **Device limit** to **5**, assign it to the pilot group. Intune enforces a default limit policy otherwise; the configurable range is 1-15 devices ([restriction overview](https://learn.microsoft.com/en-us/intune/device-enrollment/restrictions)).

**Expected result.** The tenant will auto-enroll pilot users' hybrid-joined devices, block personal Windows enrollment, and cap pilot users at 5 devices.

**Evidence.** E-04 — Automatic Enrollment blade + restriction policies.

**Rollback.** Set MDM user scope back to None; delete the custom restriction policies (the defaults remain).

### Section 5: Create the Automatic MDM Enrollment GPO (GUI)

**Purpose.** Trigger CLIENT01 (and future workstations) to enroll with its Entra credentials without touching the device.

**Prerequisites.** Section 3 (hybrid join configured) and section 4 (MDM user scope includes the pilot user).

**Steps.**

1. On DC01, open **Group Policy Management**.
2. Right-click the **Workstations** OU (`Beginningdimension\Computers\Workstations`) > **Create a GPO in this domain, and Link it here**. Name it `Cfg-AutoMDMEnrollment`.
3. Edit the GPO and browse to **Computer Configuration** > **Administrative Templates** > **Windows Components** > **MDM**.
4. Open **Enable automatic MDM enrollment using default Microsoft Entra credentials**: set to **Enabled**, and under **Select Credential Type to Use** choose **User Credential**. ([GPO-based automatic enrollment](https://learn.microsoft.com/en-us/windows/client-management/enroll-a-windows-10-device-automatically-using-group-policy))
5. Close the editor. Confirm the GPO is linked to **Workstations** (CLIENT01's OU) and note the link order.
6. On CLIENT01, run `gpupdate /force`, then verify with `gpresult /r` that `Cfg-AutoMDMEnrollment` is in the Applied GPO list.

**Expected result.** At the next sign-in or policy refresh, CLIENT01 starts MDM enrollment using `jdoe`'s Entra credentials.

**Evidence.** E-05 — GPMC settings report + `gpresult /r` on CLIENT01.

**Rollback.** Unlink (or set to Disabled) the GPO; enrolled devices stay managed until retired.

### Section 6: Create Target Groups (GUI)

**Purpose.** Build the assignment targets: one assigned pilot user group, one assigned pilot device group, and one dynamic device group that auto-collects Windows 11 devices.

**Prerequisites.** CLIENT01 is (or will be) hybrid-joined and synced to Entra ID; dynamic groups need Entra ID P1 for unique users in dynamic **user** groups — Business Premium includes P1 ([dynamic membership rules](https://learn.microsoft.com/en-us/entra/identity/users/groups-dynamic-membership)).

**Steps.**

1. Open the [Entra admin center](https://entra.microsoft.com) > **Identity** > **Groups** > **All groups** > **New group**.
2. **Assigned pilot user group**: Group type **Security**, name `GRP-INT-Pilot-Users`, Membership type **Assigned**, add `jdoe` as member and the admin as owner. **Create**.
3. **Assigned pilot device group**: New group, name `GRP-INT-Pilot-Devices`, Membership type **Assigned**, under **Members** select **Devices** and add `CLIENT01` (it appears once synced from AD or hybrid-joined). **Create**.
4. **Dynamic Windows 11 device group**: New group, Group type **Security**, name `GRP-INT-Win11-Corporate`, Membership type **Dynamic Device**. Device rules must be entered in the rule text box (the graphical rule builder is available only for dynamic user groups — [dynamic membership rules](https://learn.microsoft.com/en-us/entra/identity/users/groups-dynamic-membership)). Enter:
   ```text
   (device.deviceOSType -eq "Windows") -and (device.deviceOSVersion -startsWith "10.0.2")
   ```
   Lab decision: Windows 11 builds are 10.0.22000 and higher, so the `10.0.2` prefix matches Windows 11 while skipping Windows 10 builds (10.0.1xxxx). Confirm CLIENT01's actual OS version with `ver` and adjust if Microsoft's build numbering changes.
5. Select **Validate rules (preview)**, add CLIENT01, and confirm the result is **True**. **Create**.
6. Wait 1-2 minutes (or force), then open the group's **Members** blade and confirm CLIENT01 is listed.

**Expected result.** Three groups ready as assignment targets. Note: no license is required for devices in a dynamic device group ([licensing note](https://learn.microsoft.com/en-us/entra/identity/users/groups-dynamic-membership)).

**Evidence.** E-06 — group rules + validation results.

**Rollback.** Delete the groups.

### Section 7: Enroll CLIENT01 and Validate (GUI)

**Purpose.** Prove the hybrid join + automatic enrollment chain end-to-end on the pilot device.

**Steps.**

1. On CLIENT01, sign in as `BEGINNINGDIM\jdoe`.
2. Run `gpupdate /force`, then sign out and back in (enrollment is triggered at sign-in/policy refresh).
3. Open **Settings** > **Accounts** > **Access work or school**, select the domain connection, and select **Info**: MDM enrollment should show as enabled with server `enrollment.manage.microsoft.com` ([verify enrollment](https://learn.microsoft.com/en-us/windows/client-management/enroll-a-windows-10-device-automatically-using-group-policy)).
4. Open an elevated command prompt and run `dsregcmd /status`. Verify:
   - `AzureAdJoined: YES`
   - `DomainJoined: YES` — the dual state that defines hybrid join ([hybrid join](https://learn.microsoft.com/en-us/entra/identity/devices/how-to-hybrid-join))
   - `MdmUrl: https://enrollment.manage.microsoft.com/enrollmentserver/discovery.svc` — note this alone indicates the MDM enrollment record is configured; enrollment is proven by the Intune device record in step 6 and a successful enrollment task in step 5
5. If enrollment has not fired, open **Task Scheduler** > **Task Scheduler Library** > **Microsoft** > **Windows** > **EnterpriseMgmt** and check the last run result of the enrollment task ([GPO enrollment diagnostics](https://learn.microsoft.com/en-us/windows/client-management/enroll-a-windows-10-device-automatically-using-group-policy)).
6. In the Intune admin center, go to **Devices** > **All devices**: CLIENT01 appears with owner type and join type **Microsoft Entra hybrid joined**.
7. Select CLIENT01 > **Hardware**: confirm OS, TPM, and encryption-readiness details reported.

**Expected result.** CLIENT01 is hybrid-joined, MDM-enrolled, and reporting to Intune.

**Evidence.** E-07 — `dsregcmd /status` output + Intune device list.

**Rollback.** Unlink the `Cfg-AutoMDMEnrollment` GPO first (so the device does not re-enroll), then on CLIENT01 use Settings > Accounts > Access work or school > select the connected account > **Disconnect** — the documented user path for removing a device from management ([remove your device from management](https://learn.microsoft.com/en-us/intune/intune-service/user-help/unenroll-your-device-from-intune-windows)). The docs do not spell out side effects on hybrid join for this path — verify `dsregcmd /status` afterward; if the Entra registration was removed too, hybrid join re-establishes itself at the next policy cycle. The admin-side alternative is the **Retire** remote action ([retire](https://learn.microsoft.com/en-us/intune/intune-service/remote-actions/devices-wipe)).

## Phase 2 — Security and Compliance Policies

### Section 8: Compliance Policy and Tenant Settings (GUI)

**Purpose.** Define what "healthy" means for a managed Windows 11 device and what happens when a device is not.

**Steps.**

1. **Tenant-wide setting.** In the Intune admin center, go to **Devices** > **Compliance** > **Compliance policy settings** and set **Mark devices with no compliance policy assigned as** to **Non-compliant**. Microsoft recommends this so unmanaged devices are identifiable in the "Devices without compliance policy" report ([compliance monitoring](https://learn.microsoft.com/en-us/intune/intune-service/protect/compliance-policy-monitor)).
2. **Create the policy.** Go to **Devices** > **Compliance** > **Policies** > **Create policy** ([create compliance policies](https://learn.microsoft.com/en-us/intune/intune-service/protect/create-compliance-policy)). Choose platform **Windows 10 and later**.
3. **Basics**: name `CMP-Win11-Health`, description `Windows 11 health compliance - pilot`.
4. **Compliance settings** (values follow the Windows compliance settings reference ([Windows compliance settings](https://learn.microsoft.com/en-us/intune/intune-service/protect/compliance-policy-create-windows))):
   | Category | Setting | Value |
   |---|---|---|
   | Device health | Require BitLocker | Require |
   | Device health | Require Secure Boot to be enabled on the device | Require |
   | Device health | Require code integrity | Require |
   | Device properties | Minimum OS version | `10.0.26200` (Windows 11 25H2 — lab decision: as of October 2026, 24H2 Home/Pro is end-of-updates and 25H2 is the oldest Home/Pro version still receiving updates; re-check the [Windows 11 release information](https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information) page and `ver` on CLIENT01 at execution time and adjust) |
   | System security > Device Security | Firewall | Require |
   | System security > Device Security | Antivirus | Require |
   | System security > Device Security | Antispyware | Require |
   | System security > Password | Require a password to unlock mobile devices | Require |
   | System security > Password | Minimum password length | `8` |

   Note: "Require BitLocker" lives under **Device health**, not under System security Encryption; it evaluates BitLocker through Windows Health Attestation at boot, so a reboot may be needed after encryption before the device reports compliant ([Windows compliance settings](https://learn.microsoft.com/en-us/intune/intune-service/protect/compliance-policy-create-windows)).
5. **Actions for noncompliance** (schedules in days after noncompliance):
   | Action | Schedule |
   |---|---|
   | Mark device noncompliant | 0 days (immediate) |
   | Send email to end user | 1 day |

   The email action requires a notification template to exist first: go to **Devices** > **Compliance** > **Notifications** > **Create notification**, fill in the subject/message and sender, and save. Then select it in the policy's **Send email to end user** action. ([Notifications](https://learn.microsoft.com/en-us/intune/intune-service/protect/actions-for-noncompliance) — available actions include mark noncompliant, send email, lock, and retire.)
6. **Assignments**: include `GRP-INT-Pilot-Devices` only (lab decision: enforce on the pilot first — after validation, promotion means re-targeting assignments to the dynamic `GRP-INT-Win11-Corporate` group, which then picks up every matching managed device automatically). Review + create.
7. On CLIENT01, sign in, then in Settings > Accounts > Access work or school select the account > **Info** > **Sync** (or run the Graph sync script, section 19). Compliance evaluates after check-in; allow up to 24 hours or force it with a sync ([compliance reporting](https://learn.microsoft.com/en-us/intune/intune-service/protect/compliance-policy-monitor)).

**Expected result.** CLIENT01 reports **Compliant** once BitLocker (section 12) is on and all health checks pass; the device shows in Devices > Compliance > Monitor > Device compliance status.

**Evidence.** E-08 — policy assignment + device compliance status.

**Rollback.** Unassign or delete the policy; the tenant-wide setting returns to default (compliant) if reverted.

### Section 9: Custom Compliance — Discovery Script and JSON (GUI)

**Purpose.** Add compliance rules Intune cannot express with built-in settings — here: RDP disabled and SMBv1 removed — using a discovery script and a rules JSON.

**Prerequisites.** Custom compliance is supported on Windows (excluding Home editions); the discovery script is a PowerShell script delivered by the policy, and the JSON defines the rules ([custom compliance settings](https://learn.microsoft.com/en-us/intune/intune-service/protect/compliance-use-custom-settings)). The Intune Management Extension runs discovery every 8 hours and on user-initiated "Check compliance" ([custom compliance settings](https://learn.microsoft.com/en-us/intune/intune-service/protect/compliance-use-custom-settings)).

**Steps.**

1. Prepare the two artifacts from `scripts/`:
   - `Test-CustomCompliance.ps1` — the discovery script. It writes **only** the result JSON to stdout (diagnostics go to a log file, not stdout, because anything in STDERR marks detection as failed and stray stdout breaks evaluation).
   - `custom-compliance-rules.json` — rules referencing the setting names the script returns, using the documented schema: `SettingName`, `Operator`, `DataType`, `Operand`, plus `MoreInfoUrl` and `RemediationStrings` (at least one entry with language `en_US`) ([custom compliance JSON](https://learn.microsoft.com/en-us/intune/intune-service/protect/compliance-custom-json)). Supported operators: `IsEquals`, `NotEquals`, `GreaterThan`, `GreaterEquals`, `LessThan`, `LessEquals`; data types: `Boolean`, `Int64`, `Double`, `String`, `DateTime`, `Version`.
2. **Upload the discovery script first.** In the Intune admin center, go to **Devices** > **Compliance** > **Scripts** > **Add** (the script must be uploaded before the policy can reference it) and add `Test-CustomCompliance.ps1`.
3. **Create the policy.** Go to **Devices** > **Compliance** > **Policies** > **Create policy**, platform **Windows 10 and later**, name `CMP-Win11-Custom`.
4. On **Configuration settings**, scroll to the **Custom compliance** section: select the uploaded discovery script, upload `custom-compliance-rules.json`, and enable **Run script as 32-bit process on 64-bit clients** = **No**.
5. **Actions for noncompliance**: Mark device noncompliant — 0 days.
6. **Assignments**: `GRP-INT-Pilot-Devices` (pilot first; the dynamic group is a later promotion target). Review + create.
7. Validate on CLIENT01: sign in, open the Company Portal app (or Settings > Accounts > Access work or school > Info) and select **Check compliance**. Then check **Devices** > **Compliance** > `CMP-Win11-Custom` > **Monitor** > **Per-setting status** — the custom settings appear with their pass/fail counts.

**Expected result.** `RdpDisabled: true` and `Smbv1Disabled: true` evaluate compliant on CLIENT01.

**Evidence.** E-09 — per-setting status showing the custom rules.

**Rollback.** Delete the policy and the uploaded script.

### Section 10: MDM Security Baseline (GUI)

**Purpose.** Apply Microsoft's hardened defaults for Windows in one profile instead of dozens of individual policies.

**Steps.**

1. In the Intune admin center, go to **Endpoint security** > **Security baselines** ([manage baselines](https://learn.microsoft.com/en-us/intune/intune-service/protect/security-baselines-configure)). Available baselines include **Windows 10 and later - MDM security baseline**, the **Microsoft Defender for Endpoint baseline**, and others.
2. Select **Windows 10 and later - MDM security baseline** > **Create profile** (lab decision: the MDM baseline applies to any Intune-managed Windows 10/11 device; the Defender for Endpoint baseline is used when devices are onboarded to Defender — section 11 notes this).
3. **Basics**: name `SB-MDM-Win11`, description `MDM security baseline - pilot`.
4. **Configuration settings**: walk every settings group (BitLocker, Defender, firewall, remote procedure call, and more) and record the baseline version plus any setting you change and why. Review in particular **BitLocker > Configure TPM startup** so silent enablement is not blocked — some baseline versions set TPM startup PIN/key in ways that block silent encryption ([BitLocker silent enablement](https://learn.microsoft.com/en-us/mem/intune/protect/encrypt-devices)). Lab decision: keep defaults except where they conflict with section 12's silent-encryption prerequisites.
5. **Assignments**: include `GRP-INT-Pilot-Devices` (pilot first; promote to the dynamic group after validation). Review + create.
6. Record the baseline **version** shown on the profile (evidence). Note: profiles created in May 2023-format or later become read-only when a newer baseline version releases; updating creates a new instance that does **not** carry over assignments — re-assign after any version update ([baseline versioning](https://learn.microsoft.com/en-us/intune/intune-service/protect/security-baselines-configure)).
7. Check status: **Endpoint security** > **Security baselines** > `SB-MDM-Win11` > the profile > **Device assignment status** for CLIENT01.

**Expected result.** CLIENT01 reports "Succeeded" for the baseline profile; settings drift later shows under the profile's monitor tabs.

**Evidence.** E-10 — baseline profile + assignment status (with version).

**Rollback.** Unassign the profile. Baseline settings are not automatically reverted when unassigned — plan settings removal deliberately.

### Section 11: Defender for Business Connection and Antivirus/Firewall Policies (GUI)

**Purpose.** Onboard CLIENT01 to Defender for Business and manage its antivirus and firewall from Intune.

**Prerequisites.** Defender for Business is included with Business Premium ([security overview](https://learn.microsoft.com/en-us/microsoft-365/admin/security-and-compliance/m365b-security-overview?view=o365-worldwide)). MFA must be enabled for all users before the setup wizard ([Defender for Business setup](https://learn.microsoft.com/en-us/defender-business/mdb-setup-configuration)) — the tenant's security defaults or your `CA-MFA-AllUsers` policy (section 16) covers this.

**Steps.**

1. Open the [Microsoft Defender portal](https://security.microsoft.com) as the security admin. If Defender for Business is not yet provisioned, go to **Assets** > **Devices** — provisioning starts — and select **Get started** on the wizard ([Defender for Business setup](https://learn.microsoft.com/en-us/defender-business/mdb-setup-configuration)).
2. In the wizard: assign security team roles, set the notification email, and when prompted about device management, because this tenant manages devices with Intune, **continue using Intune** rather than switching to the simplified Defender-portal configuration. Choose the option to onboard **all devices enrolled in Intune** so Windows devices onboard automatically as they enroll ([Defender for Business setup](https://learn.microsoft.com/en-us/defender-business/mdb-setup-configuration)).
3. Finish the wizard. In the Defender portal, **Assets** > **Devices** should eventually list CLIENT01 as onboarded.
4. Back in the Intune admin center, create the antivirus policy: **Endpoint security** > **Antivirus** > **Create policy** > platform **Windows** > profile **Microsoft Defender Antivirus** > name `ES-AV-Defender`. Enable real-time protection and cloud-delivered protection, and review the remaining settings. Assign to `GRP-INT-Pilot-Devices` (pilot first).
5. Create the firewall policy: **Endpoint security** > **Firewall** > **Create policy** > platform **Windows** > name `ES-FW-Win11`. Ensure the domain, private, and public profiles are not disabled; keep Microsoft-recommended defaults for the pilot. Assign to the same group.

**Expected result.** CLIENT01 is visible in the Defender portal with sensors reporting, and both endpoint security policies show "Succeeded" in their device assignment status.

**Evidence.** E-11 — Defender devices list + policy assignment statuses.

**Rollback.** Offboard the device in the Defender portal; unassign the Intune policies.

### Section 12: BitLocker Disk Encryption (GUI)

**Purpose.** Silently encrypt CLIENT01's drives and escrow recovery keys to Entra ID.

**Prerequisites.** CLIENT01 must be Entra joined or hybrid joined, have TPM 1.2+, boot in native UEFI, and not require a TPM startup PIN/key; silent enablement also needs the user to be an admin (Windows 10 1803+/Windows 11) or a standard user (1809+) ([BitLocker prerequisites](https://learn.microsoft.com/en-us/mem/intune/protect/encrypt-devices)). Verify before deploying: `Get-Tpm` (TPM present/ready) and `Confirm-SecureBootUEFI` on CLIENT01.

**Steps.**

1. In the Intune admin center, go to **Endpoint security** > **Disk encryption** > **Create policy** > platform **Windows** > profile **BitLocker** ([disk encryption policies](https://learn.microsoft.com/en-us/mem/intune/protect/encrypt-devices)). Name it `ES-BitLocker-Win11`.
2. On **Configuration settings**, configure (values per the silent-enablement guidance ([BitLocker policies](https://learn.microsoft.com/en-us/mem/intune/protect/encrypt-devices))):
   | Setting | Value |
   |---|---|
   | Require Device Encryption | Enabled |
   | Allow Warning For Other Disk Encryption | Disabled |
   | Configure TPM startup | Allow TPM |
   | Configure TPM startup PIN | Do not allow startup PIN with TPM |
   | Configure TPM startup key | Do not allow startup key with TPM |
   | Configure TPM startup key and PIN | Do not allow startup key and PIN with TPM |
   | Save BitLocker recovery information to Microsoft Entra ID | Enabled |
   | Store recovery information in Microsoft Entra ID before enabling BitLocker | Required |
   | Client-driven recovery password rotation | Enable rotation on Microsoft Entra joined and Microsoft Entra hybrid joined devices |
3. Assign to `GRP-INT-Pilot-Devices` (pilot first). Review + create.
4. On CLIENT01: run the sync script (section 19) or Settings > Info > **Sync**, then watch for silent encryption to start. Verify with `manage-bde -status` (elevated).
5. Verify key escrow: in the [Entra admin center](https://entra.microsoft.com) > **Identity** > **Devices** > CLIENT01 > **BitLocker keys** — recovery keys should be listed. Intune can also show them under the device's **Recovery keys** blade.
6. Remember the compliance dependency: "Require BitLocker" is measured at boot, so after encryption completes, reboot CLIENT01 and re-check compliance (section 8).

**Expected result.** OS drive (and fixed data drives if configured) encrypted without user interaction; recovery keys in Entra ID.

**Evidence.** E-12 — `manage-bde -status` + Entra BitLocker keys blade.

**Rollback.** `manage-bde -off` decrypts the drive (removes BitLocker protection and the encrypted data becomes plaintext — lab only); escrowed recovery keys remain in Entra ID until the device object is removed.

### Section 13: Configuration Profiles — Restrictions Template and Settings Catalog (GUI)

**Purpose.** Demonstrate both configuration authoring models: the Device Restrictions template and the Settings Catalog.

**Steps.**

1. **Device Restrictions profile.** In the Intune admin center, go to **Devices** > **Manage devices** > **Configuration** > **Create** > **New policy** ([Settings Catalog](https://learn.microsoft.com/en-us/mem/intune/configuration/settings-catalog)); platform **Windows 10 and later**, profile type **Templates** > **Device restrictions** > **Create**. Name it `CFG-Workstation-Restrictions`. Configure:
   | Area | Setting | Value |
   |---|---|---|
   | Password | Require a password | Require |
   | Password | Minimum password length | 8 |
   | Password | Maximum minutes of inactivity before screen locks | 5 |
   | Bluetooth | Bluetooth discoverable | Block |

   Continue through **Scope tags** and **Assignments** (assign to `GRP-INT-Pilot-Devices`), then **Review + create**.
2. **Settings Catalog profile (OneDrive known folder move).** Go to **Devices** > **Manage devices** > **Configuration** > **Create** > **New policy**; platform **Windows 10 and later**, profile type **Settings catalog** ([Settings Catalog](https://learn.microsoft.com/en-us/mem/intune/configuration/settings-catalog)). Name it `CFG-OneDrive-Win11`.
3. On **Configuration settings**, select **Add settings**, search for **OneDrive**, and in the OneDrive category select:
   | Setting | Value |
   |---|---|
   | Silently move Windows known folders to OneDrive | Enable |
   | Tenant ID | the tenant GUID of `beginningdimension.onmicrosoft.com` (find it in Entra admin center > Overview) |

   Enabling the master setting reveals its sub-settings — one per folder plus notification and tenant ID (the Settings Catalog OneDrive procedure is documented in [Configure settings with Intune](https://learn.microsoft.com/en-us/sharepoint/configure-sync-intune)); configure them: **Desktop** = True, **Documents** = True, **Pictures** = True, **Show notification to users after folders have been redirected** = No. KFM requirements per Microsoft: devices must be Entra joined/hybrid joined, the user must have a OneDrive with sufficient quota, and users must be synced with the latest OneDrive build ([Known Folder Move overview](https://learn.microsoft.com/en-us/onedrive/redirect-known-folders)).

   Lab decision: KFM moves Desktop/Documents/Pictures into the user's OneDrive; `jdoe` needs storage quota from the Business Premium license. Continue through the wizard, assign to the same group, and **Review + create**.
4. Verify on CLIENT01: Devices > Manage devices > Configuration > each profile > **Device assignment status** shows CLIENT01 "Succeeded". For the restrictions profile, test one visible setting (e.g., Bluetooth is not discoverable).

**Expected result.** Both profiles report success on CLIENT01 and their settings apply at the next check-in.

**Evidence.** E-13 — both profiles' device status.

**Rollback.** Unassign or delete profiles; settings persist until another authority changes them.

### Section 14: Update Rings (GUI)

**Purpose.** Move pilot devices from the on-prem update GPO to Windows Update for Business rings.

**Prerequisites.** Windows 10 1607+ or Windows 11; supported editions include Pro and Enterprise ([update rings](https://learn.microsoft.com/en-us/intune/intune-service/protect/windows-10-update-rings)). The existing `Cfg-WindowsUpdate` GPO is linked to the **Workstations** OU and described in the AD project as update-management configuration. Its actual settings must be inspected and cleared where they overlap — do not rely on conflict precedence: GPO and MDM update settings are separate authorities, and a GPO that configures update sources or deferrals keeps interfering with the ring regardless of the Intune policy.

**GPO migration (on DC01).**

1. Record the current state: open the `Cfg-WindowsUpdate` GPO's settings report in **Group Policy Management**, and on CLIENT01 run `gpresult /h gporeport.html` — note every Windows Update policy that applies (in particular **Specify intranet Microsoft update service location** if the GPO configures WSUS, and any Windows Update for Business deferral/deadline policies).
2. In **Group Policy Management**, edit `Cfg-WindowsUpdate` and set the update-scoped policies — at minimum anything configuring the update service location, plus any deferral/deadline policies that overlap the ring settings below — to **Not Configured**. Leave the rest of the GPO untouched.
3. On CLIENT01, run `gpupdate /force`, then confirm the policies are gone from the applied set: re-run `gpresult /h` and check the Windows Update policy keys the report showed before (you can also verify the effective registry policies under `HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate` are cleared). Only then proceed to the Intune ring.
4. **Create the update ring.** In the Intune admin center, go to **Devices** > **By platform** > **Windows** > **Manage updates** > **Windows 10 and later updates** > **Update rings** tab > **Create profile** ([update rings](https://learn.microsoft.com/en-us/intune/intune-service/protect/windows-10-update-rings)). Name it `UPD-Win11-Ring1-Pilot`.
5. **Update ring settings**:
   | Setting | Value |
   |---|---|
   | Servicing channel | General Availability |
   | Feature update deferral period (days) | 7 |
   | Quality update deferral period (days) | 3 |
   | Automatic update behavior | Auto install at maintenance time |
   | Set feature update uninstall period (2-60 days) | 10 |
   | Use deadline settings for feature updates | Enabled, deadline 5 days, grace 2 days |

6. **Assignments**: `GRP-INT-Pilot-Devices` (device groups are recommended for rings). **Review + create**.
7. On CLIENT01, run a device sync (section 19), then check Settings > Windows Update — the device should check for updates against Windows Update. The ring's device status should list CLIENT01.

**Expected result.** CLIENT01 receives updates from Windows Update for Business with the ring's deferral behavior; the ring's device status shows the device.

**Evidence.** E-14 — before/after `gpresult` of the WSUS settings + ring assignment + CLIENT01 in the ring's device status.

**Rollback.** Restore the `Cfg-WindowsUpdate` settings you recorded and re-run `gpupdate` on the device, then delete the ring.

## Phase 3 — Applications and Scripts

### Section 15: Apps — Microsoft 365 Apps, Win32 App, Platform Script (GUI)

**Purpose.** Deliver required software three ways: the Microsoft 365 Apps suite (click-to-run), a Win32 app (7-Zip), and a PowerShell platform script.

#### 15a. Microsoft 365 Apps suite

**Prerequisite.** Business Premium includes **Microsoft 365 Apps for business**; Intune supports that edition but its app suite **must be configured with XML data** (the configuration designer is for Apps for enterprise) ([add Microsoft 365 Apps](https://learn.microsoft.com/en-us/intune/intune-service/apps/apps-add-office365)).

1. In the Intune admin center: **Apps** > **All apps** > **Create**. In **Select app type**, choose **Microsoft 365 Apps** > **Windows 10 and later** > **Select**.
2. **Basics**: name `APP-M365Apps-Business`, suite installed via Office Click-to-Run.
3. **Configure app suite**: for the business edition, select **Enter XML data** and paste (lab decision: excludes Publisher and Access; requires the suite for users who will activate with their Business Premium licenses):

   ```xml
   <Configuration>
     <Add OfficeClientEdition="64" Channel="Current">
       <Product ID="O365BusinessRetail">
         <Language ID="en-us" />
         <ExcludeApp ID="Publisher" />
         <ExcludeApp ID="Access" />
       </Product>
     </Add>
     <Property Name="ForceAppsToShutdown" Value="TRUE" />
     <RemoveMSI />
   </Configuration>
   ```

   Intune expects the complete Office Deployment Tool configuration XML — the `<Configuration>` root element is required, not just the `<Add>` fragment ([add Microsoft 365 Apps](https://learn.microsoft.com/en-us/intune/intune-service/apps/apps-add-office365)). `<RemoveMSI />` strips legacy MSI Office installs that would otherwise make the click-to-run install fail ([MSI removal note](https://learn.microsoft.com/en-us/intune/intune-service/apps/apps-add-office365)). Channel and edition are set inside the XML for the business edition.
4. **Assignments**: **Required** for `GRP-INT-Pilot-Devices` (pilot first; promote to the corporate dynamic group after validation). **Review + create**.

#### 15b. Win32 app (7-Zip)

**Prerequisite.** The `.intunewin` package must be generated first with the Microsoft Win32 Content Prep Tool (`IntuneWinAppUtil.exe`) — that is PowerShell work package 17; run it now to produce the package.

1. Download the 7-Zip x64 MSI (e.g., `7z2409-x64.msi`) from [7-zip.org](https://www.7-zip.org/) into a staging folder.
2. Run `New-Win32Package.ps1` (section 17) to generate the `.intunewin` and capture the MSI product code GUID (needed for detection).
3. In the Intune admin center: **Apps** > **All apps** > **Create** > app type **Windows app (Win32)** > **Select** ([add Win32 apps](https://learn.microsoft.com/en-us/mem/intune/apps/apps-win32-add)).
4. **Basics**: name `APP-7zip-Win32`, publisher, install behavior note.
5. **Program**: install command `msiexec /i "7z2409-x64.msi" /qn`; uninstall command `msiexec /x "{GUID}" /qn` (the GUID from step 2); install behavior **System**; allow the default 60-minute timeout ([Win32 Program settings](https://learn.microsoft.com/en-us/mem/intune/apps/apps-win32-add)).
6. **Requirements**: OS architecture **x64**; minimum OS **Windows 11**.
7. **Detection rules**: **Manually configure detection rules** > rule type **MSI** > enter the product code GUID ([Win32 detection](https://learn.microsoft.com/en-us/mem/intune/apps/apps-win32-add)).
8. **Dependencies**: none. **Review + create**.
9. **Assignments**: **Required** for `GRP-INT-Pilot-Devices`. The Intune Management Extension installs automatically on devices targeted with a Win32 app or script ([management extension](https://learn.microsoft.com/en-us/intune/intune-service/apps/powershell-scripts)).
10. Verify on CLIENT01: Settings > **Apps** > **Installed apps** shows 7-Zip; the Intune app install status shows "Installed" (portal reporting can lag; the local check is authoritative).

#### 15c. Platform script (device inventory)

1. In the Intune admin center: **Devices** > **Scripts and remediations** > **Platform scripts** > **Add** > **Windows 10 and later** ([PowerShell scripts](https://learn.microsoft.com/en-us/intune/intune-service/apps/powershell-scripts)).
2. **Basics**: name `SCR-DeviceInventory`.
3. **Script settings**: upload `Get-DeviceInventory.ps1` (under 200 KB ASCII); **Run this script using the logged on credentials**: **No** (system context); **Enforce script signature check**: **No**; **Run script in 64-bit PowerShell host**: **Yes**.
4. **Assignments**: `GRP-INT-Pilot-Devices`. Review + add.
5. The Intune Management Extension runs the script when it is assigned, and re-runs it when the script is updated or re-assigned — not on a fixed schedule. The IME checks in with Intune on its documented 8-hour cycle for script updates, so allow time for a new or changed script to reach the device, or speed it up with a device sync ([script execution](https://learn.microsoft.com/en-us/intune/intune-service/apps/powershell-scripts)). Verify on CLIENT01: the log `C:\ProgramData\Beginningdimension\Logs\DeviceInventory.log` exists and shows a fresh inventory, and the script's device status in Intune shows the last run result. The script exits 1 when it cannot write the log — that surfaces as a failed run in Intune, which is the intended signal.

**Expected result.** M365 Apps installs on CLIENT01, 7-Zip installs via IME, and the inventory script produces its log file.

**Evidence.** E-15 — installed apps on CLIENT01 + IME script status + log file.

**Rollback.** Uninstall assignments or set to Uninstall; delete the script entry.

#### 15d. MSIX line-of-business app (fourth app-delivery path)

**Purpose.** Demonstrate MSIX deployment, the modern Windows app format. Intune supports MSIX packages as line-of-business apps ([manage MSIX deployment with Intune](https://learn.microsoft.com/en-us/windows/msix/desktop/managing-your-msix-deployment-intune)).

**Prerequisites.** The MSIX package must be **signed**, and the signing certificate must be trusted by the devices — for a self-signed lab certificate that means distributing it with a Trusted Certificate configuration profile before (or at the same time as) the app is assigned ([MSIX deployment](https://learn.microsoft.com/en-us/windows/msix/desktop/managing-your-msix-deployment-intune)).

**Produce a signed MSIX (lab decision — concrete workflow).** Any repackaged app works; the lab uses the same 7-Zip installer staged for 15b so the Win32 and MSIX paths deliver comparable payloads:

1. On an admin workstation, install the **MSIX Packaging Tool** from the Microsoft Store.
2. Create a self-signed signing certificate: `New-SelfSignedCertificate -Type CodeSigningCert -Subject "CN=BD Lab MSIX Signing" -CertStoreLocation Cert:\CurrentUser\My`, export the public half to `BDLabMSIX.cer`, and the full cert with private key to a PFX kept offline.
3. In the MSIX Packaging Tool, choose **Application package** > create package on this machine, point it at `C:\Staging\7zip\7z2409-x64.msi`, fill the installer's details, and produce the `.msix`.
4. Sign it with `SignTool` (from the Windows SDK): `signtool sign /fd SHA256 /sha1 <cert-thumbprint> <package>.msix`.

**Deploy via Intune.**

1. **Trusted Certificate profile.** In the Intune admin center: **Devices** > **Manage devices** > **Configuration** > **Create** > **New policy** > platform **Windows 10 and later**, profile type **Templates** > **Trusted certificate** > **Create**. Name it `CFG-MSIX-Trust`. Upload `BDLabMSIX.cer`; set **Certificate destination store** to **Local Computer - Trusted People** (the documented requirement for MSIX signing certificates — [MSIX deployment](https://learn.microsoft.com/en-us/windows/msix/desktop/managing-your-msix-deployment-intune)). Assign to `GRP-INT-Pilot-Devices` and **Review + create**.
2. **Add the app.** **Apps** > **All apps** > **Create** > app type **Line-of-business app** > **Select** ([MSIX deployment](https://learn.microsoft.com/en-us/windows/msix/desktop/managing-your-msix-deployment-intune)). Upload the signed `.msix`; the app information fills from the package.
3. **Assignments**: **Required** with **App install context** set to **Device** (the documented recommendation for MSIX LOB apps — [MSIX deployment](https://learn.microsoft.com/en-us/windows/msix/desktop/managing-your-msix-deployment-intune)), assigned to `GRP-INT-Pilot-Devices`. **Review + create**.
4. Verify on CLIENT01: Settings > Apps > Installed apps lists the app; the app's install status in Intune shows success.
5. Troubleshooting: error `0x80073CF3` (ERROR_INSTALL_PACKAGE_DOWNGRADE) means a newer version of the app is already installed — uninstall the existing copy or match versions; also confirm the Trusted certificate profile applied before the app install ([MSIX deployment](https://learn.microsoft.com/en-us/windows/msix/desktop/managing-your-msix-deployment-intune)).

**Evidence.** E-15 — MSIX app install status + trusted certificate profile.

**Rollback.** Unassign the app and delete the Trusted certificate profile.

## Phase 4 — Access Enforcement

### Section 16: Conditional Access — MFA and Compliant Device (GUI)

**Purpose.** Gate cloud access on MFA and device compliance.

**Prerequisites.** Conditional Access requires Entra ID P1/P2 ([Conditional Access with Intune](https://learn.microsoft.com/en-us/mem/intune/protect/conditional-access-intune-common-ways-use)) — included in Business Premium. If the tenant has security defaults enabled, they must be turned off before defining custom Conditional Access policies (both enforce baseline protections and are not meant to run together). Plan the cutover deliberately, never mid-task: confirm the break-glass account's access first, disable security defaults, and immediately set `CA-MFA-AllUsers` to **On** and promote it to **All users** so MFA coverage is continuous — the compliant-device policy stays pilot-scoped during validation ([security defaults](https://learn.microsoft.com/en-us/entra/fundamentals/security-defaults)). Always exclude the break-glass account from every policy.

**Steps.**

1. Open the [Intune admin center](https://intune.microsoft.com) and open its **Conditional Access** node, then select **New policy** — Microsoft documents that device-based Conditional Access policies for Microsoft 365 products are configured through the Intune admin center, and that the Conditional Access node accessed from Intune is the same node as in the Entra admin center ([Conditional Access with Intune](https://learn.microsoft.com/en-us/mem/intune/protect/conditional-access-intune-common-ways-use)). (The equivalent Entra path is entra.microsoft.com > **Protection** > **Conditional Access**.)
2. **Policy 1 — `CA-MFA-AllUsers`**:
   - **Users**: Include `GRP-INT-Pilot-Users` (pilot scope for validation; promote to **All users** only after testing — the same pattern Microsoft's own "approved apps or app protection" template uses when rolling out to all users ([approved apps/app protection template](https://learn.microsoft.com/en-us/entra/identity/conditional-access/policy-all-users-approved-app-or-app-protection))); Exclude the break-glass account regardless of scope.
   - **Target resources**: **All resources** (all cloud apps).
   - **Grant**: **Grant access** > **Require multifactor authentication**.
   - **Enable policy**: **Report-only** first. **Create**.
3. **Policy 2 — `CA-RequireCompliantDevice`**:
   - **Users**: `GRP-INT-Pilot-Users`; exclude break-glass.
   - **Target resources**: All resources (lab decision: start with Exchange Online and SharePoint Online if you want to test on specific services first).
   - **Grant**: **Grant access** > **Require device to be marked as compliant** (Intune compliance status flows to Entra ID for this control ([Conditional Access with Intune](https://learn.microsoft.com/en-us/mem/intune/protect/conditional-access-intune-common-ways-use))).
   - **Enable policy**: **Report-only**. **Create**.
4. Test in report-only: sign in as `jdoe` to a target service, then check **Monitoring** > **Sign-in logs** > the sign-in event > **Conditional Access** tab — both policies appear with "Report-only: Success/Failure" results ([report-only behavior](https://learn.microsoft.com/en-us/entra/identity/conditional-access/policy-all-users-approved-app-or-app-protection)).
5. Remediate any report-only failures (e.g., device not yet compliant because BitLocker finished but no reboot happened), then set both policies to **On** — still at pilot scope.
6. Prove enforcement: from CLIENT01 (compliant), access succeeds; from an unmanaged device (e.g., a phone browser), access is blocked with the "compliant device" message.
7. Promotion (lab decision gate): once both policies behave at pilot scope, re-target each policy's **Users** include to **All users**, keeping the break-glass exclusion, and keep an eye on sign-in logs during the first day.

**Expected result.** Cloud access requires MFA and a compliant, Intune-managed device.

**Evidence.** E-16 — CA policies + sign-in log showing the applied controls.

**Rollback.** Set policies to Report-only or Off; never delete without excluding the break-glass account.

## Phase 5 — PowerShell Automation (the 20%)

### Section 17: Win32 App Packaging with New-Win32Package.ps1 (PowerShell)

**Purpose.** Wrap the Microsoft Win32 Content Prep Tool with validation, logging, and the MSI product-code extraction needed for the Intune app definition.

**Steps.**

1. Download `IntuneWinAppUtil.exe` from the official [Microsoft Win32 Content Prep Tool repository](https://github.com/microsoft/microsoft-win32-content-prep-tool) to your admin workstation.
2. Stage the app:
   ```powershell
   New-Item -ItemType Directory -Path C:\Staging\7zip -Force
   # Copy 7z2409-x64.msi into C:\Staging\7zip
   ```
3. Run:
   ```powershell
   .\New-Win32Package.ps1 -SetupFolder 'C:\Staging\7zip' -SetupFile '7z2409-x64.msi' `
     -IntuneWinAppUtilPath 'C:\Tools\IntuneWinAppUtil.exe' -OutputFolder 'C:\Staging\output' -LogPath 'C:\Staging\logs'
   ```
   The script validates inputs, runs `IntuneWinAppUtil.exe` with the documented parameters (`-c` setup folder, `-s` setup file, `-o` output folder) ([Win32 content prep](https://learn.microsoft.com/en-us/mem/intune/apps/apps-win32-prepare)), extracts the MSI product code, and writes a packaging log.
4. Use the outputs in section 15b: the `.intunewin` for upload, the product code for the MSI detection rule, and the log as evidence.

**Evidence.** E-17 — console output + packaging log.

### Section 18: Compliance Reporting with Get-IntuneComplianceReport.ps1 (PowerShell)

**Purpose.** Export the compliance state of every managed device to CSV using the Graph PowerShell SDK — the report you hand an interviewer.

**Steps.**

1. Install the SDK on the admin workstation: `Install-Module Microsoft.Graph` ([Graph PowerShell SDK](https://learn.microsoft.com/en-us/powershell/microsoftgraph/get-started?view=graph-powershell-1.0)).
2. Run:
   ```powershell
   .\Get-IntuneComplianceReport.ps1 -TenantId 'your-tenant-id' -OutputPath .\output
   ```
   The script connects with `Connect-MgGraph` requesting `DeviceManagementManagedDevices.Read.All` and `DeviceManagementConfiguration.Read.All`, walks managed devices with pagination, resolves their compliance policy states, and writes a timestamped CSV.
3. Confirm scope needs with `Find-MgGraphCommand -command Get-MgDeviceManagementManagedDevice | Select -First 1 -ExpandProperty Permissions` if you modify the script ([find permissions](https://learn.microsoft.com/en-us/powershell/microsoftgraph/get-started?view=graph-powershell-1.0)).
4. Read the CSV: device, OS, compliance state, last sync, per-policy status.

**Evidence.** E-18 — console run + CSV output.

### Section 19: On-Demand Device Sync with Sync-IntuneDevices.ps1 (PowerShell — optional operational utility)

**Purpose.** Trigger CLIENT01's check-in via Graph instead of waiting for the scheduled cycle — the same remote action as **Devices** > **All devices** > select device > **Sync** ([device sync](https://learn.microsoft.com/en-us/intune/intune-service/remote-actions/device-sync)). A sync forces a check-in so pending policies and apps are received; how fast they then apply depends on the device — watch the device's check-in time and policy status. This utility is handy during validation (sections 8, 12, 13, 15) but is not counted in the 80/20 ratio.

**Steps.**

1. Run:
   ```powershell
   .\Sync-IntuneDevices.ps1 -DeviceName 'CLIENT01' -TenantId 'your-tenant-id'
   ```
2. The script resolves the device, prints its last check-in time, and calls the Graph syncDevice action. Note the reported time reflects the check-in before the sync — re-run the script (or check the admin center) to see the new check-in timestamp, and confirm the pending policies then move to their applied states.

**Evidence.** E-19 — console output + updated check-in time.

### Section 20: Bulk Policy Assignment with Add-IntuneBulkAssignment.ps1 (PowerShell — optional operational utility)

**Purpose.** Add groups to a policy's assignments with one command — demonstrating assignment automation via Graph. This utility is used when promoting policies beyond the pilot and is not counted in the 80/20 ratio.

**Steps.**

1. Run:
   ```powershell
   .\Add-IntuneBulkAssignment.ps1 -PolicyType Compliance -PolicyName 'CMP-Win11-Health' `
     -GroupNames 'GRP-INT-Win11-Corporate' -TenantId 'your-tenant-id'
   ```
2. The Graph **assign** action replaces a policy's full assignment list, so the script first reads the current assignments (following pagination), backs them up to `output/assignments-backup-*.json`, then merges the new group while preserving every existing target — including exclusions and assignment filters. Only Compliance and Configuration policies are supported; security baselines use a different assignment model and are assigned in the admin center.
3. Verify: open **Devices** > **Compliance** > `CMP-Win11-Health` > **Properties** > **Assignments** — the new group is included and the previous targets are unchanged. Rollback: restore the backup file with the same assign action, or edit in the admin center.

**Evidence.** E-20 — console output + assignment list in the portal.

## Execution Order Summary

| Order | Sections | Why |
|---|---|---|
| 1 | 1 | Tenant and identities ready |
| 2 | 2, 3 | Identity sync + hybrid join foundation |
| 3 | 4, 5, 6 | Enrollment plumbing and groups |
| 4 | 7 | Pilot device enrolled (first proof point) |
| 5 | 8, 9, 10 | Compliance and baseline |
| 6 | 11, 12 | Defender onboarding, encryption |
| 7 | 13, 14 | Configuration and updates |
| 8 | 17 → 15 | Package (P1), then deploy apps, MSIX, and script |
| 9 | 16 | Conditional Access (enforce last, pilot scope first) |
| 10 | 18 | Reporting (P2) |
| — | 19, 20 | Optional operational utilities — run on demand |
