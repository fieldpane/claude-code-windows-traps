<#
.SYNOPSIS
  Fieldpane - one-file diagnostic for three Windows traps that make an AI coding agent
  report success while something is wrong: trap 2 (a real file named "nul"), trap 3
  (backslashes halved by the agent's Bash tool), trap 4 ("&&" rejected by Windows
  PowerShell 5.1).

.DESCRIPTION
  Runs from Windows PowerShell 5.1 (and PowerShell 7). From Git Bash, run it as:
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File Test-ClaudeCodeWindows.ps1
  No dependency on the checks\ folder. Touches nothing outside %TEMP% (trap 2 creates and
  deletes one file under %TEMP%\fieldpane-selftest). No network. No system settings.

  Trap 3 is reproduced by launching bash.exe -c from this PowerShell process: Git Bash's
  MSYS2 runtime rewrites backslashes in a -c argument that arrives from a non-MSYS parent
  (PowerShell, cmd.exe, Node - the path an agent's Bash tool uses). A script FILE run by
  bash never shows it, so do not test this by asking an agent to run this file.

.PARAMETER AgentOutput
  Optional: the exact line your agent's Bash tool printed for the trap-3 command (copy/
  paste), shown next to this script's own result for comparison.

.PARAMETER Json
  Print one JSON object with the three verdicts instead of the text report.

.OUTPUTS
  Text report, one block per trap, each ending in a verdict line:
    APPLIES / DOES NOT APPLY / CANNOT TEST
  Exit code: 0 = every check produced a verdict (APPLIES counts as a successful test),
             1 = at least one check could not run (CANNOT TEST),
             2 = this script itself failed before finishing.

.NOTES
  Fieldpane - Test-ClaudeCodeWindows.ps1. Measured 2026-10-11 on Windows 11, Windows
  PowerShell 5.1.26100.9444, Git Bash 5.3.15, Claude Code 2.1.278 - one machine, not a
  survey. If a verdict here disagrees with what you see, trust your machine.
  ASCII only on purpose: Windows PowerShell reads a BOM-less file as ANSI (trap 1).
#>
[CmdletBinding()]
param(
    [string]$AgentOutput,
    [switch]$Json
)

$ErrorActionPreference = 'Continue'
$verdicts = [ordered]@{}
$lines = New-Object System.Collections.Generic.List[string]

function Say([string]$text) { $script:lines.Add($text) }
function Head([string]$title) { Say ''; Say ('==================== ' + $title + ' ====================') }

# --- locate Git's own bash.exe next to git.exe (a bare "bash.exe" on PATH is often WSL) ---
function Find-GitBash {
    $git = Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($git) {
        $root = Split-Path (Split-Path $git.Source -Parent) -Parent
        foreach ($rel in @('bin\bash.exe', 'usr\bin\bash.exe')) {
            $p = Join-Path $root $rel
            if (Test-Path -LiteralPath $p) { return $p }
        }
    }
    foreach ($p in @("$env:ProgramFiles\Git\bin\bash.exe", "${env:ProgramFiles(x86)}\Git\bin\bash.exe", "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe")) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    return $null
}

