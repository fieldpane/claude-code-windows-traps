<#
.SYNOPSIS
  Trap 7: Which shell is Claude Code using on Windows?
.DESCRIPTION
  Read-only identification of what is on this machine: PowerShell edition, Git for
  Windows / Git Bash, WSL (with a timeout - wsl.exe can hang if no distro is installed),
  and the Claude Code CLI version. The same folder has at least three different path
  spellings depending on the shell (C:\Users\..., /c/Users/..., /mnt/c/Users/...), so
  this check flags it when more than one shell is available to choose from.
.NOTES
  Fieldpane - checks/07-which-shell.ps1
  Safe: read-only. Makes no changes. wsl.exe is given a 5-second timeout.
#>

function Invoke-WithTimeout {
    param([ScriptBlock]$Script, [int]$TimeoutSeconds = 5)
    $job = Start-Job -ScriptBlock $Script
    if (Wait-Job $job -Timeout $TimeoutSeconds) {
        $out = Receive-Job $job
        Remove-Job $job -Force
        return ($out | Out-String).Trim()
    } else {
        Stop-Job $job -ErrorAction SilentlyContinue
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        return "TIMEOUT after $TimeoutSeconds s"
    }
}

Write-Output "PSEdition: $($PSVersionTable.PSEdition)  (Desktop = Windows PowerShell 5.1, Core = PowerShell 7+)"
Write-Output "PSVersion: $($PSVersionTable.PSVersion)"

$gitPath = (Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if ($gitPath) {
    $gitVersion = (& git.exe --version) 2>&1
    Write-Output "git --version: $gitVersion"
    Write-Output "git.exe resolved from PATH to: $gitPath"
} else {
    Write-Output "git --version: CANNOT TEST (git.exe not found on PATH)."
}

$gitBashPresent = $false
$gitBashKnownPath = $null
if ($gitPath) {
    # git.exe is usually <root>\cmd\git.exe or <root>\mingw64\bin\git.exe - Git's own bash
    # lives at <root>\bin\bash.exe regardless of which git.exe PATH happened to pick.
    # <root>\cmd\git.exe -> two levels up; <root>\mingw64\bin\git.exe (PATH inside Git Bash) -> three.
    $gitRoot = Split-Path (Split-Path $gitPath -Parent) -Parent
    foreach ($root in @($gitRoot, (Split-Path $gitRoot -Parent))) {
        if (-not $root) { continue }
        $candidate = Join-Path $root 'bin\bash.exe'
        if (-not $gitBashKnownPath -and (Test-Path $candidate)) { $gitBashKnownPath = $candidate }
    }
}
if ($gitBashKnownPath) {
    Write-Output "Git Bash found at: $gitBashKnownPath"
    $gitBashPresent = $true
} else {
    Write-Output "Git Bash: CANNOT TEST (no bash.exe found next to git.exe's install root)."
}

$pathBash = (Get-Command bash.exe -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if ($pathBash) {
    $bashOut = (& bash.exe -lc 'uname -o') 2>&1
    Write-Output "bash.exe resolved from PATH (first match): $pathBash"
    Write-Output "uname -o via that bash: $bashOut   (Msys = Git Bash, GNU/Linux = WSL's own bash)"
    if ($gitBashKnownPath -and $pathBash -ne $gitBashKnownPath) {
        Write-Output "NOTE: plain 'bash.exe' on PATH is NOT Git Bash on this machine - something earlier on PATH (commonly C:\Windows\System32\bash.exe, which launches WSL) wins over Git's own bash.exe."
    }
} else {
    Write-Output "bash.exe via PATH lookup: CANNOT TEST (no bash.exe found on PATH at all)."
}

$wslResult = Invoke-WithTimeout -TimeoutSeconds 5 -Script { wsl.exe -e uname -o }
Write-Output "wsl -e uname -o (5s timeout): $wslResult"
$wslPresent = ($wslResult -match 'Linux')

try {
    $claudeVersion = (claude --version) 2>&1
    Write-Output "claude --version: $claudeVersion"
} catch {
    Write-Output "claude --version: CANNOT TEST (claude not found on PATH)."
}

$pathShadowed = ($gitBashKnownPath -and $pathBash -and ($pathBash -ne $gitBashKnownPath))

Write-Output ""
if (($gitBashPresent -and $wslPresent) -or $pathShadowed) {
    Write-Output "APPLIES: more than one shell named 'bash' is reachable on this machine (Git Bash and/or WSL), and plain PATH lookup does not reliably pick Git Bash - without writing down which shell a project uses, Claude Code or you could end up in the wrong one."
    Write-Output "DO: pick one shell per project, write it down, and verify with the commands above instead of assuming 'bash.exe' means Git Bash."
} elseif ($gitBashPresent -or $wslPresent) {
    Write-Output "DOES NOT APPLY as ambiguity: only one Bash-like shell was found on this machine, and PATH lookup resolves to it correctly."
    Write-Output "DO: nothing extra needed for shell choice; still confirm PSEdition above matches what you expect."
} else {
    Write-Output "CANNOT TEST (could not positively identify a Bash-like shell on this machine)."
    Write-Output "DO: run the individual commands above by hand and compare with the README."
}
