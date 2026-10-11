<#
.SYNOPSIS
  Trap 4: The token '&&' is not a valid statement separator in this version.
.DESCRIPTION
  Windows PowerShell 5.1 has no &&, ||, ??, or ?:. This check runs a trivial && chain in
  a fresh powershell.exe process and reports whether it errors.
.NOTES
  Fieldpane - checks/04-and-and.ps1
  Safe: read-only, spawns one child powershell.exe process, writes nothing to disk.
#>

$ErrorActionPreference = 'Continue'

Write-Output "PSEdition on this host: $($PSVersionTable.PSEdition)"
Write-Output "PSVersion on this host: $($PSVersionTable.PSVersion)"

$result = & powershell.exe -NoProfile -Command 'Write-Output a && Write-Output b' 2>&1
$asText = ($result | Out-String).Trim()
$relevantLine = ($asText -split "`r?`n" | Select-String 'not a valid statement separator' | Select-Object -First 1)

if ($relevantLine) {
    Write-Output "relevant line from the error (not the full error record - that also names the script path):"
    Write-Output $relevantLine.Line.Trim()
} else {
    Write-Output "output from 'Write-Output a && Write-Output b':"
    Write-Output $asText
}

if ($relevantLine -or $asText -match "'&&'") {
    Write-Output ""
    Write-Output "APPLIES: this PowerShell rejects '&&' as a statement separator."
    Write-Output "DO: chain commands as 'A; if (`$?) { B }' and tell your agent this is Windows PowerShell 5.1, not PowerShell 7."
} elseif ($asText -match '(?s)a.*b') {
    Write-Output ""
    Write-Output "DOES NOT APPLY: '&&' worked - this host is running PowerShell 7+ (PSEdition Core), not Windows PowerShell 5.1."
    Write-Output "DO: nothing for this check; confirm with `$PSVersionTable.PSVersion` which PowerShell your agent will actually launch."
} else {
    Write-Output ""
    Write-Output "CANNOT TEST (unexpected output - compare manually with the README)."
}
