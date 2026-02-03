# ==============================================================================
# NOM DU SCRIPT : Audit-Perf-DataCollector.ps1
# DESCRIPTION  : Collecteur de donnees brutes structure pour Power BI.
# ==============================================================================

# --- CONFIGURATION ---
$Baseline_Chrome = 2.5
$Baseline_Edge   = 2.0
$Baseline_IO     = 45.0
$Baseline_SHA    = 25.0

# --- 1. COLLECTE METADONNEES ---
$Hostname = $env:COMPUTERNAME
$DateUTC  = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss")
$CPU      = (Get-WmiObject Win32_Processor).Name.Trim()
$RAM      = [math]::Round((Get-WmiObject Win32_PhysicalMemory | Measure-Object Capacity -Sum).Sum / 1GB, 0)
$Model    = (Get-WmiObject Win32_ComputerSystem).Model

# --- 2. FONCTION ETAT AGENTS (Format Pipe-Separated pour split Power BI) ---
function Get-AgentsStatus {
    $Agents = @{ "S1"="SentinelAgent"; "UWM"="EmUser"; "FD"="FileDirector"; "FP"="DLPScanner" }
    $Status = @()
    foreach ($A in $Agents.Keys) {
        $State = if (Get-Process $Agents[$A] -ErrorAction SilentlyContinue) { "1" } else { "0" }
        $Status += "$A:$State"
    }
    return $Status -join "|"
}
$CurrentStatus = Get-AgentsStatus

# --- 3. EXECUTION DES TESTS ---
$FinalReport = @()

# Helper pour ajouter les resultats
function Add-Result($TestName, $Value, $Base) {
    $Ratio = if ($Base -gt 0) { [math]::Round($Value / $Base, 2) } else { 0 }
    $Global:FinalReport += [PSCustomObject]@{
        Timestamp_UTC  = $DateUTC
        Hostname       = $Hostname
        Model          = $Model
        CPU            = $CPU
        RAM_GB         = $RAM
        Test_Name      = $TestName
        Duration_Sec   = [string]$Value.ToString().Replace(",", ".") # Format Power BI
        Baseline_Sec   = [string]$Base.ToString().Replace(",", ".")
        Friction_Ratio = [string]$Ratio.ToString().Replace(",", ".")
        Agents_State   = $CurrentStatus
    }
}

# --- TESTS ---
Write-Host "Collecte en cours sur $Hostname..." -ForegroundColor Cyan

# Apps Launch
foreach ($App in @(@("Edge","msedge"), @("Chrome","chrome"))) {
    Get-Process $App[1] -ErrorAction SilentlyContinue | Stop-Process -Force
    $T = Measure-Command {
        try {
            $P = Start-Process $App[1] -PassThru -WindowStyle Minimized -ErrorAction Stop
            $null = $P.WaitForInputIdle(30000); Start-Sleep -Seconds 5; Stop-Process $P -Force
        } catch { $null }
    }
    Add-Result "Launch_$($App[0])" $T.TotalSeconds $Baselines["Ouverture $($App[0])"]
}

# Stress IO & SHA (AppData)
$Path = "$env:LOCALAPPDATA\Bench_PBI_Test"
if (!(Test-Path $Path)) { New-Item $Path -ItemType Directory -Force | Out-Null }

$T_IO = Measure-Command { 1..6000 | ForEach-Object { "PBI Data" | Out-File "$Path\$_" -Encoding ascii } }
Add-Result "Storage_IO_Stress" $T_IO.TotalSeconds $Baseline_IO

$T_SHA = Measure-Command { Get-ChildItem $Path | Select-Object -First 500 | ForEach-Object { Get-FileHash $_.FullName -Algorithm SHA256 | Out-Null } }
Add-Result "Security_SHA_Stress" $T_SHA.TotalSeconds $Baseline_SHA

Remove-Item $Path -Recurse -Force

# --- 4. EXPORT ---
$FileName = "Audit_Perf_$($Hostname)_$((Get-Date -Format 'yyyyMMdd')).csv"
$FinalReport | Export-Csv -Path "$HOME\Desktop\$FileName" -NoTypeInformation -Delimiter ";" -Encoding UTF8
Write-Host "Termine. Fichier pret pour Power BI : $FileName" -ForegroundColor Green
