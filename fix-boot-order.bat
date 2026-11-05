<# : ---- Batch part: asks for administrator rights, then runs the PowerShell part below ----
@echo off
net session >nul 2>&1 || (powershell -NoProfile -Command "Start-Process -Verb RunAs -FilePath '%~f0'" & exit /b)
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ((Get-Content -LiteralPath '%~f0') -join [Environment]::NewLine)"
exit /b
#>

# =============================================================================
#  fix-boot-order.bat
#  Use only if the PC starts the copy by default again (for example after a
#  BIOS or Windows update). Works from either Windows.
#  Puts your ORIGINAL first in the boot order and hides the startup menu.
#  It saves a backup of the boot settings first (bcdedit /export) and prints
#  the command that puts them back.
# =============================================================================

$ErrorActionPreference = 'Stop'
$EspType = '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'

$Backup = $null
function Stop-Script($msg) {
    Write-Host "`nSTOPPED: $msg" -ForegroundColor Red
    if ($Backup) {
        Write-Host "To put the boot settings back, run this in an administrator Command Prompt:"
        Write-Host "    bcdedit /import `"$Backup`""
    }
    Read-Host "Press Enter to close"; exit 1
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
    @{n='Size (GB)'; e={[math]::Round($_.Size/1GB)}} -AutoSize
Write-Host "This Windows (C:) is on Disk $((Get-Partition -DriveLetter C).DiskNumber)."
$num = Read-Host "Type the disk NUMBER of your ORIGINAL Windows (from the list above)"
if ($num -notmatch '^\d+$') { Stop-Script "That isn't a disk number." }
$disk = Get-Disk -Number ([int]$num) -ErrorAction SilentlyContinue
if (-not $disk) { Stop-Script "There is no Disk $num." }
Write-Host "`nOriginal Windows disk: Disk $($disk.Number)  ($($disk.SerialNumber))" -ForegroundColor Cyan

$esp = Get-Partition -DiskNumber $disk.Number | Where-Object GptType -eq $EspType | Select-Object -First 1
if (-not $esp) { Stop-Script "No EFI partition found on Disk $($disk.Number)." }

# Back up the boot settings before changing them
$BackupDir = Join-Path $env:SystemDrive 'bcd-backups'
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
$BackupFile = Join-Path $BackupDir ("bcd-before-fix-boot-order-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$out = Invoke-Native bcdedit @('/export', $BackupFile)
if ($LASTEXITCODE -ne 0) { Stop-Script "Could not back up the boot settings, so nothing was changed:`n$out" }
$Backup = $BackupFile
Write-Host "Boot settings backed up to $Backup" -ForegroundColor Cyan

$L = [char[]](83..90 + 71..82) | Where-Object { -not (Test-Path "$($_):\") } | Select-Object -First 1
$esp | Add-PartitionAccessPath -AccessPath "$($L):\"
try {
    $id = Find-FirmwareEntry $L
    if (-not $id) { throw "No boot entry found for the original disk. Set the boot order in the BIOS instead." }
    $out = Invoke-Native bcdedit @('/set', '{fwbootmgr}', 'displayorder', $id, '/addfirst')
    if ($LASTEXITCODE -ne 0) { throw "bcdedit could not change the boot order:`n$out" }
    $out = Invoke-Native bcdedit @('/store', "$($L):\EFI\Microsoft\Boot\BCD", '/timeout', '0')
    if ($LASTEXITCODE -ne 0) { throw "bcdedit could not hide the startup menu:`n$out" }
}
catch {
    $esp | Remove-PartitionAccessPath -AccessPath "$($L):\" -ErrorAction SilentlyContinue
    Stop-Script $_.Exception.Message
}
$esp | Remove-PartitionAccessPath -AccessPath "$($L):\" -ErrorAction SilentlyContinue

Write-Host "`nDone. Restart and the PC will start your original." -ForegroundColor Green
Write-Host "Boot settings backup: $Backup"
Write-Host "  To put them back:  bcdedit /import `"$Backup`""
Read-Host "`nPress Enter to close"
