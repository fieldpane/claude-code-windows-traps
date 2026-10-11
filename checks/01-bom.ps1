<#
.SYNOPSIS
  Trap 1: Script says "OK", exit code 0, and the file isn't there.
.DESCRIPTION
  Windows PowerShell 5.1 reads a UTF-8 .ps1 file WITHOUT a byte-order mark (BOM) as if it
  were ANSI (the system codepage). A non-ASCII character typed inside that script - for
  example in a string that becomes part of a file name - is then misread, so the script
  does not do what its own source text says, while still reporting success.

  This check writes a BOM-less .ps1 that prints one word containing non-ASCII characters,
  runs it with Windows PowerShell, and compares what came out to what the source says.
  A mismatch is the same misread that, in a real script, turns a file name into a
  different one than the file that was supposedly written or read.
.NOTES
  Fieldpane - checks/01-bom.ps1
  Safe: only creates and deletes one file under $env:TEMP\fieldpane-check-01.
#>

$work = Join-Path $env:TEMP 'fieldpane-check-01'
$exitCode = 0

try {
    if (Test-Path $work) { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $work -Force | Out-Null

    # The leaf name of the script itself stays ASCII-only on purpose, so this test isolates
    # the BOM issue from any unrelated path-encoding question.
    $scriptPath = Join-Path $work 'fieldpane-check-01-runme.ps1'
    $expected = 'café'

    $body = "Write-Output '$expected'`r`n"

    # Write WITHOUT a BOM - this is the trap condition.
    $noBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($scriptPath, $body, $noBom)

    $actual = ((& powershell.exe -NoProfile -File $scriptPath) | Out-String).Trim()

    Write-Output "expected (what the source text says): $expected"
    Write-Output "actual   (what Windows PowerShell printed): $actual"

    if ($actual -ne $expected) {
        Write-Output ""
        Write-Output "APPLIES: this Windows PowerShell read the BOM-less script's non-ASCII text differently than it was written - the same misread turns a non-ASCII file name inside a script into a different file than the one you typed, while the script still reports success and exit code 0."
        Write-Output "DO: save .ps1 files with a BOM, send the command inline instead of -File, or keep non-ASCII characters out of paths."
    } else {
        Write-Output ""
        Write-Output "DOES NOT APPLY: the text came back exactly as written on this machine."
        Write-Output "DO: nothing here - re-test if the system codepage or PowerShell edition changes."
    }
} catch {
    $exitCode = 1
    Write-Output "CANNOT TEST (error while running the check: $($_.Exception.Message))."
    Write-Output "DO: run the command in the README by hand and compare."
} finally {
    if (Test-Path $work) { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
}

exit $exitCode
