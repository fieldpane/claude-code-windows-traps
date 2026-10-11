<#
.SYNOPSIS
  Fieldpane - run all checks (traps 1-7) for Claude Code on Windows.
.DESCRIPTION
  Runs checks/01, 04, 05, 06, 07 with Windows PowerShell, and, if Git Bash can be found
  next to a working git.exe, checks/02 and checks/03 with that Git Bash. Traps 8-10 have
  no script (see README.md) - they need a running Office app, several parallel agents, or
  a specific Claude Code bug report, and are re-tested by hand.
.NOTES
  Fieldpane - checks/run-all.ps1
  Safe: only runs the checks above; see each check's own file for what it touches.
  Does not need -TaskName for 06; pass -TaskName <name> through to it directly if wanted.
#>
param(
    [string]$TaskName
)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Invoke-Check {
    param([string]$Label, [ScriptBlock]$Action)
    Write-Output ""
    Write-Output "==================== $Label ===================="
    try {
        & $Action
    } catch {
        Write-Output "CANNOT TEST (error running $Label`: $($_.Exception.Message))"
    }
}

Invoke-Check "01-bom.ps1" { powershell.exe -NoProfile -File (Join-Path $here '01-bom.ps1') }
Invoke-Check "04-and-and.ps1" { powershell.exe -NoProfile -File (Join-Path $here '04-and-and.ps1') }
Invoke-Check "05-stderr-redirect.ps1" { powershell.exe -NoProfile -File (Join-Path $here '05-stderr-redirect.ps1') }
if ($TaskName) {
    Invoke-Check "06-scheduled-task-idle.ps1" { powershell.exe -NoProfile -File (Join-Path $here '06-scheduled-task-idle.ps1') -TaskName $TaskName }
} else {
    Invoke-Check "06-scheduled-task-idle.ps1" { powershell.exe -NoProfile -File (Join-Path $here '06-scheduled-task-idle.ps1') }
}
Invoke-Check "07-which-shell.ps1" { powershell.exe -NoProfile -File (Join-Path $here '07-which-shell.ps1') }

# Find Git's own bash.exe next to a working git.exe - do not trust a bare "bash.exe" PATH
# lookup, because on many machines something earlier on PATH (often
# C:\Windows\System32\bash.exe, which launches WSL) wins over Git's own bash. See
# checks/07-which-shell.ps1 for the longer version of this check.
$gitBash = $null
$gitPath = (Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if ($gitPath) {
    # <root>\cmd\git.exe -> root is two levels up; <root>\mingw64\bin\git.exe (what PATH holds
    # when this runs from inside Git Bash) -> root is three levels up. Try both.
    $gitRoot = Split-Path (Split-Path $gitPath -Parent) -Parent
    foreach ($root in @($gitRoot, (Split-Path $gitRoot -Parent))) {
        if (-not $root) { continue }
        $candidate = Join-Path $root 'bin\bash.exe'
        if (-not $gitBash -and (Test-Path $candidate)) { $gitBash = $candidate }
    }
}

if ($gitBash) {
    Invoke-Check "02-nul.sh" { & $gitBash (Join-Path $here '02-nul.sh') }
    Invoke-Check "03-backslash.sh" { & $gitBash (Join-Path $here '03-backslash.sh') }
} else {
    Write-Output ""
    Write-Output "==================== 02-nul.sh / 03-backslash.sh ===================="
    Write-Output "CANNOT TEST (no Git Bash found next to git.exe - install Git for Windows, or run these two scripts by hand with your own Git Bash)."
}

Write-Output ""
Write-Output "==================== traps 8-10 ===================="
Write-Output "no script - re-test by hand (needs a running Office app, several parallel agents, or a Claude Code version check); see README.md."
