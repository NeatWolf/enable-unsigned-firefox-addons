# Enable Unsigned Firefox Add-ons

![Source Available](https://img.shields.io/badge/source-available-2f6f9f)
![No Support](https://img.shields.io/badge/support-none-6b7280)
![Dry Run First](https://img.shields.io/badge/safety-dry--run%20first-2ea043)
![No AI Training](https://img.shields.io/badge/AI%20training-no-b42318)

Patch a local Firefox Release install so unsigned add-ons can be loaded without switching to Developer Edition.

> Warning: This modifies a local Firefox install. Future Firefox releases can break it.
>
> This project is provided as-is, with no support commitment and no compatibility guarantee. Keep your own backup or be ready to reinstall Firefox. See [LICENSE](LICENSE) and [SUPPORT.md](SUPPORT.md).

This is source-available showcase software, not an open-source project. The license allows viewing and personal local testing of unmodified copies only. It forbids redistribution, modified versions, published forks, and AI training use.

## Download

Download the latest release ZIP. Do not download files one by one, and do not use GitHub's `Code` > `Download ZIP` source archive unless you specifically want the full source tree.

1. Open [Releases](https://github.com/NeatWolf/enable-unsigned-firefox-addons/releases/latest).
1. Download `enable-unsigned-firefox-addons.zip` from the release assets.
1. Extract it anywhere convenient, such as `Downloads` or `Desktop`.
1. On Windows, open the extracted folder and double-click `START-WINDOWS.cmd`.
1. On Git Bash, macOS, or Linux, use the commands in the Advanced command-line use section below.

Keep the extracted folder together, including its `scripts` folder. Do not copy individual files around. Do not put the scripts inside the Firefox install folder.

The release ZIP contains only the files normal users need:

| System | Run these files |
| --- | --- |
| Windows | `START-WINDOWS.cmd` from the extracted folder |
| Git Bash, macOS, Linux | `patch-firefox.sh`, `unpatch-firefox.sh`, `clear-startup-cache.sh` |

The source repository contains extra documentation, local verification, and repository metadata. Normal users do not need those files.

## Quick start

On Windows:

1. Double-click `START-WINDOWS.cmd`.
1. Choose `1` to check Firefox patch status.
1. Choose `2` to pick a Firefox profile and test the setup without changing files.
1. Choose `3` to apply the full setup. The menu asks again which Firefox profile should allow unsigned add-ons.
1. Use `A`, `B`, and `C` later when you want to restore Firefox before updating it.

The menu opens in the correct folder automatically. Real patch, restore, preference, and cache-cleanup actions ask before changing files. Option 2 does not change Firefox and does not need administrator permission. If option 2 succeeds, return to the menu and choose option 3 for the real setup. When option 3 asks for a profile, choose the same profile unless you intentionally want a different Firefox profile. Option 3 applies the full setup: patch Firefox, set that profile's add-on setting, and clear startup cache. There is no extra phase after it finishes. Option 3 verifies that Firefox was patched before it changes the profile setting or clears cache. Option 3 may still ask Windows for administrator approval when Firefox is installed under `C:\Program Files\Mozilla Firefox`; that approval is what allows the script to replace Firefox program files.

Windows needs Git Bash from Git for Windows to run these scripts. If Git for Windows is missing, the launcher stops and tells you before changing anything. The Windows administrator prompt may mention Windows PowerShell. Git Bash is only the local script runner used by this project; the tool is not doing a Git download, update, sign-in, or internet action.

The Windows menu uses single-key prompts. You do not need to press Enter for menu choices, and unexpected keys are ignored instead of being treated as commands.

The Windows launchers append a local log at `logs\enable-unsigned-firefox-addons.log` inside the extracted folder. The log stays on your machine and can be deleted. It may include command output, local Firefox install paths, and Firefox profile paths.

## What gets changed

- Firefox program files: the patch changes Firefox `omni.ja` and keeps `omni-orig.ja` as the rollback backup.
- Firefox profile: a profile is Firefox's user-data folder for one setup. It stores settings, add-ons, history, bookmarks, passwords, and other user data. Setup changes one setting in the profile you choose: `xpinstall.signatures.required=false`.
- Startup cache: cleanup removes Firefox `startupCache` folders. These are rebuildable startup files. This does not delete bookmarks, passwords, history, form data, settings, cookies, add-ons, or profiles.

If you use one normal Firefox setup, choose the profile marked default. If you use Firefox Profile Manager or separate profiles, choose the profile where you will install the unsigned add-on. The tool does not change every profile unless you explicitly use `--all-profiles`.

## Advanced command-line use

These commands are for users who already prefer a terminal.

From Windows, run these from the extracted folder:

```powershell
.\patch-firefox.cmd --status
.\patch-firefox.cmd --dry-run
.\patch-firefox.cmd
.\set-unsigned-addon-pref.cmd --status
.\set-unsigned-addon-pref.cmd --dry-run
.\set-unsigned-addon-pref.cmd
.\clear-startup-cache.cmd --status
.\clear-startup-cache.cmd --dry-run
.\clear-startup-cache.cmd
```

From Git Bash, macOS, or Linux, run these from the extracted folder:

```bash
bash ./patch-firefox.sh --status
bash ./patch-firefox.sh --dry-run
bash ./patch-firefox.sh
bash ./set-unsigned-addon-pref.sh --status
bash ./set-unsigned-addon-pref.sh --dry-run
bash ./set-unsigned-addon-pref.sh
bash ./clear-startup-cache.sh --status
bash ./clear-startup-cache.sh --dry-run
bash ./clear-startup-cache.sh
```

Run `--status` first, then `--dry-run`. The Windows launchers ask for confirmation before modifying files and show the matching `--dry-run` command to try first. `--status`, `--dry-run`, and `--help` do not ask and do not change Firefox. Successful commands print the next practical step before exiting.

If auto-detection does not find Firefox, pass the install directory explicitly:

```powershell
.\patch-firefox.cmd --status --mozilla-home "C:\Program Files\Mozilla Firefox"
.\patch-firefox.cmd --dry-run --mozilla-home "C:\Program Files\Mozilla Firefox"
.\patch-firefox.cmd --mozilla-home "C:\Program Files\Mozilla Firefox"
```

Bash accepts the same `--mozilla-home /path/to/firefox` option.

For patch and restore commands, pass the Firefox install folder that contains `omni.ja`. For the add-on setting and startup-cache cleanup, pass a Firefox profile directory or a `profiles.ini` file when auto-detection is not enough. Windows paths such as `C:\Program Files\Mozilla Firefox` are accepted and normalized when needed.

The add-on setting helper changes the default Firefox profile by default. Use `--profile "C:\Users\Name\AppData\Roaming\Mozilla\Firefox\Profiles\xxxxxxxx.default-release"` for one specific profile, or `--all-profiles` only when you intentionally want every detected profile changed.

Git for Windows includes Git Bash. The `.cmd` launchers use Git Bash and intentionally skip WSL bash.

## About Unsigned Add-on Support

The standard release channel builds of Firefox require add-ons to be signed by Mozilla. That requirement cannot be disabled by simple settings, including `about:config`.

[Firefox Developer Edition](https://www.mozilla.org/en-US/firefox/developer/) doesn't have this limitation. You can install unsigned extensions by downloading Firefox Developer Edition and then toggle `xpinstall.signatures.required` to false in `about:config`. The Developer Edition is effectively a beta release channel, and is updated nightly.

This repo exists for the narrower case where you intentionally want a standard release channel Firefox and still need to run your own unsigned local add-ons.

## Prerequisites

The scripts need `bash`, `unzip`, `mktemp` (from GNU coreutils), `grep`, and `sed` for inspection and verification. Patching prefers Info-ZIP `zip` to rebuild `omni.ja`. On Windows, if `zip` is not installed, `patch-firefox.sh` can use PowerShell/.NET instead. Python is only a final optional fallback and should not be assumed on target machines.

On Windows, a real patch or restore of a protected Firefox install can request administrator permission through a UAC prompt. This is normal for Firefox installs under `C:\Program Files\Mozilla Firefox`. `--status` and `--dry-run` do not request elevation and should work before you have write access. Passing dry run means the archive can be read, rebuilt in a temporary folder, and verified; it does not mean Windows has already allowed writes to `Program Files`. If Firefox is still open, real patch and restore commands stop before rebuilding or restoring files.

## Repository layout

- `patch-firefox.cmd`: Windows launcher that finds Git Bash, asks before modifying files, and runs `patch-firefox.sh`.
- `unpatch-firefox.cmd`: Windows launcher that finds Git Bash, asks before modifying files, and runs `unpatch-firefox.sh`.
- `clear-startup-cache.cmd`: Windows launcher that finds Git Bash, asks before modifying files, and runs `clear-startup-cache.sh`.
- `set-unsigned-addon-pref.cmd`: Windows launcher that finds Git Bash, asks before editing the profile add-on setting, and runs `set-unsigned-addon-pref.sh`.
- `START-WINDOWS.cmd`: double-click Windows menu for status, dry-run, patch, startup-cache cleanup, restore, and README access.
- `patch-firefox.sh`: inspects status, dry-runs safely, edits Firefox `AppConstants`, verifies the replacement archive, then backs up `omni.ja` to `omni-orig.ja` and swaps in the patched archive.
- `unpatch-firefox.sh`: inspects status, dry-runs safely, restores `omni.ja` from `omni-orig.ja` through a temporary replacement file, then removes the backup.
- `clear-startup-cache.sh`: inspects or clears Firefox profile `startupCache` directories listed in `profiles.ini`, with status and dry-run support.
- `set-unsigned-addon-pref.sh`: inspects or sets the add-on setting in Firefox profile `prefs.js`, with status and dry-run support.
- `CHANGELOG.md`: high-level summary of user-visible script and repository changes.
- `findings.md`: short notes about verified local behavior that affected the user-facing scripts.
- `MAINTENANCE.md`: short checklist for keeping script changes small, verified, and user-readable.
- `scripts/append-log.ps1`: local log writer used by the Windows launchers.
- `scripts/read-choice.ps1`: quiet single-key input helper used by the Windows launchers.
- `scripts/debug-choice-beep.cmd`: debug-only repro helper for the Windows `choice.exe` system-beep behavior.
- `scripts/verify.ps1`: lightweight repository checks that are safe to run on Windows and do not modify Firefox.
- `scripts/verify-fixture.sh`: disposable patch/unpatch fixture test, run by `verify.ps1` when Bash has the required Unix tools.
- `.github/workflows-disabled/verify.yml`: parked GitHub Actions workflow, kept for later reactivation but not run by GitHub.
- `.github/dependabot-disabled.yml`: parked Dependabot config for GitHub Actions updates.
- `.github/ISSUE_TEMPLATE/config.yml`: disables blank GitHub issues and points readers back to the as-is support policy.
- `AGENTS.md`: rules for future automated work in this repository.
- `LICENSE`: source-available showcase license, no-AI-training restriction, and no-warranty notice.
- `SUPPORT.md`: support policy and as-is notice.
- `SECURITY.md`: security policy and supported-version notice.

## Verify changes

Run the local repository checks after making changes:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1
```

If you have a working Bash installation, also run:

```bash
bash -n patch-firefox.sh
bash -n unpatch-firefox.sh
```

## Patching

Follow the following steps to patch Firefox to disable addon signing.

1. Update Firefox to the latest version before starting, to save extra steps to update later.
1. Configure Firefox not to auto-update using `about:preferences#general`, because you will now have additional manual steps to update (see the Updating section).
1. Find the directory where you have installed Firefox. This is the path where `omni.ja` resides. On many installs it is also the directory containing the `firefox` binary.
1. Ensure that you have exited from Firefox. The scripts refuse to modify `omni.ja` if Firefox appears to be running from `MOZILLA_HOME`.
1. Run `patch-firefox.cmd --status --mozilla-home /path/to/firefox` on Windows, or `patch-firefox.sh --status --mozilla-home /path/to/firefox` from Bash, to inspect the Firefox application version and build ID, archive, current signing constant, rollback backup, archive repacker, Firefox process state, and suggested next step without modifying anything.
1. Run the same command with `--dry-run` to confirm that the archive can be extracted, patched, rebuilt, and verified without modifying Firefox. Dry run does not write to `MOZILLA_HOME`, so it should work even before you have admin/write access for the real patch. If it succeeds, it tells you to run the same command without `--dry-run`.
1. Run the patch command without `--status` or `--dry-run`. On Windows, the launcher asks for confirmation first, then requests UAC elevation automatically if the Firefox directory is protected. If it works, the last line should be Done.
1. Run `set-unsigned-addon-pref.cmd --status` on Windows, or `set-unsigned-addon-pref.sh --status` from Bash, to see detected Firefox profiles and whether each one already allows unsigned add-ons.
1. Run `set-unsigned-addon-pref.cmd --dry-run` on Windows, or `set-unsigned-addon-pref.sh --dry-run` from Bash, to preview the default profile's add-on setting change. If you use another profile, pass that profile with `--profile /path/to/profile`.
1. Run `set-unsigned-addon-pref.cmd` on Windows, or `set-unsigned-addon-pref.sh` from Bash, to set the add-on setting in the default profile. The helper stops if Firefox is still running.
1. Run `clear-startup-cache.cmd --status` on Windows, or `clear-startup-cache.sh --status` from Bash, to see which Firefox profiles the helper detects and whether any startupCache folders are present.
1. Run `clear-startup-cache.cmd --dry-run` on Windows, or `clear-startup-cache.sh --dry-run` from Bash, to preview Firefox profile `startupCache` directories that will be cleared. If Firefox is still running, dry run warns but does not change anything; the real cleanup still stops until Firefox is closed. If it succeeds, it tells you to run the same command without `--dry-run`.
1. Run `clear-startup-cache.cmd` on Windows, or `clear-startup-cache.sh` from Bash, to remove those `startupCache` directories. On Windows, the launcher asks for confirmation before deleting cache folders. Startup cache is rebuildable startup data, not bookmarks, passwords, history, form data, settings, cookies, add-ons, or profiles. The helper uses Firefox `profiles.ini`; for an unusual profile location, pass `--profile /path/to/profile`. Windows paths such as `C:\Users\Name\AppData\Roaming\Mozilla\Firefox\Profiles\xxxxxxxx.default-release` are accepted by the `.cmd` launcher.
1. Start Firefox.
1. Navigate to `about:config`.
1. While on `about:config`, go to the Developer tools (F12 by default), and switch to the Console tab. Type in `ChromeUtils.importESModule("resource://gre/modules/AppConstants.sys.mjs").AppConstants.MOZ_REQUIRE_SIGNING`. If you see `false`, the patching has worked. If you see true, something has not worked. Older Firefox builds may require `ChromeUtils.import("resource://gre/modules/AppConstants.jsm").AppConstants.MOZ_REQUIRE_SIGNING` instead. If it did not work, ensure you have run the `patch-firefox.sh` script with the correct MOZILLA_HOME, and that you have successfully deleted the startupCache before starting Firefox, and try again.
1. If you did not use `set-unsigned-addon-pref`, search for `xpinstall.signatures.required` in `about:config`, and change the value to false if it is true.
1. Copy your extension into the extensions subdirectory of your Firefox profile directory.
1. Restart Firefox. Firefox will prompt to confirm that you want to enable the addon.

## Upgrading Firefox

You should continue to upgrade Firefox whenever it prompts you to upgrade it to ensure you have the latest security patches. However, before applying upgrades, you should:

1. Exit from Firefox.
1. Run `unpatch-firefox.cmd --status --mozilla-home /path/to/firefox` on Windows, or `unpatch-firefox.sh --status --mozilla-home /path/to/firefox` from Bash, to confirm that the install is currently patched and has a rollback backup. The status output also gives the suggested next step without modifying anything.
1. Run the same command with `--dry-run` to confirm that the backup can be staged for restore. If it succeeds, it tells you to run the same command without `--dry-run`.
1. Run the restore command without `--status` or `--dry-run`. On Windows, the launcher asks for confirmation first, then requests UAC elevation automatically if the Firefox directory is protected. A successful restore removes `omni-orig.ja`.
1. Start Firefox using the `-ProfileManager` option, and start it using a different profile - create a new one if necessary (don't start it with your normal profile as this will disable all your unsigned addons, and you will need to clear caches again).
1. Apply the update.
1. Run `patch-firefox.sh`
1. Start Firefox again using your default profile.
