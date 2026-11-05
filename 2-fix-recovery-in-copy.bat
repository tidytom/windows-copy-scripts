<# : ---- Batch part: asks for administrator rights, then runs the PowerShell part below ----
@echo off
net session >nul 2>&1 || (powershell -NoProfile -Command "Start-Process -Verb RunAs -FilePath '%~f0'" & exit /b)
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ((Get-Content -LiteralPath '%~f0') -join [Environment]::NewLine)"
exit /b
#>

# =============================================================================
#  2-fix-recovery-in-copy.bat
#  Run INSIDE THE COPY, the first time you start it.
#  Turns Windows Recovery (Windows RE) back on, using the recovery partition
#  on the copy's own disk. BitLocker needs this before it can be turned on.
# =============================================================================

$ErrorActionPreference = 'Stop'
$RecType = '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}'

function Stop-Script($msg) {
    Write-Host "`nSTOPPED: $msg" -ForegroundColor Red
    Read-Host "Press Enter to close"; exit 1
}

$d     = (Get-Partition -DriveLetter C).DiskNumber
$disk  = Get-Disk -Number $d
$label = (Get-Volume -DriveLetter C).FileSystemLabel
Write-Host "`nThis Windows (C: '$label') is on Disk $d, serial $($disk.SerialNumber)" -ForegroundColor Cyan

$rec = Get-Partition -DiskNumber $d | Where-Object GptType -eq $RecType | Select-Object -First 1
if (-not $rec) { Stop-Script "No recovery partition found on Disk $d." }

$L = [char[]](82..90 + 71..81) | Where-Object { -not (Test-Path "$($_):\") } | Select-Object -First 1
$rec | Add-PartitionAccessPath -AccessPath "$($L):\"
try {
    $dir = "$($L):\Recovery\WindowsRE"
    if (-not (Test-Path "$dir\Winre.wim")) { throw "Winre.wim was not found on the recovery partition." }
    reagentc /disable | Out-Null
    reagentc /setreimage /path $dir /target C:\Windows
    if ($LASTEXITCODE -ne 0) { throw "reagentc /setreimage failed." }
    reagentc /enable
    if ($LASTEXITCODE -ne 0) { throw "reagentc /enable failed." }
}
catch {
    $rec | Remove-PartitionAccessPath -AccessPath "$($L):\" -ErrorAction SilentlyContinue
    Stop-Script $_.Exception.Message
}
$rec | Remove-PartitionAccessPath -AccessPath "$($L):\" -ErrorAction SilentlyContinue

Write-Host ""
reagentc /info
Write-Host "`nIf 'Windows RE status' says Enabled, you can turn on BitLocker." -ForegroundColor Green
Read-Host "`nPress Enter to close"
