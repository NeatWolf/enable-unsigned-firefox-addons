# Agent Rules

## Operating Contract

- Read `README.md` before changing script behavior or documented workflows.
- Treat `patch-firefox.sh` and `unpatch-firefox.sh` as host-modifying scripts. Do not run them against a real Firefox install unless the user explicitly asks and provides the intended `MOZILLA_HOME`.
- Prefer static verification and disposable fixture checks before any live Firefox mutation.
- Keep the repository small: shell scripts, documentation, and lightweight verification only unless the user asks for a broader tool.

## Build And Verification

- Run `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1` after changes.
- If a working Bash is available, also run `bash -n patch-firefox.sh` and `bash -n unpatch-firefox.sh`.
- Treat Info-ZIP `zip` as the normal repacker. Python is only an optional fallback for machines that have it.
- When `unzip`, `mktemp`, `sed`, `grep`, and either `zip` or `python3`/`python` are available under Bash, run `scripts/verify-fixture.sh` instead of touching a real Firefox install.
- Keep `--dry-run` non-mutating for both patch and unpatch paths.
- Keep the Firefox-running guard enabled for real use; use `SKIP_FIREFOX_PROCESS_CHECK=1` only inside disposable verification fixtures or after explicit user direction.
- On Windows, `bash.exe` may resolve to WSL. If WSL cannot launch, report that Bash syntax verification was skipped or use a non-WSL Bash such as Git Bash.

## Script Safety

- Quote filesystem paths and variable expansions.
- Avoid deleting or overwriting files outside `MOZILLA_HOME` and the temporary working directory.
- Preserve `omni-orig.ja` as the rollback point and keep unpatch behavior simple.
- Do not add telemetry, networking, background services, or generated dependency trees.
