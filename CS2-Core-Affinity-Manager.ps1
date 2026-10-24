<#
.SYNOPSIS
    Waits for Counter-Strike 2 (cs2.exe) and pins it to a chosen set of CPU cores.

.DESCRIPTION
    Runs in the background, detects every cs2.exe launch, and applies a CPU affinity
    mask that leaves the chosen cores free for Windows, Discord, OBS and the rest.
    If anything resets the affinity while the game runs, it is re-applied.

    Works in Windows PowerShell 5.1 and PowerShell 7+, and when compiled to an .exe
    with ps2exe.

.PARAMETER ExcludeCores
    Logical CPU numbers CS2 must NOT run on, e.g. 0  or  0,1  or  0-3. Default: 0.

.PARAMETER LogicalOnly
    By default the Hyper-Threading / SMT twin of each excluded core is excluded
    too, so a whole physical core is freed rather than half of one. -LogicalOnly
    excludes only the exact logical cores listed (the old script's behaviour).

.PARAMETER Priority
    Optional process priority for CS2: Unchanged (default), Normal, AboveNormal, High.

.PARAMETER ProcessName
    Process to watch, without .exe. Default: cs2.

.PARAMETER ApplyDelaySeconds
    Seconds to wait after the game starts before applying, so it can finish
    starting up. Default: 5.

.PARAMETER PollSeconds
    How often to check for the game / re-check affinity. Default: 5.

.PARAMETER Once
    Apply to the next launch, then exit instead of waiting for further launches.

.PARAMETER Silent
    No console output; log to a file instead. Turned on automatically for the
    "No Window" exe.

.PARAMETER LogFile
    Write a log here. Silent mode defaults to %LOCALAPPDATA%\CS2AffinityManager\log.txt.

.EXAMPLE
    .\CS2-Core-Affinity-Manager.ps1
    Frees physical core 0 (logical 0 and its SMT sibling) for the system.

.EXAMPLE
    .\CS2-Core-Affinity-Manager.ps1 -ExcludeCores 0-3 -LogicalOnly -Priority High
#>
[CmdletBinding()]
param(
    [string[]]$ExcludeCores = @('0'),
    [switch]$LogicalOnly,
    [ValidateSet('Unchanged', 'Normal', 'AboveNormal', 'High')]
    [string]$Priority = 'Unchanged',
    [string]$ProcessName = 'cs2',
    [ValidateRange(0, 600)]
    [int]$ApplyDelaySeconds = 5,
    [ValidateRange(1, 600)]
    [int]$PollSeconds = 5,
    [switch]$Once,
    [switch]$Silent,
    [string]$LogFile
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

# ---------------------------------------------------------------- environment ---

$isWindowsOs = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT

# The "No Window" exe has no console to write to: switch to file logging.
$hostPath = ''
try { $hostPath = (Get-Process -Id $PID).Path } catch { }
if (-not $Silent -and $hostPath -and ([IO.Path]::GetFileName($hostPath) -match 'No ?Window')) {
    $Silent = $true
}
if ($Silent -and -not $LogFile) {
    $base = $env:LOCALAPPDATA
    if (-not $base) { $base = [IO.Path]::GetTempPath() }
    $LogFile = Join-Path $base 'CS2AffinityManager\log.txt'
}
if ($LogFile) {
    $logDir = Split-Path -Parent $LogFile
    if ($logDir -and -not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    # Keep the log from growing forever when it runs at every startup.
    if ((Test-Path $LogFile) -and (Get-Item $LogFile).Length -gt 1MB) {
        Move-Item $LogFile "$LogFile.old" -Force
    }
}

function Write-Log {
    param([string]$Message, [ValidateSet('Info', 'Ok', 'Warn', 'Error')][string]$Level = 'Info')
    $line = '[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message
    if ($LogFile) {
        try { Add-Content -Path $LogFile -Value ('{0} {1,-5} {2}' -f (Get-Date -Format 'yyyy-MM-dd'), $Level.ToUpper(), $line) } catch { }
    }
    if (-not $Silent) {
        $colour = @{ Info = 'Gray'; Ok = 'Green'; Warn = 'Yellow'; Error = 'Red' }[$Level]
        Write-Host $line -ForegroundColor $colour
    }
}

function Set-Title([string]$Text) {
    if ($Silent) { return }
    try { $Host.UI.RawUI.WindowTitle = $Text } catch { }
}

# ------------------------------------------------------------- CPU topology ---

function Get-CpuTopology {
    $logical = 0
    $physical = 0
    if ($isWindowsOs) {
        try {
            # Sum across sockets: Win32_Processor returns one entry per physical CPU.
            $cpus = @(Get-CimInstance -ClassName Win32_Processor)
            $logical = [int]($cpus | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
            $physical = [int]($cpus | Measure-Object -Property NumberOfCores -Sum).Sum
        } catch { }
    }
    if ($logical -le 0) { $logical = [Environment]::ProcessorCount }
    if ($physical -le 0) { $physical = $logical }
    [pscustomobject]@{ Logical = $logical; Physical = $physical; Smt = ($logical -gt $physical) }
}

function Get-AffinityMask {
    param($Topology, [int[]]$Exclude, [bool]$WithSiblings)

    $count = $Topology.Logical
    if ($count -gt 64) {
        # ProcessorAffinity only covers one 64-thread processor group.
        Write-Log "This PC has $count logical CPUs; only the first 64 (one processor group) can be targeted." Warn
        $count = 64
    }

    $excluded = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($c in $Exclude) {
        if ($c -lt 0 -or $c -ge $count) {
            Write-Log "Ignoring core $c - this PC only has cores 0-$($count - 1)." Warn
            continue
        }
        [void]$excluded.Add($c)
        # Windows numbers SMT twins next to each other (0/1, 2/3, ...). On hybrid
        # Intel chips only the P-cores have twins and they are numbered first, so
        # pairing still holds for the low core numbers people normally exclude.
        if ($WithSiblings -and $Topology.Smt) {
            $twin = $c -bxor 1
            if ($twin -lt $count) { [void]$excluded.Add($twin) }
        }
    }

    [long]$mask = 0
    for ($i = 0; $i -lt $count; $i++) {
        if (-not $excluded.Contains($i)) { $mask = $mask -bor ([long]1 -shl $i) }
    }

    $allowed = @(0..($count - 1) | Where-Object { -not $excluded.Contains($_) })
    [pscustomobject]@{
        Mask     = $mask
        Allowed  = $allowed
        Excluded = @($excluded | Sort-Object)
    }
}

function Format-CoreList([int[]]$Cores) {
    if ($null -eq $Cores -or $Cores.Count -eq 0) { return 'none' }
    # Collapse runs: 2,3,4,5,8 -> 2-5, 8
    $parts = @()
    $i = 0
    while ($i -lt $Cores.Count) {
        $j = $i
        while ($j + 1 -lt $Cores.Count -and $Cores[$j + 1] -eq $Cores[$j] + 1) { $j++ }
        if ($j -eq $i) { $parts += "$($Cores[$i])" } else { $parts += "$($Cores[$i])-$($Cores[$j])" }
        $i = $j + 1
    }
    $parts -join ', '
}

# -------------------------------------------------------------- per process ---

function Set-GameAffinity {
    param([System.Diagnostics.Process]$Process, [long]$Mask, [string]$PriorityClass)
    try {
        $Process.Refresh()
        if ($Process.HasExited) { return $false }
        if ($Process.ProcessorAffinity.ToInt64() -ne $Mask) {
            $Process.ProcessorAffinity = [IntPtr]$Mask
        }
        if ($PriorityClass -ne 'Unchanged' -and $Process.PriorityClass.ToString() -ne $PriorityClass) {
            $Process.PriorityClass = [System.Diagnostics.ProcessPriorityClass]$PriorityClass
        }
        return $true
    } catch {
        $msg = $_.Exception.Message
        if ($_.Exception.InnerException) { $msg = $_.Exception.InnerException.Message }
        Write-Log "PID $($Process.Id): could not set affinity - $msg" Error
        if ($msg -match 'denied') {
            Write-Log 'Access denied: if the game runs as administrator, run this tool as administrator too.' Warn
        }
        return $false
    }
}

function ConvertTo-CoreNumbers([string[]]$Text) {
    # Accepts "0", "0,1", "0 1", "0-3", "0,2-3" (and arrays of those). When
    # launched with -File, cmd or Steam, "0,1" arrives as one string.
    $result = @()
    foreach ($token in (($Text -join ',') -split '[,;\s]+')) {
        if ($token -eq '') { continue }
        if ($token -match '^(\d+)-(\d+)$') {
            $a = [int]$Matches[1]; $b = [int]$Matches[2]
            if ($a -gt $b) { $a, $b = $b, $a }
            $result += $a..$b
        } elseif ($token -match '^\d+$') {
            $result += [int]$token
        } else {
            throw "Can't read core number '$token'. Use something like: 0   or   0,1   or   0-3"
        }
    }
    , $result
}

# ---------------------------------------------------------------------- main ---

# Only one copy at a time (e.g. startup task plus the Steam shortcut).
$mutex = New-Object System.Threading.Mutex($false, "Local\CS2CoreAffinityManager_$ProcessName")
$haveLock = $false
try { $haveLock = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $haveLock = $true }
if (-not $haveLock) {
    Write-Log 'Another copy of CS2 Core Affinity Manager is already running. Exiting.' Warn
    if (-not $Silent) { Start-Sleep -Seconds 3 }
    exit 0
}

try {
    try { $exclude = ConvertTo-CoreNumbers $ExcludeCores } catch { Write-Log $_.Exception.Message Error; exit 1 }
    $topology = Get-CpuTopology
    $plan = Get-AffinityMask -Topology $topology -Exclude $exclude -WithSiblings (-not $LogicalOnly)

    if ($plan.Mask -eq 0) {
        Write-Log 'That would leave CS2 with no cores at all. Exclude fewer cores.' Error
        exit 1
    }

    $smtText = 'no SMT'
    if ($topology.Smt) { $smtText = 'SMT on' }
    Write-Log ("CPU: {0} physical / {1} logical cores ({2})" -f $topology.Physical, $topology.Logical, $smtText)
    Write-Log ("Reserved for system: {0}" -f (Format-CoreList $plan.Excluded))
    Write-Log ("CS2 allowed on:      {0}   (mask 0x{1:X})" -f (Format-CoreList $plan.Allowed), $plan.Mask)
    if ($plan.Excluded.Count -eq 0) { Write-Log 'Nothing is reserved, so this will not change anything.' Warn }
    if ($Priority -ne 'Unchanged') { Write-Log "Priority: $Priority" }
    Write-Log "Waiting for $ProcessName.exe..."
    Set-Title "CS2 Affinity Manager - waiting for $ProcessName.exe"

    # PID -> state, so each process is handled once and re-checked for drift.
    $tracked = @{}

    while ($true) {
        $running = @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)
        $alive = @{}

        foreach ($p in $running) {
            $alive[$p.Id] = $true
            if (-not $tracked.ContainsKey($p.Id)) {
                $tracked[$p.Id] = @{ Applied = $false; Seen = Get-Date; LastCpu = $null; LastAt = $null }
                Write-Log "$ProcessName.exe started (PID $($p.Id))."
            }
            $state = $tracked[$p.Id]

            if (-not $state.Applied) {
                if (((Get-Date) - $state.Seen).TotalSeconds -lt $ApplyDelaySeconds) { continue }
                if (Set-GameAffinity -Process $p -Mask $plan.Mask -PriorityClass $Priority) {
                    $state.Applied = $true
                    Write-Log "PID $($p.Id): affinity applied." Ok
                }
            } else {
                # Re-apply if something (the game, another tool) changed it.
                try {
                    $p.Refresh()
                    if (-not $p.HasExited -and $p.ProcessorAffinity.ToInt64() -ne $plan.Mask) {
                        Write-Log "PID $($p.Id): affinity was changed externally, re-applying." Warn
                        [void](Set-GameAffinity -Process $p -Mask $plan.Mask -PriorityClass $Priority)
                    }
                } catch { }
            }

            # Live CPU / RAM in the window title instead of a scrolling tasklist.
            try {
                $now = Get-Date; $cpuTime = $p.TotalProcessorTime
                if ($state.LastCpu) {
                    $pct = ($cpuTime - $state.LastCpu).TotalMilliseconds / (($now - $state.LastAt).TotalMilliseconds * $topology.Logical) * 100
                    Set-Title ("CS2 Affinity Manager - PID {0} | CPU {1:N0}% | RAM {2:N0} MB" -f $p.Id, $pct, ($p.WorkingSet64 / 1MB))
                }
                $state.LastCpu = $cpuTime; $state.LastAt = $now
            } catch { }
        }

        foreach ($id in @($tracked.Keys)) {
            if (-not $alive.ContainsKey($id)) {
                $tracked.Remove($id)
                Write-Log "$ProcessName.exe closed (PID $id)."
                if ($tracked.Count -eq 0) {
                    if ($Once) { Write-Log 'Done (-Once).'; exit 0 }
                    Write-Log "Waiting for next launch..."
                    Set-Title "CS2 Affinity Manager - waiting for $ProcessName.exe"
                }
            }
        }

        if ($tracked.Count -gt 0) {
            Start-Sleep -Seconds ([Math]::Min($PollSeconds, [Math]::Max(1, $ApplyDelaySeconds)))
        } else {
            Start-Sleep -Seconds $PollSeconds
        }
    }
} finally {
    if ($haveLock) { try { $mutex.ReleaseMutex() } catch { } }
    $mutex.Dispose()
}
