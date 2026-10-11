<#
.SYNOPSIS
  Trap 5: NativeCommandError with 2>&1 even though the program exited 0.
.DESCRIPTION
  In Windows PowerShell 5.1, 2>&1 on a native .exe wraps every stderr line in a
  NativeCommandError record and sets $? to $false, even when the program's own exit code
  is 0. This only shows up reliably when the CONTAINING script is itself invoked as a
  file (powershell.exe -File ...), not pasted at a prompt or run with -Command.
.NOTES
  Fieldpane - checks/05-stderr-redirect.ps1
  Must be run with: powershell.exe -File 05-stderr-redirect.ps1 (run-all.ps1 does this).
  Safe: read-only, spawns one child cmd.exe process, writes nothing to disk.
#>

$cmdOutput = cmd /c "echo warn 1>&2 & exit 0" 2>&1
$dollarQ = $?
$exitCode = $LASTEXITCODE

Write-Output "invoked as: $($MyInvocation.MyCommand.Path)"
Write-Output "`$? after the call: $dollarQ"
Write-Output "`$LASTEXITCODE after the call: $exitCode"

if ($dollarQ -eq $false -and $exitCode -eq 0) {
    Write-Output ""
    Write-Output "APPLIES: `$? is False while the real exit code is 0 - redirecting a native exe's stderr with 2>&1 is misleading here."
    Write-Output "DO: don't redirect stderr with 2>&1 on a native .exe in this PowerShell; check `$LASTEXITCODE instead of `$?."
} elseif ($dollarQ -eq $true -and $exitCode -eq 0) {
    Write-Output ""
    Write-Output "DOES NOT APPLY: `$? stayed True with exit code 0 on this host."
    Write-Output "DO: nothing here - re-test if PSVersionTable.PSVersion or PSEdition changes."
} else {
    Write-Output ""
    Write-Output "CANNOT TEST (unexpected combination: `$?=$dollarQ, exit=$exitCode - compare manually with the README)."
}