try {
    Say ('Test-ClaudeCodeWindows.ps1  ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'))
    Say ('PowerShell: ' + $PSVersionTable.PSVersion + ' (' + $PSVersionTable.PSEdition + ')  OS: ' + [Environment]::OSVersion.VersionString)
    $gitBash = Find-GitBash
    if ($gitBash) { Say ('Git Bash: ' + $gitBash) } else { Say 'Git Bash: not found next to git.exe' }

    # ================= trap 4: '&&' in Windows PowerShell 5.1 =================
    Head "trap 4 - The token '&&' is not a valid statement separator"
    $t4 = & powershell.exe -NoProfile -Command 'Write-Output a && Write-Output b' 2>&1
    $t4text = ($t4 | Out-String).Trim()
    if ($t4text -match 'not a valid statement separator') {
        Say "powershell.exe -Command 'Write-Output a && Write-Output b' -> parser error"
        Say ('  ' + (($t4text -split "`r?`n" | Select-String 'not a valid statement separator' | Select-Object -First 1).Line.Trim()))
        Say "APPLIES: the PowerShell your agent launches by default rejects '&&'."
        Say "DO: chain as 'A; if (`$?) { B }' and tell the agent this is Windows PowerShell 5.1, not PowerShell 7."
        $verdicts['trap4_and_and'] = 'APPLIES'
    } elseif ($t4text -match '(?s)\ba\s+b\b') {
        Say "'&&' ran: output was 'a' then 'b'."
        Say 'DOES NOT APPLY: the powershell.exe this script launched accepted "&&" (normally only pwsh.exe, PowerShell 7+, does). Check which executable your agent actually starts.'
        $verdicts['trap4_and_and'] = 'DOES NOT APPLY'
    } else {
        Say ('unexpected output: ' + $t4text)
        Say 'CANNOT TEST (output matched neither pattern).'
        $verdicts['trap4_and_and'] = 'CANNOT TEST'
    }

    # ================= trap 2: a real file named nul =================
    Head 'trap 2 - Git Bash creates a real file named "nul" that Windows tools cannot delete'
    if (-not $gitBash) {
        Say 'CANNOT TEST (no Git Bash found - install Git for Windows; the trap only exists through Git Bash redirection).'
        $verdicts['trap2_nul'] = 'CANNOT TEST'
    } else {
        $work = Join-Path $env:TEMP 'fieldpane-selftest'
        New-Item -ItemType Directory -Force -Path $work | Out-Null
        $workBash = (& $gitBash -c "cygpath -u '$($work -replace '\\','/')'" 2>$null | Out-String).Trim()
        if (-not $workBash) { $workBash = '/tmp/fieldpane-selftest' }
        $bashCmd = "cd '$workBash' && echo hi > nul; if [ -e nul ]; then echo CREATED; rm -f nul; if [ -e nul ]; then echo STUCK; else echo REMOVED; fi; else echo NOTCREATED; fi"
        $t2 = (& $gitBash -c $bashCmd 2>&1 | Out-String).Trim()
        Say ("Git Bash ran: echo hi > nul   (inside $work)")
        Say ('result: ' + ($t2 -replace "`r?`n", ' / '))
        if ($t2 -match 'CREATED' -and $t2 -match 'REMOVED') {
            Say "APPLIES: '> nul' in Git Bash created a real file called nul; Git Bash's own rm removed it."
            Say 'DO: have the agent redirect to /dev/null, never nul, in anything Git Bash runs. If one is stuck: rm nul from Git Bash, or [System.IO.File]::Delete("\\?\<full path>\nul").'
            $verdicts['trap2_nul'] = 'APPLIES'
        } elseif ($t2 -match 'NOTCREATED') {
            Say 'DOES NOT APPLY: this Git Bash did not create a nul file.'
            $verdicts['trap2_nul'] = 'DOES NOT APPLY'
        } elseif ($t2 -match 'STUCK') {
            Say ("CANNOT TEST (Git Bash's rm could not remove the nul file it created in $work - the folder is left in place; delete the file with: [System.IO.File]::Delete(`"\\?\$work\nul`") ).")
            $verdicts['trap2_nul'] = 'CANNOT TEST'
        } else {
            Say 'CANNOT TEST (unexpected Git Bash output).'
            $verdicts['trap2_nul'] = 'CANNOT TEST'
        }
        if ($t2 -notmatch 'STUCK') { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # ================= trap 3: backslashes halved by the agent's Bash tool =================
    Head 'trap 3 - backslashes come out halved (ceil(n/2)) in the Bash tool'
    $probe = "printf '%s|' 'n1=\x' 'n2=\\x' 'n4=\\\\x' 'n6=\\\\\\x'; echo"
    $expected = 'n1=\x|n2=\\x|n4=\\\\x|n6=\\\\\\x|'
    $halved   = 'n1=\x|n2=\x|n4=\\x|n6=\\\x|'
    # The halving is done by Git Bash's own MSYS2 runtime when bash.exe receives a -c argument
    # from a non-MSYS parent (PowerShell, cmd.exe, Node - which is how an agent's Bash tool
    # launches it). So this script CAN reproduce it: it launches bash.exe -c from PowerShell.
    # A script FILE run by bash never shows it (file contents are not a command-line argument).
    Say ('command sent as a -c argument: ' + $probe)
    Say ('expected if untouched:         ' + $expected)
    Say ('halved (trap applies):         ' + $halved)
    if (-not $gitBash) {
        Say 'CANNOT TEST (no Git Bash found - the halving lives in Git Bash''s MSYS2 runtime; without it there is nothing to test).'
        $verdicts['trap3_backslash'] = 'CANNOT TEST'
    } else {
        $got = (& $gitBash -c $probe 2>&1 | Out-String).Trim()
        Say ('bash.exe -c from this PowerShell:  ' + $got)
        $save = $env:MSYS; $env:MSYS = 'noglob'
        $gotNoglob = (& $gitBash -c $probe 2>&1 | Out-String).Trim()
        $env:MSYS = $save
        Say ('same with MSYS=noglob:             ' + $gotNoglob)
        if ($AgentOutput) {
            $ao = $AgentOutput.Trim()
            Say ('your agent printed (inline):       ' + $ao)
            if ($ao -eq $halved) { Say '  -> agent output is HALVED, matching the pattern above.' }
            elseif ($ao -eq $expected) { Say '  -> agent output is intact.' }
            else { Say '  -> agent output matches neither pattern; paste the single printed line exactly, nothing else. Ignored for the verdict.' }
        }
        if ($got -eq $halved) {
            Say 'APPLIES: every backslash run came back as ceil(n/2). Git Bash''s MSYS2 runtime rewrote the -c argument before bash parsed it - the same path an agent''s Bash tool uses (anthropics/claude-code#85856, #100063).'
            if ($gotNoglob -eq $expected) { Say '  MSYS=noglob stopped it here - evidence of the layer, NOT a fix to hand to an agent: set on the whole agent process it broke a hook command containing quotes (measured 2026-10-11).' }
            Say 'DO: for backslash-heavy content use the PowerShell tool or the file-writing tool, then run the file; never a Bash heredoc (it lands on disk already halved).'
            $verdicts['trap3_backslash'] = 'APPLIES'
        } elseif ($got -eq $expected) {
            Say 'DOES NOT APPLY: bash.exe -c from PowerShell kept every backslash on this machine.'
            if ($AgentOutput -and $AgentOutput.Trim() -eq $halved) { Say '  but your agent''s inline output was halved - its tool adds a step this script does not reproduce; report that with your agent version.' }
            $verdicts['trap3_backslash'] = 'DOES NOT APPLY'
        } else {
            Say 'CANNOT TEST (output matched neither pattern - compare by hand with the two lines above).'
            $verdicts['trap3_backslash'] = 'CANNOT TEST'
        }
    }

    # ================= summary =================
    Head 'summary'
    foreach ($k in $verdicts.Keys) { Say ('{0,-18} {1}' -f $k, $verdicts[$k]) }
    $cannot = @($verdicts.Values | Where-Object { $_ -eq 'CANNOT TEST' }).Count
    $exit = if ($cannot -gt 0) { 1 } else { 0 }
    Say ('exit code: ' + $exit + '  (0 = every check reached a verdict, 1 = something could not be tested)')

    if ($Json) {
        $obj = [ordered]@{ tool = 'Test-ClaudeCodeWindows.ps1'; when = (Get-Date -Format 's'); powershell = "$($PSVersionTable.PSVersion)"; gitbash = $gitBash; verdicts = $verdicts; exit = $exit }
        Write-Output ($obj | ConvertTo-Json -Depth 4)
    } else {
        $lines | ForEach-Object { Write-Output $_ }
    }
    exit $exit
} catch {
    if ($Json) {
        Write-Output (([ordered]@{ tool = 'Test-ClaudeCodeWindows.ps1'; error = $_.Exception.Message; verdicts = $verdicts; exit = 2 }) | ConvertTo-Json -Depth 4)
    } else {
        Write-Output ('SCRIPT FAILED: ' + $_.Exception.Message)
    }
    exit 2
}
