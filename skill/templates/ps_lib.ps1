# ps_lib.ps1 -- vetted primitives for driving external tools from PowerShell.
#
# WHY THIS FILE EXISTS
#   Every function here exists because the obvious ad-hoc one-liner produced a
#   WRONG ANSWER at least once during this project. They are not style
#   preferences; each carries the failure it prevents.
#
#   The real root cause of those failures was not that PowerShell is hard --
#   it is that non-trivial work was being done with freshly typed inline
#   commands, which are never tested before they are trusted.
#
#   Dot-source it:   . ".\ps_lib.ps1"
#
# ASCII ONLY (PowerShell parses .ps1 with the system code page on zh-CN).

# ---------------------------------------------------------------------------
# Invoke-Native
#
# WHY: the naive version was
#         & make all 2>&1 | Where-Object { $_ -match 'error:' }
#      with $ErrorActionPreference = 'Stop' set at the top. PowerShell turns
#      ANY stderr output from a native command into a terminating error under
#      Stop, so a harmless make warning killed the script mid-build and the
#      exit code said "1" -- while make itself had been doing fine.
#
# RULE: never merge native stderr through a PowerShell pipeline. Redirect to a
#       FILE with cmd, then read the file. The file is also the evidence.
# ---------------------------------------------------------------------------
function Invoke-Native {
    param(
        [Parameter(Mandatory=$true)][string]$CommandLine,
        [string]$LogFile
    )
    if (-not $LogFile) {
        $LogFile = Join-Path $env:TEMP ('native_' + [guid]::NewGuid().ToString('N') + '.log')
    }
    cmd /c "$CommandLine > `"$LogFile`" 2>&1" | Out-Null
    $code = $LASTEXITCODE
    $lines = @()
    if (Test-Path -LiteralPath $LogFile) {
        $lines = @(Get-Content -LiteralPath $LogFile -ErrorAction SilentlyContinue)
    }
    return [pscustomobject]@{
        ExitCode = $code
        LogFile  = $LogFile
        Lines    = $lines
        Text     = ($lines -join "`n")
    }
}

# ---------------------------------------------------------------------------
# Select-NativeLine
#   Convenience filter over Invoke-Native's captured lines.
# ---------------------------------------------------------------------------
function Select-NativeLine {
    param(
        [Parameter(Mandatory=$true)]$Result,
        [Parameter(Mandatory=$true)][string]$Pattern
    )
    return @($Result.Lines | Where-Object { $_ -match $Pattern })
}

# ---------------------------------------------------------------------------
# Get-FreeSpaceGB
#
# WHY: Get-PSDrive returned "used 0.0 GB / free 0.0 GB" for every drive in this
#      environment -- impossible values that were briefly believed. DriveInfo
#      reported the real numbers (C: 76 GB free, D: 164 GB free).
#
# RULE: if a measurement is physically implausible, it is a BROKEN MEASUREMENT,
#       not a surprising fact. Re-measure with an independent API before acting.
# ---------------------------------------------------------------------------
function Get-FreeSpaceGB {
    param([string]$Drive = 'C:')
    foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
        if ($d.Name -eq $Drive -and $d.IsReady) {
            return [math]::Round($d.AvailableFreeSpace / 1GB, 1)
        }
    }
    return $null
}

function Get-AllDrivesGB {
    $out = @()
    foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
        if ($d.IsReady) {
            $out += [pscustomobject]@{
                Drive  = $d.Name
                TotalGB = [math]::Round($d.TotalSize / 1GB, 1)
                FreeGB  = [math]::Round($d.AvailableFreeSpace / 1GB, 1)
            }
        }
    }
    return $out
}

# ---------------------------------------------------------------------------
# Test-OuterWrite
#
# WHY: a tool reported "Project is read-only" while the file attributes said
#      IsReadOnly=False. A one-line bare write test answered it in 2 seconds:
#      writes outside the workspace were denied by the environment, not by the
#      file.
#
# RULE: before blaming a tool's permission error, prove whether the path is
#       writable at all.
# ---------------------------------------------------------------------------
function Test-OuterWrite {
    param([Parameter(Mandatory=$true)][string]$Directory)
    $probe = Join-Path $Directory ('__wtest_' + [guid]::NewGuid().ToString('N') + '.txt')
    try {
        Set-Content -LiteralPath $probe -Value 'probe' -ErrorAction Stop
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        return $true
    } catch {
        return $false
    }
}

# ---------------------------------------------------------------------------
# Test-ToolWithKnownAnswer
#
# WHY: an HTTPS probe reported "the competition site's TLS is broken". The same
#      probe, run against www.baidu.com, ALSO reported broken -- the probe was
#      broken, not the site. A wrong conclusion was reported to the user before
#      anyone checked the instrument.
#
# RULE: a probe earns trust only by being run against an input whose correct
#       answer is already known. Do that FIRST, not after the mistake.
# ---------------------------------------------------------------------------
function Test-ToolWithKnownAnswer {
    param(
        [Parameter(Mandatory=$true)][scriptblock]$Probe,
        [Parameter(Mandatory=$true)][scriptblock]$IsHealthy,
        [string]$Name = 'probe'
    )
    $result = $null
    $err = $null
    try   { $result = & $Probe }
    catch { $err = $_.Exception.Message }
    $healthy = $false
    if (-not $err) {
        try { $healthy = [bool](& $IsHealthy $result) } catch { $healthy = $false }
    }
    return [pscustomobject]@{
        Name    = $Name
        Healthy = $healthy
        Result  = $result
        Error   = $err
        Verdict = $(if ($healthy) { 'TRUSTWORTHY' } else { '*** DO NOT TRUST THIS PROBE ***' })
    }
}

# ---------------------------------------------------------------------------
# Find-Files
#
# WHY: "Get-ChildItem <dir> -File -Include *.md" returns NOTHING, silently,
#      because -Include needs -Recurse (or a wildcard in -Path). It looked like
#      "there are no documents" when there were many.
#
# RULE: a filter that can return empty must be verified against a case known to
#       be non-empty (skill B1's "would my output tell me?").
# ---------------------------------------------------------------------------
function Find-Files {
    param(
        [Parameter(Mandatory=$true)][string]$Root,
        [Parameter(Mandatory=$true)][string]$Pattern,
        [int]$Max = 200
    )
    $hits = @(Get-ChildItem -LiteralPath $Root -Recurse -Filter $Pattern -File -ErrorAction SilentlyContinue)
    if ($hits.Count -eq 0) {
        Write-Host ("  Find-Files: 0 hits for '{0}' under {1}  <-- verify this is real" -f $Pattern, $Root)
    }
    return @($hits | Select-Object -First $Max)
}

# ---------------------------------------------------------------------------
# Write-Report
#   Every report line goes to the HOST, never into a function's return stream.
#
# WHY: a function that emitted bare strings and was called as
#         if (Show-Color ...) { $n++ }
#      returned "N strings + 1 bool" as one collection; the if() consumed and
#      DISCARDED every string. The count came out right and every detail line
#      vanished, which nearly passed as "that is just how the script prints".
#
# RULE: inside a function, diagnostics go to Write-Host; only real output goes
#       to the pipeline.
# ---------------------------------------------------------------------------
function Write-Report {
    param([Parameter(Mandatory=$true)][string]$Message)
    Write-Host $Message
}
