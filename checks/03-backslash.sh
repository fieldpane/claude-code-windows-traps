#!/usr/bin/env bash
# Trap 3: every backslash count comes out as ceil(n/2) before the Bash tool's own shell
# ever sees them - a pair becomes one, four becomes two, six becomes three.
#
# This is NOT the ordinary bash behaviour where "\\x" inside DOUBLE quotes prints as
# "\x" - that collapse is normal double-quote escape processing in every bash, Windows
# or not (try `echo "\\x"` on Ubuntu; same result). The real, Windows-specific bug: when
# bash.exe gets its command as a -c ARGUMENT from a non-MSYS parent (PowerShell, cmd.exe,
# Node - which is how Claude Code's Bash tool launches it), Git Bash's MSYS2 runtime thins
# every run of backslashes in that argument down to ceil(n/2) before bash parses it - even
# inside SINGLE quotes and inside a quoted heredoc (<<'EOF'), where bash's own quoting
# would normally protect them completely. Measured 2026-10-11 from PowerShell 5.1, cmd.exe
# and Node spawnSync alike; MSYS=noglob stops it (evidence of the layer, not a fix to hand
# to an agent). See anthropics/claude-code#100063 and #93618 (both open as of 2026-10-10)
# and ../Test-ClaudeCodeWindows.ps1, which reproduces it without any agent.
#
# A second, related symptom: long commands can fail outright with "unexpected EOF while
# looking for matching ''" past a length threshold that depends on local paths (7822
# characters ran, 7872 did not, on the machine this was measured on 2026-10-11). This
# script does not test that part - see README.md section 3.
#
# This script proves the halving with single-quoted strings, which bash itself never
# touches: any change between "command run" and "printed" below did not come from bash.
#
# IMPORTANT: this script file must itself be created with the Write tool or a plain text
# editor - never with a Bash heredoc run through the Bash tool. A heredoc sent through
# that tool lands on disk already halved, which would corrupt the very backslashes this
# script exists to test (measured, not theoretical).
#
# Usage:
#   ./03-backslash.sh              printf test only, no network
#   ./03-backslash.sh SERVERNAME   also runs Test-NetConnection SERVERNAME -Port 445
#     (kept from the original UNC-path framing of this trap; a secondary check, not the
#     main point above)
#
# Fieldpane - checks/03-backslash.sh
# Safe: no file changes; network access only if you pass a server name.

set -u

SERVER="${1:-}"

# Single-quoted in bash = fully literal, no backslash processing by bash itself. Whatever
# comes out the other side either matches these literal strings, or something upstream of
# bash's own parsing altered them.
OUT=$(printf '%s|' 'one\x' 'two\\x' 'four\\\\x'; echo)
EXPECTED='one\x|two\\x|four\\\\x|'
HALVED='one\x|two\x|four\\x|'

echo 'command run:  printf '"'"'%s|'"'"' '"'"'one\x'"'"' '"'"'two\\x'"'"' '"'"'four\\\\x'"'"'; echo'
echo "printed:      $OUT"
echo "expected if nothing touched it: $EXPECTED"

if [ "$OUT" = "$EXPECTED" ]; then
  echo ""
  echo "PRESERVED in this shell - but this is the ONLY result this script, run as a file,"
  echo "can ever show you. A file's contents are never a command-line argument, so the"
  echo "MSYS2 parsing that halves backslashes never sees them - only an inline command does."
  echo "TO ACTUALLY TEST: run ../Test-ClaudeCodeWindows.ps1 from Windows PowerShell (it sends"
  echo "the same printf as a bash.exe -c argument), or ask your agent to run the 'command"
  echo "run:' line above typed inline through its own Bash tool - not this file."
  echo "HALVED there ($HALVED) means the trap applies."
elif [ "$OUT" = "$HALVED" ]; then
  echo ""
  echo "HALVED -> APPLIES: every backslash count above came back as ceil(n/2) - a pair"
  echo "became one, four became two - even though they were inside single quotes, and even"
  echo "though this ran as a script file (if you are seeing this, whatever ran this file is"
  echo "not an ordinary bash - say so when you report it). This is the signature of"
  echo "anthropics/claude-code#100063 / #93618 - the corruption happens before bash parses"
  echo "the command, so no amount of bash-side quoting fixes it. A related symptom: long"
  echo "commands can fail outright with \"unexpected EOF\" past a length threshold that"
  echo "depends on local paths (7822 chars ran, 7872 did not, measured here 2026-10-11) -"
  echo "see README.md section 3 for that part; this script does not test it."
  echo "DO: for backslash-heavy strings (UNC paths, regex, JSON escapes), use the"
  echo "PowerShell tool instead of the Bash tool, or write the content with the Write tool"
  echo "instead of a Bash heredoc (the workaround from #100063)."
else
  echo ""
  echo "CANNOT TEST (output matched neither the preserved nor the halved pattern - compare"
  echo "manually with the README)."
fi

if [ -n "$SERVER" ]; then
  echo ""
  echo "server check requested for: $SERVER"
  if command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -Command "Test-NetConnection '$SERVER' -Port 445" 2>&1
  else
    echo "CANNOT TEST (powershell.exe not found on PATH - cannot run Test-NetConnection)."
  fi
else
  echo ""
  echo "no server name given - skipping Test-NetConnection (pass a server name as the first argument for a UNC-path-specific network check)."
fi
