# Findings

## Windows `choice` Can Trigger System Beeps

Observed on Windows while testing the menu scripts.

- Source: the built-in Windows `choice` command, not an explicit beep command in this repository.
- Trigger: invalid input, empty input, or piped input that leaves extra characters/newlines for `choice` to consume.
- User impact: the menu can feel like it is sending unexplained system beep signals.
- Repro helper: `scripts\debug-choice-beep.cmd`.
- Current implication: any normal menu path using `choice` may beep if the user presses an unexpected key or Enter.
- Mitigation: normal user-facing Windows prompts now use `scripts\read-choice.ps1`, a small PowerShell `ReadKey` helper that silently ignores invalid keys.
- Remaining `choice` use: `scripts\debug-choice-beep.cmd` intentionally keeps `choice` as a debug-only repro helper.
