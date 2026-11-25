param([ValidateSet('Install','Restore')][string]$Mode = 'Install')
$ErrorActionPreference = 'Stop'
$taskRoot = $PSScriptRoot
$resultPath = Join-Path $taskRoot 'installation-result.json'
$original = Get-Content -LiteralPath (Join-Path $taskRoot 'original-installed/manifest.json') -Raw | ConvertFrom-Json
$custom = Get-Content -LiteralPath (Join-Path $taskRoot 'custom-build/manifest.json') -Raw | ConvertFrom-Json
$target = 'C:\Program Files (x86)\HopToDesk\HopToDesk.exe'
$backup = Join-Path $taskRoot 'original-installed/HopToDesk.exe'
$source = if ($Mode -eq 'Restore') { $backup } else { Join-Path $taskRoot 'custom-build/HopToDesk.exe' }
$sourceHash = if ($Mode -eq 'Restore') { $original.SHA256 } else { $custom.SHA256 }
$expectedTargetHash = if ($Mode -eq 'Restore') { $custom.SHA256 } elseif ($custom.PreviousSHA256) { $custom.PreviousSHA256 } else { $original.SHA256 }
$staging = Join-Path (Split-Path $target) 'HopToDesk.tray-staged'
$replacementBackup = Join-Path (Split-Path $target) ('HopToDesk.previous-' + [Guid]::NewGuid().ToString('N') + '.exe')
$serviceStopped = $false
$result = [ordered]@{Mode=$Mode;Success=$false;Target=$target;Rollback=$false;HelperProcessId=$PID}
try {
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Administrator privileges are required.' }
    if ($original.InstalledPath -ne $target) { throw 'Backup manifest target mismatch.' }
    if ((Get-FileHash -LiteralPath $backup).Hash -ne $original.SHA256) { throw 'Original backup integrity check failed.' }
    if ((Get-FileHash -LiteralPath $source).Hash -ne $sourceHash) { throw 'Source integrity check failed.' }
    $allowedTargetHashes = @($expectedTargetHash)
    if ($Mode -eq 'Install') { $allowedTargetHashes += $original.SHA256 }
    if ($allowedTargetHashes -notcontains (Get-FileHash -LiteralPath $target).Hash) { throw 'Installed executable changed; refusing to overwrite it.' }
    Copy-Item -LiteralPath $source -Destination $staging -Force
    if ((Get-FileHash -LiteralPath $staging).Hash -ne $sourceHash) { throw 'Staged executable integrity check failed.' }
    $servicePid = (Get-CimInstance Win32_Service -Filter "Name='HopToDesk'").ProcessId
    $hopRows = @(Get-CimInstance Win32_Process -Filter "Name='HopToDesk.exe'")
    $ownedIds = [Collections.Generic.HashSet[uint32]]::new()
    $null = $ownedIds.Add([uint32]$servicePid)
    do {
        $added = $false
        foreach ($row in $hopRows) {
            if ($row.ExecutablePath -eq $target -or $ownedIds.Contains([uint32]$row.ParentProcessId)) {
                if ($ownedIds.Add([uint32]$row.ProcessId)) { $added = $true }
            }
        }
    } while ($added)
    $installedProcessRows = @($hopRows | Where-Object {$ownedIds.Contains([uint32]$_.ProcessId)})
    $result.StoppedProcessIds = @($installedProcessRows.ProcessId)
    $installedProcesses = @($installedProcessRows |
        ForEach-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue })
    foreach ($process in $installedProcesses) { $null = $process.Handle }
    Stop-Service -Name HopToDesk -Force
    (Get-Service HopToDesk).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
    $serviceStopped = $true
    Get-CimInstance Win32_Process -Filter "Name='HopToDesk.exe'" |
        Where-Object {$_.ExecutablePath -eq $target} |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    foreach ($process in $installedProcesses) {
        if (!$process.HasExited) { Stop-Process -InputObject $process -Force }
        if (!$process.HasExited -and !$process.WaitForExit(15000)) {
            throw "Installed process $($process.Id) did not finish exiting."
        }
        $process.Dispose()
    }
    [IO.File]::Replace($staging, $target, $replacementBackup)
    $result.ReplacedFileBackup = $replacementBackup
    if ((Get-FileHash -LiteralPath $target).Hash -ne $sourceHash) { throw 'Installed executable integrity check failed.' }
    if ((Get-Service HopToDesk).Status -eq 'Running') { Restart-Service -Name HopToDesk -Force }
    else { Start-Service -Name HopToDesk }
    (Get-Service HopToDesk).WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
    $result.Success = $true
    $result.SHA256 = $sourceHash
    $result.Service = (Get-Service HopToDesk).Status.ToString()
} catch {
    $result.Error = $_.Exception.Message
    $result.ErrorLine = $_.InvocationInfo.ScriptLineNumber
    if ($serviceStopped) {
        try {
            Stop-Service HopToDesk -Force -ErrorAction SilentlyContinue
            Get-CimInstance Win32_Process -Filter "Name='HopToDesk.exe'" |
                Where-Object {$_.ExecutablePath -eq $target} |
                ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
            if ((Get-FileHash -LiteralPath $target).Hash -ne $original.SHA256) {
                $rollbackStaging = Join-Path (Split-Path $target) ('HopToDesk.rollback-' + [Guid]::NewGuid().ToString('N'))
                Copy-Item -LiteralPath $backup -Destination $rollbackStaging
                $failedBackup = Join-Path (Split-Path $target) ('HopToDesk.failed-' + [Guid]::NewGuid().ToString('N') + '.exe')
                [IO.File]::Replace($rollbackStaging, $target, $failedBackup)
            }
            if ((Get-FileHash -LiteralPath $target).Hash -ne $original.SHA256) { throw 'Rollback integrity check failed.' }
            Start-Service HopToDesk
            $result.Rollback = $true
        } catch { $result.RollbackError = $_.Exception.Message }
    }
} finally {
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Force }
    $result | ConvertTo-Json | Set-Content -LiteralPath $resultPath
    $result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $taskRoot "installation-result-$PID.json")
}
if (!$result.Success) { exit 1 }

