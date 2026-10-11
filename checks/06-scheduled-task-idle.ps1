<#
.SYNOPSIS
  Trap 6: A scheduled task dies in seconds with exit code 3221225786 (0xC000013A).
.DESCRIPTION
  New Task Scheduler tasks default to "stop if the computer stops being idle", even when
  "run only if idle" is switched off. This is a common cause of exit code 3221225786.
  This check only reads settings. It changes nothing.
.PARAMETER TaskName
  Optional. Name of an existing scheduled task to inspect (read-only).
.NOTES
  Fieldpane - checks/06-scheduled-task-idle.ps1
  Safe: read-only. Does not create, modify, or delete any scheduled task.
#>
param(
    [string]$TaskName
)

$defaultSetting = (New-ScheduledTaskSettingsSet).IdleSettings.StopOnIdleEnd
Write-Output "default StopOnIdleEnd for a brand-new task definition on this host: $defaultSetting"

if ($defaultSetting) {
    Write-Output ""
    Write-Output "APPLIES: new scheduled tasks on this machine default to stopping when the computer stops being idle."
    Write-Output "DO: for each task, read `$s = (Get-ScheduledTask -TaskName <name>).Settings; set `$s.IdleSettings.StopOnIdleEnd = `$false; Set-ScheduledTask -TaskName <name> -Settings `$s"
} else {
    Write-Output ""
    Write-Output "DOES NOT APPLY: new scheduled tasks on this machine do not default to StopOnIdleEnd = True."
    Write-Output "DO: nothing for new tasks here - still check existing tasks if you see exit code 3221225786."
}

if ($TaskName) {
    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
        $value = $task.Settings.IdleSettings.StopOnIdleEnd
        Write-Output ""
        Write-Output "task '$TaskName' StopOnIdleEnd: $value"
        if ($value) {
            Write-Output "this task will stop early if the machine leaves idle state while the task is running."
        } else {
            Write-Output "this task is not affected by the idle-stop default."
        }
    } catch {
        Write-Output ""
        Write-Output "CANNOT TEST (task '$TaskName' not found or not readable: $($_.Exception.Message))."
    }
}
