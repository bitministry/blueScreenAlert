Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------- Paths ----------
$Base = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
$ConfigPath = Join-Path $Base "config.ini"

# ---------- Config (read-only) ----------
$limit   = 85
$seconds = 15
$kill    = @("chrome","msedge","firefox")

if (Test-Path $ConfigPath) {
    $ini = Get-Content $ConfigPath -Raw
    if ($ini -match 'limit\s*=\s*(\d+)')   { $limit   = [int]$matches[1] }
    if ($ini -match 'seconds\s*=\s*(\d+)') { $seconds = [int]$matches[1] }
    if ($ini -match 'kill\s*=\s*(.+)')     { $kill    = $matches[1] -split '[;,\s]+' }
}

# ---------- Single instance ----------
$mutex = New-Object System.Threading.Mutex($false, "Global\BlueScreenAlert")
if (-not $mutex.WaitOne(0)) { exit }

# ---------- Memory ----------
function Get-CommitPercent {
    $c = Get-Counter '\Memory\Committed Bytes','\Memory\Commit Limit'
    $used  = ($c.CounterSamples | Where-Object Path -like '*Committed Bytes').CookedValue
    $total = ($c.CounterSamples | Where-Object Path -like '*Commit Limit').CookedValue
    [math]::Round(100 * $used / $total)
}

# ---------- UI ----------
function Confirm-CloseBrowsers($commitPct) {
    $msg = "Memory usage is critical ($commitPct%).`n`nClose all browsers now?"
    [System.Windows.Forms.MessageBox]::Show(
        $msg,
        "BlueScreenAlert",
        [System.Windows.Forms.MessageBoxButtons]::OKCancel,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
}

# ---------- Action ----------
function Close-Browsers {
    foreach ($name in $kill) {
        Get-Process -Name $name -ErrorAction SilentlyContinue |
            ForEach-Object {
                try { Stop-Process -Id $_.Id -Force } catch {}
            }
    }
}

# ---------- Loop ----------
while ($true) {
    $commit = Get-CommitPercent

    if ($commit -ge $limit) {
        $res = Confirm-CloseBrowsers $commit
        if ($res -eq 'OK') {
            Close-Browsers
        }
    }

    Start-Sleep -Seconds $seconds
}
