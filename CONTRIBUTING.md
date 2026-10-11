# Contributing

If a command in this repo disagrees with the text next to it, the text is wrong. Open an
issue with your exact output and these versions:

- Windows build: `[Environment]::OSVersion.Version`
- PowerShell edition and version: `$PSVersionTable`
- Git for Windows / Git Bash version: `git --version`, `bash --version`
- Claude Code version: `claude --version`

## What we accept

A new trap, only with all three of:

1. A command that reproduces the symptom - or shows that it does **not** reproduce on a
   given version. Negative results are useful too.
2. The date it was run, and the versions above.
3. The exact error text or symptom, as it appeared - not a paraphrase.

We don't accept a trap sourced from someone else's post without your own verification.
Every claim in this repo ships with a date and a command that re-checks it.

## What we don't accept

- Installation tutorials. They're free everywhere already, and stale within weeks.
- An undated "X doesn't work" claim with no command attached.
- Anything that needs `irm | iex`, elevated privileges, or network access beyond an
  explicit, opt-in `Test-NetConnection`.
