# BlueScreenAlert

Monitors Windows paging file usage and warns before a system crash (BSOD) caused by virtual memory exhaustion.  
If the configured limit is exceeded, it alerts the user and force-closes Chrome, Edge, and Firefox to free memory.  
On first run, it will also add itself to Windows Startup so it launches automatically.

---

## Requirements
- Windows 10 or newer
- PowerShell 3.0 or newer
- `config.ini` in the same folder as the executable.

Example `config.ini`:
```ini
[Settings]
limit=85
seconds=60
added_to_startup=false
```

---

## Reference
- [PS2EXE GitHub Repository](https://github.com/MScholtes/PS2EXE)

---

## Build Instructions
Install **PS2EXE**:
```powershell
Install-Module -Name ps2exe -Scope CurrentUser
```

Compile the script to an EXE:
```powershell
ps2exe blueScreenAlert.ps1 blueScreenAlert.exe -noConsole
```

---

## Usage
1. Place `blueScreenAlert.exe` and `config.ini` in the same folder.
2. Run `blueScreenAlert.exe` for the first time — it will automatically add itself to Windows Startup.
3. On each run, it will:
   - Check paging file usage every `seconds` interval.
   - If usage exceeds `limit` (%), show a warning and close browsers.

---

## Troubleshooting
**Execution policy errors when compiling**  
If PowerShell blocks running scripts:
```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**Blocked file warning on download**  
Right-click the `.ps1` file → Properties → check “Unblock” → Apply.

**EXE not starting on boot**  
Check the shortcut in:
```
%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup
```
It should point to `blueScreenAlert.exe`.

**Multiple instances**  
The EXE uses a mutex to ensure only one instance runs at a time.

---

## Notes
- This tool is intended for personal use and testing.  
- Force-killing browsers will close all open tabs without saving unsaved data.  
- Use with caution on production systems.
