@echo off
title CS2 Core Affinity Manager
echo Starting CS2 affinity manager...
echo.

powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ^
"Write-Output 'Waiting for cs2.exe...'; ^
function Get-AffinityMask { ^
    $cores = (Get-CimInstance Win32_Processor).NumberOfLogicalProcessors; ^
    $maskBinary = ('1' * ($cores - 1)) + '0'; ^
    return [Convert]::ToInt32($maskBinary, 2); ^
}; ^
$mask = Get-AffinityMask; ^
while ($true) { ^
    while (-not (Get-Process -Name 'cs2' -ErrorAction SilentlyContinue)) { Start-Sleep -Seconds 10 }; ^
    $proc = Get-Process -Name 'cs2'; ^
    Write-Output 'cs2.exe detected.'; ^
    Write-Output ('Applying affinity mask: ' + $mask); ^
    try { ^
        $proc.ProcessorAffinity = $mask; ^
        Write-Output 'Affinity applied successfully.'; ^
    } catch { ^
        Write-Output 'Failed to apply affinity. Will retry on next launch.'; ^
    }; ^
    Write-Output 'Monitoring until cs2.exe closes...'; ^
    while (Get-Process -Name 'cs2' -ErrorAction SilentlyContinue) { Start-Sleep -Seconds 10 }; ^
    Write-Output 'cs2.exe closed. Waiting for next launch...'; ^
}"

:loop
cls
echo ==== CS2 Resource Usage ====
tasklist /FI "IMAGENAME eq cs2.exe"
timeout /t 5 >nul
goto loop
