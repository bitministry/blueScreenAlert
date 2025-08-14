$exeFile = "blueScreenAlert.exe"
Add-Type -AssemblyName System.Windows.Forms

# --- single-instance guard ---
$mtx = New-Object System.Threading.Mutex($false, "Global\BlueScreenAlertMutex")
if (-not $mtx.WaitOne(0, $false)) { return }

# --- paths relative to EXE location ---
$exePath  = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$basePath = Split-Path -Parent $exePath
$configPath = Join-Path $basePath "config.ini"

# --- ensure config.ini exists ---
if (-not (Test-Path $configPath)) {
    "[Settings]`r`nlimit=85`r`nseconds=60`r`nadded_to_startup=false" | Set-Content $configPath -Encoding ASCII
}

# --- read config.ini ---
$config = Get-Content $configPath | Where-Object { $_ -match "=" }
$settings = @{}
foreach ($line in $config) {
    $parts = $line -split "=", 2
    if ($parts.Count -eq 2) { $settings[$parts[0].Trim()] = $parts[1].Trim() }
}
$limit   = [int]$settings["limit"]
$seconds = [int]$settings["seconds"]

# --- one-time add to Startup ---
$added = $false
if ($settings.ContainsKey("added_to_startup")) {
    $added = ($settings["added_to_startup"].ToLower() -eq "true")
}
if (-not $added) {
    $startupLnk = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\blueScreenAlert.lnk'
    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut($startupLnk)
    $sc.TargetPath = $exePath
    $sc.WorkingDirectory = $basePath
    $sc.Save()

    # update config flag
    $cfg = Get-Content $configPath -Raw
    if ($cfg -match '(?im)^\s*added_to_startup\s*=') {
        $cfg = [regex]::Replace($cfg,'(?im)^\s*added_to_startup\s*=\s*(true|false)\s*$','added_to_startup=true')
    } else {
        $cfg += "`r`nadded_to_startup=true`r`n"
    }
    Set-Content $configPath $cfg -Encoding ASCII
}

# --- main loop ---
while ($true) {
    $page = Get-Counter '\Paging File(_Total)\% Usage'
    if ($page.CounterSamples[0].CookedValue -gt $limit) {
        [System.Windows.Forms.MessageBox]::Show("WARNING: Pagefile usage high!")
        Stop-Process -Name chrome,msedge,firefox -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds $seconds
}
