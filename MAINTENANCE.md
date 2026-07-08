# Maintenance Notes

This repository is maintained as-is.

Useful checks before changing scripts:

- Run `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1`.
- Use `--status` and `--dry-run` against a real Firefox install; do not run a real patch during routine maintenance.
- Keep Windows `.cmd` launchers standard and small.
- Keep Python optional; prefer Git Bash tools and PowerShell/.NET fallback on Windows.
- Keep script output direct enough for inexperienced users and clear enough for technical users.
- Update `CHANGELOG.md` when behavior visible to users changes.
- If the owner wants no support channel, disable Issues and Discussions in GitHub repository settings. Files in this repo can only set boundaries, not turn those features off.
