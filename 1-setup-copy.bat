<# : ---- Batch part: asks for administrator rights, then runs the PowerShell part below ----
@echo off
net session >nul 2>&1 || (powershell -NoProfile -Command "Start-Process -Verb RunAs -FilePath '%~f0'" & exit /b)
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ((Get-Content -LiteralPath '%~f0') -join [Environment]::NewLine)"
exit /b
#>

# =============================================================================
#  1-setup-copy.bat
#  Run from your ORIGINAL Windows, right after cloning it with Samsung Magician.
#  - Gives the copy a new disk ID and brings it online
#  - Makes the copy use C: for itself when it starts
#  - Builds the copy's own startup files (so the PC's boot menu can start it)
#  - Adds the copy to the startup menu
#  - Keeps your original first in the boot order, with no menu shown
#  Before it changes the boot settings it saves a backup with bcdedit /export
#  and prints the command that puts them back.
#  UEFI (GPT) PCs only. BitLocker must be off on the original before cloning.
# =============================================================================

$ErrorActionPreference = 'Stop'
$EspType = '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'

$Backup = $null
function Stop-Script($msg) {
    Write-Host "`nSTOPPED: $msg" -ForegroundColor Red
    if ($Backup) {
        Write-Host "If the PC doesn't start normally now, put the boot settings back with this command"
        Write-Host "in an administrator Command Prompt:  bcdedit /import `"$Backup`""
    }
    Read-Host "Press Enter to close"; exit 1
}
function Get-FreeLetter {
    [char[]](83..90 + 71..82) | Where-Object { -not (Test-Path "$($_):\") } | Select-Object -First 1
}
function Invoke-Native([string]$exe, [string[]]$arguments) {
    # Runs a Windows program and returns everything it printed as one text. Check
    # $LASTEXITCODE afterwards. Error stops are relaxed while it runs, because Windows
    # PowerShell 5.1 would otherwise stop at the program's first error line, before its
    # exit code can be checked and explained.
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $out = & $exe @arguments 2>&1 | ForEach-Object { "$_" } }
    finally { $ErrorActionPreference = $old }
    return ($out -join "`n")
}
function Find-FirmwareEntry($letter) {
    # The firmware boot entry whose startup partition is mounted at $letter, or $null.
    # The labels bcdedit prints ("identifier", ...) are translated on non-English Windows,
    # so this looks only at the values: the block that names "partition=S:" and the first
    # {GUID} in that block, which is the entry's identifier.
    $blocks = ((bcdedit /enum firmware /v) -join "`n") -split "`n\s*`n"
    $block  = $blocks | Where-Object { $_ -match "partition=$($letter):" } | Select-Object -First 1
    if (-not $block) { return $null }
    $m = [regex]::Match($block, '\{[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\}')
    if ($m.Success) { return $m.Value } else { return $null }
}

Write-Host "`nDisks on this PC:" -ForegroundColor Cyan
Get-Disk | Format-Table Number, FriendlyName, SerialNumber,
    @{n='Size (GB)'; e={[math]::Round($_.Size/1GB)}}, OperationalStatus -AutoSize

# The original is the disk this Windows (C:) runs from; you pick the copy from the list.
$orig = Get-Disk -Number (Get-Partition -DriveLetter C).DiskNumber
Write-Host "This Windows (C:) is on Disk $($orig.Number): $($orig.FriendlyName)" -ForegroundColor Cyan
$ans = Read-Host "Is this your ORIGINAL Windows (the one you cloned from)? Type YES"
if ($ans -cne 'YES') { Stop-Script "Start your original Windows and run this again." }
$num = Read-Host "Type the disk NUMBER of the COPY (from the list above)"
if ($num -notmatch '^\d+$') { Stop-Script "That isn't a disk number." }
$copy = Get-Disk -Number ([int]$num) -ErrorAction SilentlyContinue
if (-not $copy) { Stop-Script "There is no Disk $num." }
if ($copy.Number -eq $orig.Number) { Stop-Script "That is the original's disk. Pick the copy's disk." }
Write-Host "Original: Disk $($orig.Number)    Copy: Disk $($copy.Number)" -ForegroundColor Cyan

$ans = Read-Host "Set up the copy on Disk $($copy.Number)? Type YES"
if ($ans -cne 'YES') { Stop-Script "Cancelled." }

# ---- 0. Back up the boot settings before anything changes -----------------
$BackupDir = Join-Path $env:SystemDrive 'bcd-backups'
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
$BackupFile = Join-Path $BackupDir ("bcd-before-setup-copy-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$out = Invoke-Native bcdedit @('/export', $BackupFile)
if ($LASTEXITCODE -ne 0) { Stop-Script "Could not back up the boot settings, so nothing was changed:`n$out" }
$Backup = $BackupFile
Write-Host "   Boot settings backed up to $Backup" -ForegroundColor Cyan
Write-Host "   To put them back (in an administrator Command Prompt):  bcdedit /import `"$Backup`"" -ForegroundColor Cyan

# ---- 1. New disk ID for the copy, bring it online ---------------------------
$dp = Join-Path $env:TEMP 'copy-id.txt'
"select disk $($copy.Number)`r`nuniqueid disk id={$([guid]::NewGuid())}" | Set-Content $dp -Encoding ASCII
$out = Invoke-Native diskpart @('/s', $dp)
$code = $LASTEXITCODE
Remove-Item $dp
if ($code -ne 0) { Stop-Script "diskpart could not give the copy a new disk ID (code $code):`n$out" }
Set-Disk -Number $copy.Number -IsOffline $false -ErrorAction SilentlyContinue
Set-Disk -Number $copy.Number -IsReadOnly $false -ErrorAction SilentlyContinue
Start-Sleep 3
if ((Get-Disk -Number $copy.Number).IsOffline) { Stop-Script "The copy's disk is still offline." }
Write-Host "1. New disk ID set, copy is online."

# ---- 2. Find the copy's startup (EFI) and Windows partitions ----------------
$parts = Get-Partition -DiskNumber $copy.Number
$esp   = $parts | Where-Object GptType -eq $EspType | Select-Object -First 1
if (-not $esp) { Stop-Script "No EFI partition on the copy. Did the clone finish?" }
$win = $null
foreach ($p in ($parts | Where-Object { $_.Size -gt 50GB })) {
    if (-not ($p.DriveLetter -match '[A-Z]')) {
        $p | Add-PartitionAccessPath -AssignDriveLetter
        $p = Get-Partition -DiskNumber $copy.Number -PartitionNumber $p.PartitionNumber
    }
    if (Test-Path "$($p.DriveLetter):\Windows\System32\config\SYSTEM") { $win = $p; break }
}
if (-not $win) { Stop-Script "No Windows found on the copy (turn off BitLocker on the original and clone again)." }
$W = "$($win.DriveLetter):"
Write-Host "2. Copy's Windows is on $W"

# ---- 3. Clear the copy's saved drive letters (so it takes C:) ---------------
$out = Invoke-Native reg @('load', 'HKLM\COPYSYS', "$W\Windows\System32\config\SYSTEM")
if ($LASTEXITCODE -ne 0) { Stop-Script "Could not open the copy's registry:`n$out" }
$out = Invoke-Native reg @('delete', 'HKLM\COPYSYS\MountedDevices', '/va', '/f')
$deleted = ($LASTEXITCODE -eq 0)
[gc]::Collect(); Start-Sleep 2
$unload = Invoke-Native reg @('unload', 'HKLM\COPYSYS')
if ($LASTEXITCODE -ne 0) {
    Write-Host "   Could not close the copy's registry. Restart the PC before you start the copy." -ForegroundColor Yellow
    Write-Host "   $unload" -ForegroundColor Yellow
}
if (-not $deleted) { Stop-Script "Could not clear the copy's saved drive letters:`n$out" }
Write-Host "3. Cleared the copy's saved drive letters."

# ---- 4. Copy's own startup files (boot order is preserved with /p) ----------
$L = Get-FreeLetter
$esp | Add-PartitionAccessPath -AccessPath "$($L):\"
try {
    $out = Invoke-Native bcdboot @("$W\Windows", '/s', "$($L):", '/f', 'UEFI', '/p')
    $code = $LASTEXITCODE
} finally { $esp | Remove-PartitionAccessPath -AccessPath "$($L):\" }
if ($code -ne 0) { Stop-Script "bcdboot could not build the copy's startup files (code $code):`n$out" }
Write-Host "4. Built the copy's own startup files."

# ---- 5. Add the copy to the original's startup menu -------------------------
$out = Invoke-Native bcdboot @("$W\Windows", '/d', '/addlast')
if ($LASTEXITCODE -ne 0) { Stop-Script "bcdboot could not add the copy to the startup menu (code $LASTEXITCODE):`n$out" }
Write-Host "5. Added the copy to the startup menu."

# ---- 6. Original first in boot order, no menu shown -------------------------
$oesp = Get-Partition -DiskNumber $orig.Number | Where-Object GptType -eq $EspType | Select-Object -First 1
$L = Get-FreeLetter
$oesp | Add-PartitionAccessPath -AccessPath "$($L):\"
$step6 = $true
try {
    $id = Find-FirmwareEntry $L
    if ($id) {
        $out = Invoke-Native bcdedit @('/set', '{fwbootmgr}', 'displayorder', $id, '/addfirst')
        if ($LASTEXITCODE -ne 0) {
            $step6 = $false
            Write-Host "   Could not change the boot order: $out" -ForegroundColor Yellow
        }
    } else {
        $step6 = $false
        Write-Host "   Could not find the original's boot entry. Set the original first in the BIOS boot order." -ForegroundColor Yellow
    }
    $out = Invoke-Native bcdedit @('/store', "$($L):\EFI\Microsoft\Boot\BCD", '/timeout', '0')
    if ($LASTEXITCODE -ne 0) {
        $step6 = $false
        Write-Host "   Could not hide the startup menu: $out" -ForegroundColor Yellow
    }
} finally { $oesp | Remove-PartitionAccessPath -AccessPath "$($L):\" }
if ($step6) { Write-Host "6. Original is first in the boot order, menu hidden." }
else { Write-Host "6. Finished with warnings (see above)." -ForegroundColor Yellow }

Write-Host "`nDone." -ForegroundColor Green
Write-Host "Restarts and power-ons start your ORIGINAL."
Write-Host "To start the copy: Shift + Restart > Use another operating system,"
Write-Host "  or press your PC's boot-menu key at power-on (often F8, F11, F12 or Esc)."
Write-Host "First time in the copy: run 2-fix-recovery-in-copy.bat before turning on BitLocker."
Write-Host "Boot settings backup: $Backup"
Write-Host "  To put them back:  bcdedit /import `"$Backup`""
Read-Host "`nPress Enter to close"
