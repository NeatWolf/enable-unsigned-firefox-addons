# Contributing

Keep this repository narrow and reversible.

- The patch script changes a local Firefox installation. Review path handling and rollback behavior before accepting script changes.
- Do not run patching commands against a normal browser install during routine verification.
- Prefer fixture-based or static checks for pull requests.
- Keep shell scripts compatible with Bash and common Unix command-line tools listed in `README.md`.
- Run `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1` before handing off changes.
- Keep pull requests about repo or script improvements, not support requests for a local Firefox install.
