# FSLogix-DEM-ShareProvisioning

An interactive PowerShell tool for Windows file servers. It creates the storage locations for
**FSLogix profile containers** and **Omnissa Dynamic Environment Manager (DEM)**, sets the NTFS
permissions as documented by the respective vendor, creates the SMB shares, and verifies the
result by reading it back.

> **Disclaimer — not an official tool.** This is an independent community project. It is not
> affiliated with, endorsed by, or supported by Microsoft Corporation or Omnissa, LLC.
> FSLogix is a trademark of Microsoft Corporation; Omnissa and Dynamic Environment Manager are
> trademarks of Omnissa, LLC. All other trademarks belong to their respective owners. Product
> names are used only to describe what the tool works with.
>
> The tool changes NTFS permissions and SMB shares. Review the plan it shows before you confirm,
> and try it on a test server first. It is provided "as is", without warranty of any kind (see
> [LICENSE](LICENSE)).

> **Language note:** the operator interface and the code comments are in **German**. This README
> is the English documentation. The tool runs on German and English Windows Server alike.

---

## Why this tool exists

The vendor documentation describes the required permissions in tables and `icacls` examples.
Applying them by hand is error-prone, and scripts that use account names such as
`BUILTIN\Administrators` or `CREATOR OWNER` break on localized (for example German) servers,
where these principals have different names.

This tool:

- resolves all built-in principals by their **well-known SID**, never by name, so it behaves the
  same on every Windows display language;
- writes the permissions **only on the share root** and lets inheritance do the rest — it never
  touches user folders below it;
- **reads the result back and compares it** with the vendor specification, because `Set-Acl` can
  report success on a partial failure;
- creates the SMB share **only after** the NTFS permissions have been verified;
- never writes a *Deny* entry, never grants `Everyone: Full Control` on NTFS, and never changes the
  owner of a folder.

## Features

The tool offers three modes from one main menu:

| Mode | What it does |
|---|---|
| **1 — Provision new storage** | Create folders (or adopt existing ones), set the NTFS permissions, verify them, create the SMB share and verify it. Nothing is written until you type `JA` ("yes"). |
| **2 — Audit existing storage** | Scan a root folder, recognize the storage types by name, read the groups from the existing ACL, and check NTFS permissions, share permissions, offline caching and owner. Deviations can then be corrected through the same write path, again only after confirmation. Optionally, the user folders below profile shares are checked **read-only**. |
| **3 — Adjust NTFS permissions** | Add, replace or remove groups on the root of existing storage locations. A group always receives exactly the permissions of a role, never free-form rights. |

Supported storage types:

| Type | Purpose | Permission source |
|---|---|---|
| `FSLogix-Profiles` | FSLogix profile containers | Microsoft FSLogix documentation |
| `FSLogix-Redirections` | Location of `redirections.xml` | Derived (no vendor table published) |
| `DEMConfig` | DEM configuration share | Omnissa DEM documentation |
| `DEMProfiles` | DEM profile archives | Omnissa DEM documentation |
| `DEMComputerLogs` | DEM computer environment logs | Derived (no vendor table published) |

For each role (administrators group, users group, computers group) you can enter more than one
group; every additional group receives the same permissions as the first one.

## Requirements

- Windows Server with **Windows PowerShell 5.1**.
- An **elevated** PowerShell session. Without elevation the tool stops before writing anything.
- The account running the tool should be a **member of the group you enter as the administrators
  group**. Otherwise it loses access to the folder after the protected ACL is written and the
  share cannot be created. The tool warns about this beforehand. Sign out and back in after
  adding yourself to a group.
- Target folders on **NTFS or ReFS**. Drive roots, system paths and UNC paths are rejected.
- A reachable **domain controller** to resolve the groups.

## Quick start

1. Download `FSLogix-DEM-ShareProvisioning.ps1` from the
   [latest release](https://github.com/tomcek42/FSLogix-DEM-ShareProvisioning/releases/latest).
   This single file contains the complete tool.
2. Copy it to the file server **unchanged** (do not paste it through a text editor).
3. Run it from an elevated prompt:

   ```
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\FSLogix-DEM-ShareProvisioning.ps1
   ```

   Use the `-File` form. Dot-sourcing the file or calling it via `-Command` is not supported.

4. Choose a mode in the main menu and follow the dialog. Before anything is written, the tool
   shows a plan and a preflight check, and asks you to type `JA`. Pressing Enter alone is not
   enough.

After each run you can show a detailed report (`R`), return to the main menu (`M`) or exit (`E`).

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Everything matches the specification |
| 1 | Warnings, for example existing content in a target folder |
| 2 | Errors, for example a permission deviation or a blocked target |
| 3 | Cancelled, the confirmation was not typed |

After several runs in one session, the highest code is returned.

### Keeping a transcript

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\FSLogix-DEM-ShareProvisioning.ps1 > run.txt
```

Plan, report and summary go to the file; the questions stay on the console. Colors are switched
off in this mode on purpose.

## Running from source

Instead of the single-file release you can run the tool from this repository. Keep
`FSLogix-DEM-ShareProvisioning.ps1` and the `DemFsAcl` folder together in the same directory and start it
the same way as above. The source form additionally shows the vendor reference (URL and section)
for every permission entry in the detailed report.

To build the single file yourself:

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Tools\Build-DemFsBundle.ps1
```

The result is written to `dist\FSLogix-DEM-ShareProvisioning.ps1`. The build needs `git` and must run
inside a clone of this repository; the two header lines of the bundle record the source commit.

## What the tool deliberately does not do

- It never sets permissions on user folders below a share root. FSLogix and DEM create those
  folders themselves; a recursive change would lock users out of their own profiles.
- It never creates user folders in advance.
- No *Deny* entries, no `Everyone: Full Control` on NTFS, no `icacls.exe`.
- It never changes the owner of a folder; it only reports it.
- No log file, no unattended mode, no remote execution.
- No Azure Files or Azure NetApp Files.

## Vendor documentation

The permission templates are based on:

- Microsoft: [Configure SMB storage permissions for FSLogix](https://learn.microsoft.com/en-us/fslogix/how-to-configure-storage-permissions)
- Omnissa: [DEM configuration share](https://docs.omnissa.com/DEMInstallConfigGuide-V2606/DynamicEnvironmentManagerConfigurationShare)
- Omnissa: [DEM profile archives share](https://docs.omnissa.com/DEMInstallConfigGuide-V2606/ProfileArchivesShare)

Where a vendor publishes no permission table, the template is marked as *derived*.

## License

[MIT](LICENSE) — © 2026 tomcek42.
