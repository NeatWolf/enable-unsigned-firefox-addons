# Changelog

## Unreleased

- Added safer Windows launchers with confirmation prompts for file-changing actions.
- Added status and dry-run checks for patching, restoring, and startup-cache cleanup.
- Added status output for Firefox install write access before real patch or restore commands.
- Added patch status output for the archive repacker that would rebuild `omni.ja`.
- Improved path error messages for Firefox install and profile paths.
- Added next-step status hints for patch, restore, and running-Firefox states.
- Added startupCache status counts and next-step hints.
- Added dry-run success hints that point to the matching real command.
- Hardened `omni.ja` patching with rollback backups, verified replacement archives, and temporary-file cleanup.
- Supported modern `AppConstants.sys.mjs` and legacy `AppConstants.jsm` layouts.
- Added PowerShell/.NET archive rebuilding on Windows when Info-ZIP `zip` is unavailable.
- Added repository verification, disposable fixture tests, and GitHub metadata for as-is maintenance.
- Added maintenance notes for small, readable, verified script changes.
