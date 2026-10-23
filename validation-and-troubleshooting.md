# Validation and Troubleshooting

Two goals: prove the deployment works (validation), and prove you can fix it when it doesn't (troubleshooting). The second half is the interview material — anyone can click through the admin center; the engineer who knows where the logs live can defend the deployment.

## Part 1 — Validation Matrix

Run each check after the matching work package; capture the output as evidence (`docs/evidence-checklist.md`).

| # | What to prove | Command / location | Expected result | Package |
|---|---|---|---|---|
| V1 | Identity sync works | Entra admin center > Identity > Users > `jdoe` | Source: Windows Server AD | 2 |
| V2 | Hybrid join configured | Discover the SCP: `$configNC = (Get-ADRootDSE).ConfigurationNamingContext; Get-ADObject -SearchBase "CN=Device Registration Configuration,CN=Services,$configNC" -SearchScope Subtree -Filter * -Properties cn` | SCP object exists in the Device Registration Configuration container (end-to-end proof is CLIENT01 hybrid-joining in V3) | 3 |
| V3 | CLIENT01 hybrid-joined | `dsregcmd /status` on CLIENT01 | `AzureAdJoined: YES`, `DomainJoined: YES` ([hybrid join](https://learn.microsoft.com/en-us/entra/identity/devices/how-to-hybrid-join)) | 7 |
| V4 | MDM enrolled | Intune admin center > Devices > All devices > CLIENT01 (plus `dsregcmd /status` MdmUrl as supporting signal) | Device record exists; join type hybrid joined; enrollment task succeeded | 7 |
| V5 | Device visible and reporting | Intune admin center > Devices > All devices > CLIENT01 | Join type "Microsoft Entra hybrid joined"; Last check-in recent | 7 |
| V6 | Compliance evaluated | Devices > Compliance > Monitor > Device compliance status | CLIENT01 = Compliant | 8 |
| V7 | Custom compliance rules fire | CMP-Win11-Custom > Monitor > Per-setting status | RdpDisabled/Smbv1Disabled rows show pass counts | 9 |
| V8 | Baseline applied | Endpoint security > Security baselines > SB-MDM-Win11 > profile > Device assignment status | CLIENT01 Succeeded | 10 |
| V9 | Defender onboarding | Defender portal > Assets > Devices | CLIENT01 onboarded, sensors reporting | 11 |
| V10 | Encryption + escrow | `manage-bde -status` and Entra admin center > Devices > CLIENT01 > BitLocker keys | OS drive "Protection On"; recovery key listed | 12 |
| V11 | Config profiles apply | Devices > Manage devices > Configuration > each profile > Device assignment status | Succeeded | 13 |
| V12 | Update ring takes over | Before/after `gpresult` on CLIENT01 + Settings > Windows Update | Update-scoped GPO settings no longer applied; device services against Windows Update; ring lists CLIENT01 | 14 |
| V13 | Apps install | Settings > Apps > Installed apps on CLIENT01 | Microsoft 365 Apps + 7-Zip present | 15 |
| V14 | Platform script runs | `C:\ProgramData\Beginningdimension\Logs\DeviceInventory.log` | Fresh timestamped JSON line | 15 |
| V15 | CA gates access | Intune admin center > Conditional Access node (policies); Entra admin center > Monitoring > Sign-in logs > event > Conditional Access tab | CA-MFA-AllUsers + CA-RequireCompliantDevice applied; failure from unmanaged device | 16 |
| V16 | Graph automation works | `Get-IntuneComplianceReport.ps1` output CSV | All devices listed with compliance states | 18 |

## Part 2 — Troubleshooting Runbooks

### Runbook A: Device Will Not Hybrid-Join

1. **Check the SCP exists** (V2). No SCP = devices cannot discover the tenant. Re-run Entra Connect > Configure > Configure device options (section 3).
2. **Check sync scope.** The computer object must be in a synced OU — `Computers\Workstations` is under `Beginningdimension`, which is inside the OU filter. A device in a non-synced OU cannot complete hybrid join ([hybrid join prerequisites](https://learn.microsoft.com/en-us/entra/identity/devices/how-to-hybrid-join)).
3. **Check connectivity** from the device SYSTEM account to the Entra device registration endpoints (Microsoft's Test Device Registration Connectivity script is referenced in the hybrid join docs ([hybrid join](https://learn.microsoft.com/en-us/entra/identity/devices/how-to-hybrid-join))).
4. **Read the device logs**: Event Viewer > Applications and Services Logs > Microsoft > Windows > User Device Registration > Admin. Errors here name the failing step.
5. **`dsregcmd /status`** tells you which half is broken: `DomainJoined: NO` is an AD problem, not Entra.

### Runbook B: Device Hybrid-Joined but Not MDM-Enrolled

1. **MDM user scope**: confirm the signed-in user is in the group selected under Devices > Enrollment > Windows > Automatic Enrollment ([automatic enrollment](https://learn.microsoft.com/en-us/intune/intune-service/enrollment/windows-enroll)).
2. **GPO applied?** `gpresult /r` on the client must list `Cfg-AutoMDMEnrollment`. If missing, check the GPO link on the Workstations OU and run `gpupdate /force`.
3. **Task Scheduler evidence**: Task Scheduler Library > Microsoft > Windows > EnterpriseMgmt — the enrollment task's Last Run Result and History show whether enrollment started and why it failed ([GPO enrollment diagnostics](https://learn.microsoft.com/en-us/windows/client-management/enroll-a-windows-10-device-automatically-using-group-policy)).
4. **Enrollment restrictions**: if personal Windows enrollment is blocked, enrollment through the GPO is still authorized as corporate ([enrollment restrictions](https://learn.microsoft.com/en-us/intune/device-enrollment/restrictions)) — if you used a different enrollment method, that is the place to look.
5. **User license**: the user needs an Intune-capable license (Business Premium qualifies) — an unlicensed user's devices cannot enroll.

### Runbook C: Compliance Stuck "Not compliant"

1. **Find the failing setting**: Devices > Compliance > the policy > Monitor > **Per-setting status** shows which rule and how many devices fail it ([compliance monitoring](https://learn.microsoft.com/en-us/intune/intune-service/protect/compliance-policy-monitor)).
2. **BitLocker rule**: measured at boot — after encryption completes, reboot and re-check ([Windows compliance settings](https://learn.microsoft.com/en-us/intune/intune-service/protect/compliance-policy-create-windows)).
3. **Firewall rule**: a conflicting GPO that turns the firewall off or allows all inbound traffic makes `Firewall: Require` fail even when an Intune policy enables the firewall ([Windows compliance settings](https://learn.microsoft.com/en-us/intune/intune-service/protect/compliance-policy-create-windows)) — check the settings-ownership matrix.
4. **Fresh evaluation**: sync the device (admin center Sync button or `Sync-IntuneDevices.ps1`), then check status. Devices must check in before reports update; allow up to 24 hours or force it ([compliance reporting](https://learn.microsoft.com/en-us/intune/intune-service/protect/compliance-policy-monitor)).
5. **No compliance policy at all**: the tenant-wide setting marks such devices non-compliant by design once enabled (section 8).

### Runbook D: Win32 App or Platform Script Not Installing

1. **Where the logs live**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs` — `IntuneManagementExtension.log` (main agent log), `AgentExecutor.log` (PowerShell script execution), `AppWorkload.log` (app installs and detection), `ClientHealth.log`, `HealthScripts.log` (remediation/custom compliance). View with CMTrace or a text editor ([Win32 troubleshooting](https://learn.microsoft.com/en-us/intune/app-management/deployment/troubleshoot-win32)).
2. **Is the IME installed?** It only appears after a Win32 app or script is targeted ([management extension](https://learn.microsoft.com/en-us/intune/intune-service/apps/powershell-scripts)). Check Services for "Microsoft Intune Management Extension".
3. **Detection**: verify the detection rule against reality — for a file version, use `[System.Diagnostics.FileVersionInfo]::GetVersionInfo("<path>").FileVersion` ([Win32 troubleshooting](https://learn.microsoft.com/en-us/intune/app-management/deployment/troubleshoot-win32)).
4. **Custom detection scripts**: exit code 0 + stdout = installed; any stderr = not installed ([detection rules](https://learn.microsoft.com/en-us/mem/intune/apps/apps-win32-add)).
5. **Collect logs remotely**: the app's Installation details pane in Intune has a **Collect logs** action ([Win32 troubleshooting](https://learn.microsoft.com/en-us/intune/app-management/deployment/troubleshoot-win32)).
6. **User-targeted app needing admin rights fails** — switch to device targeting or System install behavior ([Win32 app settings](https://learn.microsoft.com/en-us/mem/intune/apps/apps-win32-add)).

### Runbook E: Custom Compliance Rules Report Nothing

1. **Check script + JSON names match**: every `SettingName` in the JSON must match the property name the script emits, exactly (case-sensitive) ([custom compliance JSON](https://learn.microsoft.com/en-us/intune/intune-service/protect/compliance-custom-json)).
2. **Check stdout hygiene**: the discovery script must print only the JSON; our script sends diagnostics to a file for this reason.
3. **Timing**: the IME runs discovery every 8 hours, plus on user-initiated **Check compliance** in Company Portal ([custom compliance settings](https://learn.microsoft.com/en-us/intune/intune-service/protect/compliance-use-custom-settings)).
4. **Script uploaded before the policy?** The discovery script must exist in Intune before the policy can select it ([custom compliance settings](https://learn.microsoft.com/en-us/intune/intune-service/protect/compliance-use-custom-settings)).

### Runbook F: Conditional Access Blocks or Fails to Block

1. **Read the sign-in log first**: Entra admin center > Monitoring > **Sign-in logs** > the sign-in > **Conditional Access** tab shows every policy that evaluated, in report-only or enforced mode. This is the single most useful CA diagnostic surface.
2. **Report-only shows "Failure" for grant controls that are not enforced** — that is expected until the policy is On ([report-only behavior](https://learn.microsoft.com/en-us/entra/identity/conditional-access/policy-all-users-approved-app-or-app-protection)).
3. **Device not compliant?** Run runbook C; the CA result only mirrors the compliance state.
4. **Device not registered?** "Require compliant device" needs the device identity — run runbook A.
5. **Locked out?** Sign in with the break-glass account (excluded from all policies) and set the policy to Report-only while you investigate.

### Runbook G: Client-Side Log Grab (Windows)

Users can export management logs from the device without admin rights: Settings > Accounts > Access work or school > **Export your management log files** — files land in `C:\Users\Public\Public Documents\MDMDiagnostics` ([share management logs](https://learn.microsoft.com/en-us/intune/user-help/diagnostics/collect-logs-settings-windows)). Company Portal can also upload its own logs to support ([Company Portal reporting](https://learn.microsoft.com/en-us/intune/user-help/diagnostics/collect-logs-company-portal-windows)).

## Part 3 — Controlled Failure Tests

The tests that turn screenshots into a story:

| Test | Do | Expected failure you can fix on camera |
|---|---|---|
| F1 | Temporarily raise the **Minimum OS version** in `CMP-Win11-Health`: first record CLIENT01's actual reported OS version (device's **Hardware** page or `winver`) and the policy's currently configured minimum (policy's **Configured settings** page — these are two different numbers), then set the minimum to any valid value strictly greater than the observed device version (e.g., device reports `10.0.26200` → set `10.0.26300`) | CLIENT01 flips to Not compliant at the next evaluation with the OS version rule listed as failing; the compliant-device CA policy blocks access; restoring the recorded original minimum + sync restores compliance — a fully reversible test that never weakens protection |
| F2 | Temporarily change the custom-compliance JSON operand for `Smbv1Disabled` from `true` to `false` | CLIENT01 fails the custom rule and is marked non-compliant; restoring the operand and re-checking compliance recovers it |
| F3 | Sign in from an unmanaged device (phone browser) | CA-RequireCompliantDevice blocks with the remediation message |
| F4 | Uninstall 7-Zip | Intune re-installs it at next app evaluation cycle |
| F5 | Temporarily narrow the dynamic group rule (e.g., change `deviceOSVersion -startsWith "10.0.2"` to a non-matching value like `10.0.9`) | CLIENT01 drops out of `GRP-INT-Win11-Corporate`; restore the rule and membership returns after processing |

Document each test with a before/during/after capture and one line on which policy did the enforcement. That narrative — detect, enforce, remediate, recover — is the interview answer.
