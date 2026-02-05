# ==============================================================================
# AUDIT PERF - VERSION SIMPLE
# ==============================================================================

# --- 1. CONFIGURATION (Valeurs de référence) ---
$Ref_Chrome  = 2.5
$Ref_Edge    = 2.0
$Ref_IO      = 45.0
$Ref_SHA     = 25.0

# --- 2. IDENTITE DU POSTE ---
$Hostname = $env:COMPUTERNAME
$Date     = Get-Date -Format "dd-MM-yyyy_HHmm"
$CPU      = (Get-WmiObject Win32_Processor).Name

# --- 3. VERIFICATION DES AGENTS (Simple et robuste) ---
Write-Host "--- Verification des agents ---" -ForegroundColor Cyan
$AgentsMap = @{ 
    "SentinelOne" = "SentinelAgent"
    "Ivanti_UWM"  = "EmUser"
    "Ivanti_FD"   = "FileDirector"
    "ForcePoint"  = "DLPScanner"
}

$AgentsStatusList = @()
foreach ($Name in $AgentsMap.Keys) {
    $Proc = Get-Process $AgentsMap[$Name] -ErrorAction SilentlyContinue
    $State = if ($Proc) { "ACTIF" } else { "INACTIF" }
    $AgentsStatusList += "$Name=$State"
    Write-Host "$Name : $State"
}
$FinalStatus = $AgentsStatusList -join " / "

# --- 4. TESTS DE PERFORMANCE ---
$Results = @()

function Run-Test($Label, $Value, $Baseline) {
    $Ratio = [math]::Round($Value / $Baseline, 1)
    $obj = [PSCustomObject]@{
        Date           = $Date
        Machine        = $Hostname
        Processeur     = $CPU
        Test           = $Label
        Resultat_Sec   = $Value
        Baseline_Sec   = $Baseline
        Ratio_Friction = "x$Ratio"
        Etat_Agents    = $FinalStatus
    }
    return $obj
}

# -- Test Lancement Chrome
Write-Host "`nTest Chrome..." -ForegroundColor Yellow
$T_Chrome = Measure-Command {
    try {
        $p = Start-Process chrome -PassThru -WindowStyle Minimized -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
        Stop-Process $p -Force -ErrorAction SilentlyContinue
    } catch { }
}
$Results += Run-Test "Ouverture Chrome" $T_Chrome.TotalSeconds $Ref_Chrome

# -- Test Stress I/O (6000 fichiers)
Write-Host "Test I/O intensif (6000 fichiers)..." -ForegroundColor Yellow
$Path = "$env:LOCALAPPDATA\Temp_Bench"
if (!(Test-Path $Path)) { New-Item $Path -ItemType Directory | Out-Null }

$T_IO = Measure-Command {
    1..6000 | ForEach-Object { "Donnees de test" | Out-File "$Path\file$_.txt" -Encoding ascii }
}
$Results += Run-Test "Stress_IO_6000" $T_IO.TotalSeconds $Ref_IO

# -- Test SHA256 (500 fichiers)
Write-Host "Test SHA256 (500 fichiers)..." -ForegroundColor Yellow
$T_SHA = Measure-Command {
    Get-ChildItem $Path | Select-Object -First 500 | ForEach-Object { Get-FileHash $_.FullName -Algorithm SHA256 | Out-Null }
}
$Results += Run-Test "Stress_SHA256" $T_SHA.TotalSeconds $Ref_SHA

Remove-Item $Path -Recurse -Force

# --- 5. EXPORT ET AFFICHAGE ---
Write-Host "`n--- RESULTATS ---" -ForegroundColor Green
$Results | Format-Table -AutoSize

$FileName = "Diagnostic_$($Hostname)_$($Date).csv"
$Results | Export-Csv -Path "$HOME\Desktop\$FileName" -NoTypeInformation -Delimiter ";" -Encoding UTF8

Write-Host "`nFichier cree sur le bureau : $FileName" -ForegroundColor Green
