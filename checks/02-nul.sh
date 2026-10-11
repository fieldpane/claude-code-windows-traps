#!/usr/bin/env bash
# Trap 2: A file named "nul" appears and won't delete.
#
# In Git Bash, `> nul` and `2>nul` create a REAL file, because `nul` is only a reserved
# device name to native Windows tools, not to Git Bash's own redirection. Once it exists,
# `del nul` from cmd.exe fails and PowerShell's `Test-Path` reports False, because those
# tools treat the name as the reserved device, not as a file.
#
# This check creates and removes a `nul` file with Git Bash's own `rm`, strictly under
# $TEMP (never inside a cloud-sync client's folder - such clients can choke on a file
# called nul).
#
# Fieldpane - checks/02-nul.sh
# Safe: only creates and deletes files under $TEMP/fieldpane-check-02.

set -u

TEMP_WIN="${TEMP:-${TMP:-}}"
if [ -z "$TEMP_WIN" ]; then
  echo "CANNOT TEST (no TEMP or TMP environment variable found)."
  exit 1
fi

WORK="$(cygpath -u "$TEMP_WIN" 2>/dev/null)/fieldpane-check-02"
if [ -z "$WORK" ] || [ "$WORK" = "/fieldpane-check-02" ]; then
  echo "CANNOT TEST (cygpath could not resolve TEMP)."
  exit 1
fi

rm -rf "$WORK" 2>/dev/null
mkdir -p "$WORK"
cd "$WORK" || { echo "CANNOT TEST (could not create or enter $WORK)."; exit 1; }

echo "working folder: $WORK"

echo hi > nul 2>/dev/null
CREATE_RESULT=$?

if [ -e nul ]; then
  SIZE=$(wc -c < nul 2>/dev/null | tr -d ' ')
  echo "a file named 'nul' was created (size: ${SIZE:-?} bytes, redirect exit code: $CREATE_RESULT)"
  rm -f nul
  if [ -e nul ]; then
    echo "CANNOT TEST (Git Bash's own rm could not remove the nul file - clean it up by hand in $WORK)."
  else
    echo "APPLIES: 'echo hi > nul' in Git Bash created a real file called nul; Git Bash's own 'rm nul' deleted it."
    echo "DO: tell your agent to redirect to /dev/null, not nul, in any command Git Bash runs."
  fi
else
  echo "DOES NOT APPLY: no file named nul was created by this shell on this machine."
  echo "DO: nothing here - re-test if you change Git for Windows version."
fi

cd / >/dev/null 2>&1 || true
rm -rf "$WORK" 2>/dev/null
