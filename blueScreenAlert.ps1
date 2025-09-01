# VirtualMemoryGuard.ps1
# Monitors commit charge and pagefile usage; warns and optionally kills heavy apps.
Add-Type -AssemblyName System.Windows.Forms

# ---- config (ini-like) ----
$DefaultConfig = @"
[Settings]
limit=85
seconds=15
kill=chrome;msedge;firefox
"@

# Resolve script folder reliably (works for ps1 or compiled exe)
if ($PSScriptRoot) {
    $Base = $PSScriptRoot
} else {
    $Base = Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
}

$ConfigPath = Join-Path $Base "config.ini"
if (-not (Test-Path $ConfigPath)) {
    $DefaultConfig | Set-Content -Path $ConfigPath -Encoding UTF8
}

# ---- read config ----
$ini = Get-Content -Path $ConfigPath -Raw
$limit   = [int]  ( ($ini -split '\r?\n') | Where-Object {$_ -match '^\s*limit\s*=\s*(\d+)'} | ForEach-Object { [int]($Matches[1]) } | Select-Object -First 1 )
$seconds = [int]  ( ($ini -split '\r?\n') | Where-Object {$_ -match '^\s*seconds\s*=\s*(\d+)'} | ForEach-Object { [int]($Matches[1]) } | Select-Object -First 1 )
$killStr =         ( ($ini -split '\r?\n') | Where-Object {$_ -match '^\s*kill\s*=\s*(.+)'}  | ForEach-Object { $Matches[1] }          | Select-Object -First 1 )

if (-not $limit)   { $limit = 85 }
if (-not $seconds) { $seconds = 15 }
$KillList = @()
if ($killStr) { $KillList = $killStr -split '[;,\s]+' | Where-Object { $_ } }

# ---- helper: read commit % ----
function Get-CommitPercent {
    try {
        $c = Get-Counter '\Memory\Committed Bytes','\Memory\Commit Limit'
        $committed = ($c.CounterSamples | Where-Object { $_.Path -like '*Committed Bytes' }).CookedValue
        $limit     = ($c.CounterSamples | Where-Object { $_.Path -like '*Commit Limit'   }).CookedValue
        if ($limit -gt 0) { return [math]::Round(100.0 * $committed / $limit, 1) } else { return 0 }
    } catch { return 0 }
}

# ---- helper: read pagefile % ----
function Get-PagefilePercent {
    try {
        $p = (Get-Counter '\Paging File(_Total)\% Usage').CounterSamples[0].CookedValue
        return [math]::Round($p,1)
    } catch { return 0 }
}

# ---- action: warn + kill ----
function Take-Action([double] $commitPct, [double] $pagePct) {
    $msg = "Memory pressure high:`nCommit: $commitPct%`nPagefile: $pagePct%"
    [System.Windows.Forms.MessageBox]::Show($msg, "VirtualMemoryGuard", 'OK', 'Warning') | Out-Null
    if ($KillList.Count -gt 0) {
        foreach ($name in $KillList) {
            Stop-Process -Name $name -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---- single-instance guard ----
$mtx = New-Object System.Threading.Mutex($false, "Global\VirtualMemoryGuard_Mutex")
if (-not $mtx.WaitOne(0, $false)) { return }

# ---- main loop ----
while ($true) {
    $commitPct = Get-CommitPercent
    $pagePct   = Get-PagefilePercent

    if ($commitPct -ge $limit) {
        Take-Action -commitPct $commitPct -pagePct $pagePct
    }

    Start-Sleep -Seconds $seconds
}
