# Support

This project is provided as-is.

There is no support commitment, no help desk, no compatibility guarantee for
future Firefox releases, and no promise that unsigned add-ons will keep working
in Firefox Release builds.

Before using the scripts, read the README and run the safe checks first. On
Windows, run `patch-firefox.cmd --status` and `patch-firefox.cmd --dry-run`.
From Bash, run `patch-firefox.sh --status` and `patch-firefox.sh --dry-run`.
Run the startup-cache helper with `--status` and `--dry-run` before clearing
Firefox profile caches.

Keep your own recoverable backup of the Firefox install. If Firefox changes or
something breaks, restore from your own backup, run `unpatch-firefox` if the
rollback backup is available, or reinstall Firefox.

Python is optional. Administrator permission is not required for `--status` or
`--dry-run`; real patch and restore commands may request UAC only when the
Firefox install is protected. You can also pass a writable Firefox install path.
