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
- GitHub Actions is currently parked at `.github/workflows-disabled/verify.yml`; move it back to `.github/workflows/verify.yml` only when hosted Actions can run again.
- Dependabot for GitHub Actions is currently parked at `.github/dependabot-disabled.yml` for the same reason.

## GitHub Presentation

- About description: `Patch local Firefox installs to allow unsigned add-ons. Provided as-is.`
- Topics: `firefox`, `addons`, `webextensions`, `unsigned-addons`, `bash`, `windows`, `git-bash`
- Disable Issues and Discussions if no support channel is desired.
- Upload `assets/github-social-preview.svg` as the social preview.
