# Purpose

[![Verify](https://github.com/NeatWolf/enable-unsigned-firefox-addons/actions/workflows/verify.yml/badge.svg)](https://github.com/NeatWolf/enable-unsigned-firefox-addons/actions/workflows/verify.yml)

This lets you modify your local Firefox installation so that you can use a standard release channel Firefox, but still install unsigned addons.

You probably only want to do this if you are a developer of add-ons (for example, of your own personal addons you want to run locally but not share with Mozilla for signing).

This project is provided as-is, with no support commitment and no guarantee that it will keep working with future Firefox releases.

# About unsigned addon support

The standard release channel builds of Firefox now have a setting built into them that means that all addons must be signed by Mozilla, and this setting cannot be changed by simple means (including through settings in `about:config`).

[Firefox Developer Edition](https://www.mozilla.org/en-US/firefox/developer/) doesn't have this limitation. You can install unsigned extensions by downloading Firefox Developer Edition and then toggle `xpinstall.signatures.required` to false in `about:config`. The Developer Edition is effectively a beta release channel, and is updated nightly.

For various reasons, you might prefer to be on the more stable release channel. If you want that, but to also install unsigned addons, the scripts provided here are what you need.

# Prerequisites

The scripts use `bash`, `unzip`, `mktemp` (from GNU coreutils), `grep`, and `sed` for inspection and verification. Patching prefers Info-ZIP `zip` to rebuild `omni.ja`. If `zip` is not installed on Windows, `patch-firefox.sh` can rebuild the archive with PowerShell/.NET. Python is only a final optional fallback and should not be assumed on target machines.

On Windows, a real patch or restore of a protected Firefox install can request administrator permission through a UAC prompt. `--status` and `--dry-run` do not request elevation and should work before you have write access. If Firefox is still open, real patch and restore commands stop before rebuilding or restoring files.

# Repository layout

- `patch-firefox.cmd`: Windows launcher that finds Git Bash, asks before modifying files, and runs `patch-firefox.sh`.
- `unpatch-firefox.cmd`: Windows launcher that finds Git Bash, asks before modifying files, and runs `unpatch-firefox.sh`.
- `clear-startup-cache.cmd`: Windows launcher that finds Git Bash, asks before modifying files, and runs `clear-startup-cache.sh`.
- `patch-firefox.sh`: inspects status, dry-runs safely, edits Firefox `AppConstants`, verifies the replacement archive, then backs up `omni.ja` to `omni-orig.ja` and swaps in the patched archive.
- `unpatch-firefox.sh`: inspects status, dry-runs safely, restores `omni.ja` from `omni-orig.ja` through a temporary replacement file, then removes the backup.
- `clear-startup-cache.sh`: inspects or clears Firefox profile `startupCache` directories listed in `profiles.ini`, with status and dry-run support.
- `scripts/verify.ps1`: lightweight repository checks that are safe to run on Windows and do not modify Firefox.
- `scripts/verify-fixture.sh`: disposable patch/unpatch fixture test, run by `verify.ps1` when Bash has the required Unix tools.
- `.github/ISSUE_TEMPLATE/config.yml`: disables blank GitHub issues and points readers back to the as-is support policy.
- `AGENTS.md`: rules for future automated work in this repository.
- `SUPPORT.md`: support policy and as-is notice.

# Verify changes

Run the local repository checks after making changes:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1
```

If you have a working Bash installation, also run:

```bash
bash -n patch-firefox.sh
bash -n unpatch-firefox.sh
```

# Quick start

On Windows, start from PowerShell or Command Prompt:

```powershell
.\patch-firefox.cmd --status
.\patch-firefox.cmd --dry-run
.\patch-firefox.cmd
.\clear-startup-cache.cmd --status
.\clear-startup-cache.cmd --dry-run
.\clear-startup-cache.cmd
```

You can also double-click a `.cmd` launcher. If it fails when launched that way, it leaves the window open so the error message can be read. Command-line use exits normally.

The Windows launchers ask for confirmation before modifying files. `--status`, `--dry-run`, and `--help` do not ask and do not change Firefox.

If the Windows launcher cannot auto-detect the install directory, pass it explicitly:

```powershell
.\patch-firefox.cmd --status --mozilla-home "C:\Program Files\Mozilla Firefox"
.\patch-firefox.cmd --dry-run --mozilla-home "C:\Program Files\Mozilla Firefox"
.\patch-firefox.cmd --mozilla-home "C:\Program Files\Mozilla Firefox"
```

From Git Bash, macOS, or Linux, use the shell scripts directly:

```bash
./patch-firefox.sh --status
./patch-firefox.sh --dry-run
./patch-firefox.sh
./clear-startup-cache.sh --status
./clear-startup-cache.sh --dry-run
./clear-startup-cache.sh
```

If the script cannot auto-detect the install directory, pass it explicitly:

```bash
./patch-firefox.sh --status --mozilla-home "/path/to/firefox"
./patch-firefox.sh --dry-run --mozilla-home "/path/to/firefox"
./patch-firefox.sh --mozilla-home "/path/to/firefox"
```

# Patching

Follow the following steps to patch Firefox to disable addon signing.

1. Update Firefox to the latest version before starting, to save extra steps to update later.
1. Configure Firefox not to auto-update using `about:preferences#general`, because you will now have additional manual steps to update (see the Updating section).
1. Find the directory where you have installed Firefox. This is the path where `omni.ja` resides. On many installs it is also the directory containing the `firefox` binary.
1. Ensure that you have exited from Firefox. The scripts refuse to modify `omni.ja` if Firefox appears to be running from `MOZILLA_HOME`.
1. Run `patch-firefox.cmd --status --mozilla-home /path/to/firefox` on Windows, or `patch-firefox.sh --status --mozilla-home /path/to/firefox` from Bash, to inspect the archive, current signing constant, rollback backup, and Firefox process state without modifying anything.
1. Run the same command with `--dry-run` to confirm that the archive can be extracted, patched, rebuilt, and verified without modifying Firefox. Dry run does not write to `MOZILLA_HOME`, so it should work even before you have admin/write access for the real patch.
1. Run the patch command without `--status` or `--dry-run`. On Windows, the launcher asks for confirmation first, then requests UAC elevation automatically if the Firefox directory is protected. If it works, the last line should be Done.
1. Run `clear-startup-cache.cmd --status` on Windows, or `clear-startup-cache.sh --status` from Bash, to see which Firefox profiles the helper detects.
1. Run `clear-startup-cache.cmd --dry-run` on Windows, or `clear-startup-cache.sh --dry-run` from Bash, to preview Firefox profile `startupCache` directories that will be cleared.
1. Run `clear-startup-cache.cmd` on Windows, or `clear-startup-cache.sh` from Bash, to remove those `startupCache` directories. On Windows, the launcher asks for confirmation before deleting cache folders. The helper uses Firefox `profiles.ini`; for an unusual profile location, pass `--profile /path/to/profile`. Windows paths such as `C:\Users\Name\AppData\Roaming\Mozilla\Firefox\Profiles\xxxxxxxx.default-release` are accepted by the `.cmd` launcher.
1. Start Firefox.
1. Navigate to `about:config`.
1. While on `about:config`, go to the Developer tools (F12 by default), and switch to the Console tab. Type in `ChromeUtils.importESModule("resource://gre/modules/AppConstants.sys.mjs").AppConstants.MOZ_REQUIRE_SIGNING`. If you see `false`, the patching has worked. If you see true, something has not worked. Older Firefox builds may require `ChromeUtils.import("resource://gre/modules/AppConstants.jsm").AppConstants.MOZ_REQUIRE_SIGNING` instead. If it did not work, ensure you have run the `patch-firefox.sh` script with the correct MOZILLA_HOME, and that you have successfully deleted the startupCache before starting Firefox, and try again.
1. In `about:config`, search for xpinstall.signatures.required, and change the value to false if it is true.
1. Copy your extension into the extensions subdirectory of your Firefox profile directory.
1. Restart Firefox. Firefox will prompt to confirm that you want to enable the addon.

# Upgrading Firefox

You should continue to upgrade Firefox whenever it prompts you to upgrade it to ensure you have the latest security patches. However, before applying upgrades, you should:

1. Exit from Firefox.
1. Run `unpatch-firefox.cmd --status --mozilla-home /path/to/firefox` on Windows, or `unpatch-firefox.sh --status --mozilla-home /path/to/firefox` from Bash, to confirm that the install is currently patched and has a rollback backup.
1. Run the same command with `--dry-run` to confirm that the backup can be staged for restore.
1. Run the restore command without `--status` or `--dry-run`. On Windows, the launcher asks for confirmation first, then requests UAC elevation automatically if the Firefox directory is protected.
1. Start Firefox using the `-ProfileManager` option, and start it using a different profile - create a new one if necessary (don't start it with your normal profile as this will disable all your unsigned addons, and you will need to clear caches again).
1. Apply the update.
1. Run `patch-firefox.sh`
1. Start Firefox again using your default profile.
