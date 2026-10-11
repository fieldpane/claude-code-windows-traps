# Claude Code on Windows: 10 traps

Ten specific ways Claude Code (or any AI coding agent) on native Windows reports success
while something is actually wrong. Every trap has a command you can run on your own
machine. If a command disagrees with the text next to it, the text is wrong - trust your
machine, not this file.

Tested 2026-10-10 on Windows 11, Windows PowerShell 5.1, Git Bash 5.3, Claude Code 2.1.278.
Traps 6 and 08-10 are marked `re-test, from field notes` below: their causal story comes
from field notes and was not re-run on that date (trap 6's default-setting measurement was
re-run; the kill itself was not).

**Run the checks:** [`checks/`](checks/) has a runnable script for traps 1-7 - download or
clone the repo, then run:

```powershell
Get-ChildItem checks -Recurse | Unblock-File
powershell.exe -NoProfile -ExecutionPolicy Bypass -File checks\run-all.ps1
```

The `Unblock-File` step only matters if you got these files as a ZIP download - Windows
marks downloaded files as coming from the internet, and Windows PowerShell can refuse to
run a blocked script even when the command above looks identical to one that works on a
cloned copy. `-ExecutionPolicy Bypass` is a per-process flag, not a system change: it
affects only this one `powershell.exe` run, including every nested `powershell.exe -File`
call `run-all.ps1` makes (they inherit it through the `PSExecutionPolicyPreference`
variable, not by re-reading your machine's policy). Traps 8-10 need a running Office app,
several parallel agents, or a specific Claude Code version, so they stay as manual steps
in this file.

Fieldpane is an independent product, not affiliated with or endorsed by Anthropic.

---

## 1. Script says "OK", exit code 0, and the file isn't there

**Symptom.** A `.ps1` script runs, prints success, exits 0 - and the file it says it wrote
or read is not there, or a different file is.

**Cause.** Windows PowerShell 5.1 reads a UTF-8 `.ps1` file *without* a byte-order mark
(BOM) as if it were the system's ANSI codepage, not UTF-8. A non-ASCII character typed
anywhere in that script - including inside a string that becomes part of a file name - is
then misread. The script still "succeeds"; it just does not do what its own source text
says.

**Fix.** Save `.ps1` files with a UTF-8 BOM. If you can't control how the file is saved,
send the command inline instead of with `-File`, or keep non-ASCII characters out of any
path the script touches.

**Verify.**

```powershell
$f = "$env:TEMP\t.ps1"
[IO.File]::WriteAllText($f, "Write-Output 'café'", (New-Object Text.UTF8Encoding $false))
powershell.exe -File $f
```

Garbled output (anything other than a clean `café` - on a Czech codepage it comes back as
`cafĂ©`, on a Western one as `cafÃ©`) means the trap applies on your machine. Re-run with `(New-Object Text.UTF8Encoding $true)` to see the file with a BOM
come back clean. Runnable version: [`checks/01-bom.ps1`](checks/01-bom.ps1).

---

## 2. A file named "nul" appears and won't delete

**Symptom.** A file literally called `nul` shows up in a folder. `del nul` from `cmd.exe`
refuses to touch it. PowerShell's `Test-Path` on it reports `False` even though Explorer
shows the file sitting right there.

**Cause.** `nul` is a reserved device name to native Windows tools (`cmd.exe`,
`Remove-Item`, `Test-Path`), but not to Git Bash's own redirection. A command like `> nul`
or `2>nul` run from Git Bash creates a real file named `nul` on disk - something
Windows-native tools then refuse to address by that name.

**Fix.** Delete it from Git Bash itself with `rm nul`. Tell your agent to redirect to
`/dev/null`, never `nul`, in anything that runs through Bash. Without Git Bash on the
machine at all, `Remove-Item` and `del` still refuse the reserved name even though
`Get-ChildItem` shows the file sitting right there - prefix the full path with `\\?\` to
bypass Windows' own name parsing and let .NET delete it directly:

```powershell
[System.IO.File]::Delete("\\?\$fullPathToNul")
```

**Verify** (run from Git Bash, outside any cloud-sync client's folder):

```bash
cd "$TEMP" && mkdir -p nultest && cd nultest && echo hi > nul && ls -la && rm nul
```

If `ls -la` shows a file called `nul`, the trap applies. Runnable version:
[`checks/02-nul.sh`](checks/02-nul.sh) (creates and deletes its own file under `$TEMP`
only).

---

## 3. Backslashes come out halved - and long commands die with "unexpected EOF"

**Symptom.** Send a command through the Bash tool with one to six backslashes - `\`, `\\`,
`\\\`, `\\\\`, `\\\\\`, `\\\\\\` - and count what arrives on the other side: 1, 1, 2, 2, 3,
3, exactly `ceil(n/2)`. Measured 2026-10-11 on this machine. It happens inside single quotes
and inside a quoted heredoc (`<<'EOF'`) too, where bash's own quoting would normally protect
them completely. No error, exit code 0. In practice: a JSON string such as
`'{"p":"C:\\\\x"}'`, decoded with Python on the other end, comes back as `C:\x` - the
command text asked for `C:\\x`.

A second symptom shows up only on long commands: past some length, the command does not run
at all. The shell reports ``unexpected EOF while looking for matching `''` ``, exit code 2 -
and that stray quote is not anywhere in the text you actually wrote.

**Cause.** The Bash tool wraps every command in its own shell before running it, roughly:
`source '<snapshot>' ... && export TEMP TMP && shopt -u extglob ... && { \builtin unalias
... } ... && eval '<command>' < /dev/null && pwd -P >| '<temp>/claude-...-cwd'`. On this
machine that wrapper is 436 characters - the number depends on local paths, so yours will
differ. A command of 7,822 characters ran; one of 7,872 characters did not. The cut lands at
the end of the combined string, inside the wrapper's own closing quote around `eval '...'` -
so the `unexpected EOF` is complaining about a quote that belongs to the wrapper, not to
anything in the command.

The layer that halves is Git Bash's own runtime (MSYS2, a Cygwin fork) parsing a `-c`
argument that arrives from a non-MSYS parent. Measured 2026-10-11: the same `printf` sent as
`bash.exe -c` from Windows PowerShell 5.1, from `cmd.exe` and from Node's `spawnSync` came
back halved in all three, while the Windows command line read back with
`Get-CimInstance Win32_Process` still held every backslash; with `MSYS=noglob` in the
environment all three came back intact. Cygwin's documentation for its `glob` option (MSYS2
reads the same options from `MSYS` instead of `CYGWIN`) says it applies "only to programs
run from non-Cygwin programs such as a CMD prompt" and lists wildcards "escaped with `\`"
among what it processes - that this glob step is the halving is an inference from those
runs, not a sentence in the documentation. The oldest open report,
[#85856](https://github.com/anthropics/claude-code/issues/85856) (opened 2026-08-11),
attributes it to "MSVCRT vs MSYS2" command-line parsing - the MSYS2 half matches this
measurement; the MSVCRT and libuv sources only describe backslashes directly before a double
quote. Claude Code's Bash tool launches Git Bash from Node with the wrapped command as one
`-c` argument - the same path by inference; the tool itself was not instrumented. A file run
with `bash file.sh` is untouched because its contents are not a command-line argument.

Tracked upstream, all still open and with no reply from Anthropic as of 2026-10-10 (seven
here; the eighth, [#88578](https://github.com/anthropics/claude-code/issues/88578), is the UNC
report at the end of this section):
[#85856](https://github.com/anthropics/claude-code/issues/85856),
[#89392](https://github.com/anthropics/claude-code/issues/89392),
[#90630](https://github.com/anthropics/claude-code/issues/90630),
[#93618](https://github.com/anthropics/claude-code/issues/93618),
[#93915](https://github.com/anthropics/claude-code/issues/93915),
[#100063](https://github.com/anthropics/claude-code/issues/100063), and
[#100349](https://github.com/anthropics/claude-code/issues/100349). No fix for any of them
appears in the CHANGELOG through version 2.1.296.

**Fix.**

- Write the file with the Write tool, not a Bash heredoc, then run it with `bash file.sh`.
  A heredoc sent through the Bash tool lands on disk already halved - measured, not
  theoretical.
- Use the PowerShell tool instead of the Bash tool. Not affected - measured on this
  machine.
- For a long command, put it in a file first rather than relying on the length threshold;
  the threshold moves with your own paths.
- Workarounds mentioned in the open issues (a pre-processing hook, `bash -s`) are reported
  by other users, not tested here.
- `MSYS=noglob` is evidence, not a workaround: it stopped the halving in every direct
  `bash.exe -c` spawn measured here, but set on the whole Claude Code process it changed how
  a hook command containing double quotes was split and that hook failed with a syntax error
  before any tool ran (one attempt, 2026-10-11).

**Verify.** Three steps - the halving happens only when bash.exe gets the command as a
`-c` argument from a Windows process, so where you type matters:

```powershell
& "C:\Program Files\Git\bin\bash.exe" -c "printf '%s|' 'n2=\\x' 'n4=\\\\x'; echo"
```

0. Run that from Windows PowerShell, no agent involved. Here it printed `n2=\x|n4=\\x|` -
   halved. Runnable version: [`Test-ClaudeCodeWindows.ps1`](Test-ClaudeCodeWindows.ps1)
   (traps 2, 3 and 4 in one file, nothing outside `%TEMP%`).

```bash
printf '%s|' 'one\x' 'two\\x' 'four\\\\x'; echo
```

1. Type that at a Git Bash prompt. Expect `one\x|two\\x|four\\\\x|` - typed at the prompt
   it is never a command-line argument, and bash's single quotes are fully literal.
2. Ask your agent to run the exact same line through its own Bash tool - typed inline, not
   saved to a script first (see why below). Expect `one\x|two\x|four\\x|` - every count of
   backslashes rounded to `ceil(n/2)`: 1 stays 1, 2 stays 1, 4 becomes 2. That mismatch
   against step 1 is the trap.

Also check the wrapper directly, inline, through the same tool:

```bash
echo ${#BASH_EXECUTION_STRING}; echo "${BASH_EXECUTION_STRING:0:120}"
```

This prints the length of the whole wrapped command and its first 120 characters, so you
see the wrapper around your own text instead of guessing at it.

To find your own machine's length threshold, grow a command and watch for `unexpected
EOF`. The padding has to be digits sitting in the command's own text - for example a
comment with a counted number of `#` characters - not something generated at run time such
as `$(printf ...)`, which would change the wrapped string's length along with the payload
and defeat the measurement.

Runnable version: [`checks/03-backslash.sh`](checks/03-backslash.sh) reproduces step 1 and
tells you what to compare it to - but asking an agent to run the script file itself through
its Bash tool only ever reproduces step 1's clean result, even on an affected machine,
because a file's contents are never a command-line argument, so the MSYS2 parsing that
halves never sees them; only an inline command does. Saving a reproduction to a script and having the
agent run the script is not a valid test for this specific bug - pass a server name as the
script's first argument to also run an optional `Test-NetConnection` check; with no argument
it only prints the printf comparison, no network access at all. The script file itself must
be created with the Write tool or a plain editor, never a Bash heredoc - a heredoc would
corrupt the very backslashes the script exists to test.

Reported but not independently tested here: a UNC path such as `\\SERVER\share` losing one
of its two leading backslashes the same way
([#88578](https://github.com/anthropics/claude-code/issues/88578)).

---

## 4. `The token '&&' is not a valid statement separator in this version.`

**Symptom.** A command chained with `&&` fails immediately with that exact parser error.

**Cause.** Windows PowerShell 5.1 has no `&&`, `||`, `??`, or `?:` - those were added in
PowerShell 7. An agent that was taught to chain commands with `&&` (common on macOS/Linux,
and in PowerShell 7 itself) breaks the moment it runs under Windows PowerShell 5.1.

**Fix.** Chain commands as `A; if ($?) { B }` instead, and tell your agent explicitly
which PowerShell it is talking to.

**Verify.**

```powershell
powershell.exe -NoProfile -Command 'Write-Output a && Write-Output b'
```

That exact error means the trap applies. Also check which PowerShell you're actually on:

```powershell
$PSVersionTable.PSVersion
```

Runnable version: [`checks/04-and-and.ps1`](checks/04-and-and.ps1).

---

## 5. `NativeCommandError` with `2>&1` even though the program exited 0

**Symptom.** A native `.exe` finishes fine - its own exit code is 0 - but PowerShell
reports the command failed, and `$?` comes back `False`.

**Cause.** In Windows PowerShell 5.1, redirecting a native executable's stderr with
`2>&1` wraps every line it wrote to stderr in a `NativeCommandError` record and sets `$?`
to `False`, regardless of the program's real exit code. This only shows up reliably when
the *containing* script is itself run as a file (`powershell.exe -File ...`), not pasted
at an interactive prompt.

**Fix.** Don't redirect a native `.exe`'s stderr with `2>&1` in Windows PowerShell. Check
`$LASTEXITCODE`, not `$?`, for the program's real result.

**Verify.** Save as `t.ps1`:

```powershell
cmd /c "echo warn 1>&2 & exit 0" 2>&1
"$? / $LASTEXITCODE"
```

Run it with `powershell.exe -File t.ps1` (not pasted into a live prompt). Expect
`False / 0` - that mismatch is the trap. Runnable version:
[`checks/05-stderr-redirect.ps1`](checks/05-stderr-redirect.ps1), which must be run with
`-File` for the same reason (`run-all.ps1` does this for you).

---

## 6. Scheduled task exit code `3221225786` (`0xC000013A`) `re-test, from field notes`

**Symptom.** A task you put in Task Scheduler for an agent to run unattended dies within
seconds, every time, with exit code `3221225786` (hex `0xC000013A` - the code Windows uses
for "application terminated by Ctrl+C / console session ending").

**Cause.** Two separate claims here, checked to different degrees. New Task Scheduler
tasks do default to "stop if the computer stops being idle" turned **on**, even when "run
only if idle" is turned off - that default value is directly measured, below, by
`checks/06-scheduled-task-idle.ps1`. The causal story - that the moment the machine is
touched (mouse, keyboard, a foreground window) a task running under that default gets
killed mid-run with this exact exit code - comes from field notes and was **not**
reproduced on 2026-10-10. `checks/06-scheduled-task-idle.ps1` stays a read-only check of
the default setting only; it does not create or run a task to test the kill itself.

**Fix** (from the same field notes, also not re-verified on 2026-10-10). Turn
`StopOnIdleEnd` off for the specific task.

**Verify.**

```powershell
(New-ScheduledTaskSettingsSet).IdleSettings.StopOnIdleEnd
```

`True` means the default is on on your machine. To fix an existing task:

```powershell
$s = (Get-ScheduledTask -TaskName X).Settings
$s.IdleSettings.StopOnIdleEnd = $false
Set-ScheduledTask -TaskName X -Settings $s
```

Runnable version: [`checks/06-scheduled-task-idle.ps1`](checks/06-scheduled-task-idle.ps1)
- read-only, changes nothing; pass `-TaskName <name>` to also read one specific task.

---

## 7. Which shell is Claude Code using on Windows?

**Symptom.** The same project folder has at least three different valid path spellings
(`C:\Users\...`, `/c/Users/...`, `/mnt/c/Users/...`) depending on which shell is actually
running a given command, and it is not always obvious which one that is.

**Cause.** If Git for Windows is not installed, Claude Code falls back to PowerShell as
its shell tool; a WSL-based setup does not need Git for Windows at all. Separately, a bare
`bash.exe` on `PATH` does not reliably mean Git Bash - on a machine with WSL installed,
`C:\Windows\System32\bash.exe` (a launcher that hands off to WSL) can sit earlier on
`PATH` than Git's own `bash.exe`, so "run it in bash" can quietly mean two different
shells depending on *how* bash was invoked.

**Fix.** Pick one shell per project and write it down. Don't assume `bash.exe` means Git
Bash - check where it actually resolves to.

This can also be pinned down with settings instead of just inferred. From the official
docs (<https://code.claude.com/docs/en/setup>, fetched 2026-10-10), quoted verbatim:

> Without Git for Windows, Claude Code runs shell commands via the PowerShell tool.
>
> With Git for Windows, Claude Code uses Git Bash for the Bash tool. If Claude Code can't
> find Git Bash, set the path in your settings.json file:
>
> ```
> {
>     "env": {
>       "CLAUDE_CODE_GIT_BASH_PATH": "C:\\Program Files\\Git\\bin\\bash.exe"
>     }
> }
> ```
>
> When Git for Windows is installed, the PowerShell tool is available alongside Bash: on
> by default for claude.ai and Console accounts, and enabled with
> `CLAUDE_CODE_USE_POWERSHELL_TOOL=1` in Amazon Bedrock, Google Cloud's Agent Platform,
> and Microsoft Foundry sessions. Set it to `0` to turn the tool off.

So `CLAUDE_CODE_GIT_BASH_PATH` is the documented way to point Claude Code at one specific
`bash.exe` instead of letting it search PATH - useful exactly when, as above, more than
one program named `bash.exe` is reachable on the same machine.

**Verify.**

```powershell
git --version
$PSVersionTable.PSEdition      # Desktop = Windows PowerShell 5.1
```

```bash
uname -o                        # Msys = Git Bash
```

```powershell
wsl -e uname -o                 # GNU/Linux = WSL's own bash
claude --version
```

Runnable version: [`checks/07-which-shell.ps1`](checks/07-which-shell.ps1) - read-only,
also checks whether plain `bash.exe` on `PATH` actually resolves to Git Bash or to
something else, with a 5-second timeout on the WSL check so it can't hang.

---

## 8. Automating Word or Excel closes the document you had open `re-test, from field notes`

**Symptom.** A script automates Word or Excel through COM. A document you had open -
unrelated to the script - closes.

**Cause.** COM's `Dispatch` can attach to an *already running* Office instance instead of
starting a new, invisible one. If the script then calls `Quit()` on that instance, it
closes whatever that instance had open - including your own work.

**Fix.** Check what's already running before automating Office. If something is, close
only the documents your own script opened, and never call `Quit()` on an instance you did
not start yourself.

**Verify.**

```powershell
Get-Process WINWORD,EXCEL -ErrorAction SilentlyContinue
```

Any result means Office is already running - treat that session as someone else's and
don't `Quit()` it. No script in this repo automates Office; there is nothing to run under
`checks/` for this one.

---

## 9. Running several Claude Code agents in parallel crashes the machine `re-test, from field notes`

**Symptom.** Running several agent sessions at once - especially ones doing heavy work
like video or image rendering - makes the whole machine slow to a crawl or crash outright.

**Cause.** Each concurrent agent is a real OS process with its own real memory footprint.
On a laptop-class machine, several of those at once - particularly ones calling out to
media tools - can exhaust available RAM. That looks like "Claude Code crashed"; it is
usually just the machine running out of memory.

**Fix.** Keep heavy, parallel work to one or two agents at a time until you've measured
your own machine's actual limit. Light, read-only agents can run in higher numbers safely.

**Verify.**

```powershell
Get-Process | Group-Object ProcessName | Sort-Object { ($_.Group | Measure-Object WS -Sum).Sum } -Descending | Select-Object -First 10 Name,@{n='MB';e={[math]::Round((($_.Group|Measure-Object WS -Sum).Sum)/1MB)}}
```

Watch this while you add agents one at a time; there is no safe-for-everyone number, so
this is not shipped as a pass/fail script under `checks/`.

---

## 10. Permission prompt on `cd folder && command` in Claude Code `re-test, from field notes`

**Symptom.** Claude Code asks for permission on a command you already allow-listed,
specifically when it is chained after a `cd`.

**Cause.** Open reports describe permission prompts firing on the `cd` itself instead of
the actual command that follows it (anthropics/claude-code #28240), and on absolute `cd`
targets when a matching Read deny rule exists (#91650); both were still open on 2026-10-10. This did not reproduce on 2.1.278 with a plain allow rule on the machine this
checklist was tested on - check your own version before changing any habits around it.

**Fix.** If you hit it: use an absolute path, or the tool's own directory flag instead of
`cd` (for git, `git -C <path>`), rather than reworking your permission rules.

**Verify.**

```powershell
claude --version
```

Then try `cd sub && <allowed command>` for yourself. A prompt where you don't expect one
is the trap; whether it reproduces depends on your Claude Code version and your exact
permission rules, so this stays a manual check rather than a script under `checks/`.

---

**The rule behind all ten:** never write "X doesn't work." Write "as of DATE, X failed,
and here is the command that re-checks it in thirty seconds." Tools change every few
weeks; an undated claim turns into folklore.

Printable version (PDF, free): https://fieldpane.gumroad.com/l/checklist

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to add a trap or report one that no longer
reproduces.

License: text under CC BY 4.0, scripts under MIT - see [LICENSE](LICENSE).

---

Claude and Claude Code are trademarks of Anthropic, PBC.
