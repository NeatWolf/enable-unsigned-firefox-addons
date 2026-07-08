# Changelog

## Unreleased

- Added safer Windows launchers with confirmation prompts for file-changing actions.
- Added status and dry-run checks for patching, restoring, and startup-cache cleanup.
- Hardened `omni.ja` patching with rollback backups, verified replacement archives, and temporary-file cleanup.
- Supported modern `AppConstants.sys.mjs` and legacy `AppConstants.jsm` layouts.
- Added PowerShell/.NET archive rebuilding on Windows when Info-ZIP `zip` is unavailable.
- Added repository verification, disposable fixture tests, and GitHub metadata for as-is maintenance.
