# Support

This project is provided as-is.

There is no support commitment, no compatibility guarantee for future Firefox
releases, and no promise that unsigned add-ons will keep working in Firefox
Release builds.

Before using the scripts, read the README. On Windows, run
`patch-firefox.cmd --status` and `patch-firefox.cmd --dry-run`. From Bash, run
`patch-firefox.sh --status` and `patch-firefox.sh --dry-run`. Keep your own
recoverable backup of the Firefox install or be ready to reinstall Firefox. On
Windows, real patch and restore commands may request UAC elevation only when the
Firefox install is not writable. Run `clear-startup-cache.cmd --dry-run` or
`clear-startup-cache.sh --dry-run` before clearing Firefox profile caches.
