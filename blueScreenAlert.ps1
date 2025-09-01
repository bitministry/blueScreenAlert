# blueScreenAlert.ps1 — Defender-safe via Task Scheduler (read-only config)
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()

# --- Locate config beside script/EXE ---
if ($PSScriptRoot) { $Base = $PSScriptRoot } else { $Base = Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
$SelfPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$ConfigPath = Join-Path $Base "config.ini"

# --- Event source ---
if (-not [System.Diagnostics.EventLog]::SourceExists("BlueScreenAlert")) { try { New-EventLog -LogName Application -Source "BlueScreenAlert" } catch {} }

# --- Read config (READ-ONLY). If missing keys, use hard defaults (no file writes). ---
$cfgExists = Test-Path $ConfigPath
$ini = $null
if ($cfgExists) { try { $ini = Get-Content -Path $ConfigPath -Raw -ErrorAction Stop } catch { $ini = $null } }

function Get-IniValue([string]$iniText,[string]$key,[string]$def){
  if (-not $iniText) { return $def }
  $m = [regex]::Match($iniText, "^\s*${key}\s*=\s*(.+)$", 'Multiline')
  if ($m.Success) { return $m.Groups[1].Value.Trim() } else { return $def }
}

$defLimit   = '85'
$defSeconds = '15'
$defKill    = 'chrome;msedge;firefox'
$defAdded   = 'false'

$limit   = [int](Get-IniValue $ini 'limit'   $defLimit)
$seconds = [int](Get-IniValue $ini 'seconds' $defSeconds)
$killStr =       Get-IniValue $ini 'kill'    $defKill
$added   =       Get-IniValue $ini 'added_to_startup' $defAdded
$KillList = @(); if ($killStr) { $KillList = $killStr -split '[;,\s]+' | Where-Object { $_ } }

# --- Log config path + loaded values ---
try {
  if ($cfgExists) { Write-EventLog -LogName Application -Source "BlueScreenAlert" -EntryType Information -EventId 2100 -Message "Reading config from: $ConfigPath" }
  else { Write-EventLog -LogName Application -Source "BlueScreenAlert" -EntryType Warning -EventId 2099 -Message "Config NOT found at: $ConfigPath (using in-memory defaults)" }
  $loadedMsg = "Loaded settings -> limit=$limit, seconds=$seconds, kill=[$($KillList -join ', ')], added_to_startup=$added"
  Write-EventLog -LogName Application -Source "BlueScreenAlert" -EntryType Information -EventId 2101 -Message $loadedMsg
} catch {}

# --- If config says to install, register a hidden Scheduled Task (CurrentUser) ---
function Ensure-Task {
  param([string]$taskName,[string]$targetPath)

  try {
    $exists = $false
    try { $null = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop; $exists = $true } catch {}
    $action = $null
    if ($targetPath -match '\.exe$') {
      # Run EXE directly
      $action = New-ScheduledTaskAction -Execute $targetPath
    } else {
      # Run PS1 via powershell.exe hidden
      $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$targetPath`""
    }
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $settings = New-ScheduledTaskSettingsSet -Hidden -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $principal = New-ScheduledTaskPrincipal -UserId $env:UserName -LogonType Interactive -RunLevel Limited

    if ($exists) {
      Set-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal | Out-Null
      Write-EventLog -LogName Application -Source "BlueScreenAlert" -EntryType Information -EventId 2202 -Message "Scheduled task '$taskName' updated"
    } else {
      Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "BlueScreenAlert autostart (Defender-safe)" | Out-Null
      Write-EventLog -LogName Application -Source "BlueScreenAlert" -EntryType Information -EventId 2201 -Message "Scheduled task '$taskName' created"
    }
  } catch {
    Write-EventLog -LogName Application -Source "BlueScreenAlert" -EntryType Warning -EventId 2203 -Message "Failed to create/update task '$taskName': $($_.Exception.Message)"
  }
}

if ($added -match '^(true|1|yes)$') {
  Ensure-Task -taskName "BlueScreenAlert" -targetPath $SelfPath
}

# --- Single instance ---
$mtx = New-Object System.Threading.Mutex($false, "Global\VirtualMemoryGuard_Mutex")
if (-not $mtx.WaitOne(0, $false)) { return }

# --- Metrics ---
function Get-CommitPercent {
  try {
    $c = Get-Counter '\Memory\Committed Bytes','\Memory\Commit Limit'
    $committed = ($c.CounterSamples | Where-Object { $_.Path -like '*Committed Bytes' }).CookedValue
    $limitb    = ($c.CounterSamples | Where-Object { $_.Path -like '*Commit Limit' }).CookedValue
    if ($limitb -gt 0) { return [math]::Round(100.0 * $committed / $limitb, 1) } else { return 0 }
  } catch { return 0 }
}
function Get-PagefilePercent { try { return [math]::Round((Get-Counter '\Paging File(_Total)\% Usage').CounterSamples[0].CookedValue,1) } catch { return 0 } }

# --- Action ---
function Take-Action([double] $commitPct, [double] $pagePct) {
  $msg = "Memory pressure high:`nCommit: $commitPct%`nPagefile: $pagePct%"
  [System.Windows.Forms.MessageBox]::Show($msg, "BlueScreenAlert", 'OK', 'Warning') | Out-Null
  foreach ($name in $KillList) { Stop-Process -Name $name -Force -ErrorAction SilentlyContinue }
  try { Write-EventLog -LogName Application -Source "BlueScreenAlert" -EntryType Warning -EventId 1001 -Message "High memory usage. Commit=$commitPct%, Pagefile=$pagePct%. Killed: $($KillList -join ', ')" } catch {}
}

# --- Main loop (keeps running) ---
while ($true) {
  $cp = Get-CommitPercent
  $pp = Get-PagefilePercent
  if ($cp -ge $limit) { Take-Action -commitPct $cp -pagePct $pp }
  Start-Sleep -Seconds $seconds
}
