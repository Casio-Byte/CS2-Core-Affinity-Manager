@echo off
setlocal
title CS2 Core Affinity Manager

rem ======================= Settings (edit these) =======================
rem  Cores CS2 must NOT use. Examples: 0   0,1   0-3
set "EXCLUDE_CORES=0"
rem  Add -LogicalOnly to free only the exact cores above, not their
rem  Hyper-Threading twins. Add -Priority High for higher CPU priority.
set "EXTRA_OPTIONS="
rem =====================================================================

set "SCRIPT=%~dp0CS2-Core-Affinity-Manager.ps1"
if not exist "%SCRIPT%" (
    echo Could not find CS2-Core-Affinity-Manager.ps1 next to this file.
    echo Keep the .bat and the .ps1 in the same folder.
    pause
    exit /b 1
)

powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -ExcludeCores "%EXCLUDE_CORES%" %EXTRA_OPTIONS% %*
if errorlevel 1 pause
