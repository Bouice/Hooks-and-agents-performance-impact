# ==============================================================================
# DIAGNOSTIC PERF V17 - ÉDITION EXPERT (IO RANDOM + STOPWATCH + HEADERS)
# ==============================================================================

# --- 1. CONFIGURATION DES BASES DE RÉFÉRENCE ---
$Baselines = @{
    "Launch_Chrome"      = 2.5
    "Launch_Edge"        = 2.0
    "Launch_Firefox"     = 2.5
    "Launch_Notepad"     = 0.5
    "Stress_Registre"    = 8.0   
    "Ecriture_10k_Files" = 45.0  # Augmenté car les fichiers sont maintenant plus gros (1Mo)
    "Compression_ZIP"    = 30.0  
    "Stress_SHA512"      = 15.0  
}

# --- 2. CONFIGURATION DES EXÉCUTABLES ---
$AppsToBench = @{ "Chrome"="chrome"; "Edge"="msedge"; "Firefox"="firefox"; "Notepad"="notepad" }

# --- 3. IDENTITÉ ET DOSSIER DE SORTIE ---
$Hostname  = $env:COMPUTERNAME
$DateJour  = Get-Date -Format "yyyy-MM-dd"
$HeurePrec = Get-Date -Format "HHmm"
$CPU       = (Get-WmiObject Win32_Processor).Name

$TargetFolderName = "Audit_$($Hostname)_$($DateJour)"
$TargetFolderPath = Join-Path -Path ([Environment]::GetFolderPath("Desktop")) -ChildPath $TargetFolderName
if (!(Test-Path $TargetFolderPath)) { New-Item -Path $TargetFolderPath -ItemType Directory | Out-Null }

# Statut des Agents (Colonnes dédiées dans le CSV)
$AgentsMap = @{ "S1"="SentinelAgent"; "UWM"="EmUser"; "FD"="FileDirector"; "FP"="DLPScanner" }
$AgentStatusObj = @{}
foreach ($A in $AgentsMap.Keys) {
    $State = if (Get-Process $AgentsMap[$A] -ErrorAction SilentlyContinue) { "ON" } else { "OFF" }
    $AgentStatusObj.Add($A, $State)
}

$Results = @()

# --- 4. EXÉCUTION DES TESTS ---

# [A] LANCEMENT APPS (COLD START + STOPWATCH)
Write-Host "`n--- [1/4] LANCEMENT APPS (COLD START) ---" -ForegroundColor Yellow
foreach ($AppName in $AppsToBench.Keys) {
    $ExeName = $AppsToBench[$AppName]
    Get-Process $ExeName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    
    Write-Host " -> Bench : $AppName..." -NoNewline -ForegroundColor Cyan
    $SW = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $p = Start-Process $ExeName -PassThru -WindowStyle Minimized -ErrorAction SilentlyContinue
        $null = $p.WaitForInputIdle(15000)
        $SW.Stop()
        $val = [math]::Round($SW.Elapsed.TotalSeconds, 2)
        Write-Host " Terminé en $val sec" -ForegroundColor Green
        Start-Sleep -Seconds 5 # Monitoring EDR post-lancement (non compté)
        Stop-Process $p -Force -ErrorAction SilentlyContinue
    } catch { $val = 0 ; Write-Host " Erreur" -ForegroundColor Red }
    
    $Results += [PSCustomObject]@{ Test="Launch_$AppName"; Sec=$val; Base=$Baselines["Launch_$AppName"]; Info="Cold Start Stopwatch" }
}

# [B] STRESS REGISTRE
Write-Host "`n--- [2/4] STRESS REGISTRE (10k itérations) ---" -ForegroundColor Yellow
$RegPath = "HKCU:\Software\Bench_Perf_Test"
if (!(Test-Path $RegPath)) { New-Item $RegPath -Force | Out-Null }

$SW_Reg = [System.Diagnostics.Stopwatch]::StartNew()
1..10000 | ForEach-Object {
    $null = New-ItemProperty -Path $RegPath -Name "Val_$_" -Value "Friction_Test" -Force
    $null = Get-ItemProperty -Path $RegPath -Name "Val_$_"
}
$SW_Reg.Stop()
$valReg = [math]::Round($SW_Reg.Elapsed.TotalSeconds, 2)
Write-Host " -> Terminé en $valReg sec" -ForegroundColor Green
$Results += [PSCustomObject]@{ Test="Stress_Registre"; Sec=$valReg; Base=$Baselines["Stress_Registre"]; Info="10k Reg Ops" }
Remove-Item $RegPath -Force -Recurse

# [C] I/O MASSIF ALÉATOIRE & COMPRESSION
Write-Host "`n--- [3/4] I/O MASSIF (10k fichiers 1Ko-1Mo) ---" -ForegroundColor Yellow
$WorkPath = "$env:LOCALAPPDATA\Bench_V17"
$ZipPath  = "$env:LOCALAPPDATA\Bench_Archive.zip"
if (Test-Path $WorkPath) { Remove-Item $WorkPath -Recurse -Force }
New-Item $WorkPath -ItemType Directory | Out-Null

$SW_IO = [System.Diagnostics.Stopwatch]::StartNew()
$Rand = New-Object System.Random
1..10000 | ForEach-Object {
    $Buffer = New-Object Byte[] ($Rand.Next(1KB, 1MB))
    $Rand.NextBytes($Buffer)
    [System.IO.File]::WriteAllBytes("$WorkPath\f$_.tmp", $Buffer)
    if ($_ % 2000 -eq 0) { Write-Host "    -> $_ fichiers créés..." -ForegroundColor Gray }
}
$SW_IO.Stop()
$valIO = [math]::Round($SW_IO.Elapsed.TotalSeconds, 2)
Write-Host " -> Écriture terminée en $valIO sec" -ForegroundColor Green
$Results += [PSCustomObject]@{ Test="Ecriture_10k_Random"; Sec=$valIO; Base=$Baselines["Ecriture_10k_Files"]; Info="10k Files (Max 1MB)" }

Write-Host " -> Compression ZIP en cours..." -ForegroundColor Cyan
$SW_Zip = [System.Diagnostics.Stopwatch]::StartNew()
Compress-Archive -Path "$WorkPath\*" -DestinationPath $ZipPath -Force
$SW_Zip.Stop()
$valZip = [math]::Round($SW_Zip.Elapsed.TotalSeconds, 2)
Write-Host " -> Terminé en $valZip sec" -ForegroundColor Green
$Results += [PSCustomObject]@{ Test="Compression_ZIP"; Sec=$valZip; Base=$Baselines["Compression_ZIP"]; Info="Archivage 10k files" }

# [D] CALCUL SHA512
Write-Host "`n--- [4/4] STRESS HASH SHA512 (500 fichiers) ---" -ForegroundColor Yellow
$SW_Hash = [System.Diagnostics.Stopwatch]::StartNew()
Get-ChildItem $WorkPath | Select-Object -First 500 | ForEach-Object {
    Get-FileHash $_.FullName -Algorithm SHA512 | Out-Null
}
$SW_Hash.Stop()
$valHash = [math]::Round($SW_Hash.Elapsed.TotalSeconds, 2)
Write-Host " -> Terminé en $valHash sec" -ForegroundColor Green
$Results += [PSCustomObject]@{ Test="Stress_SHA512"; Sec=$valHash; Base=$Baselines["Stress_SHA512"]; Info="Hash CPU Intensif" }

# Nettoyage
Remove-Item $WorkPath -Recurse -Force -ErrorAction SilentlyContinue
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue }

# --- 5. EXPORT CSV AVEC HEADERS DÉTAILLÉS ---
$FinalReport = foreach ($R in $Results) {
    $Ratio = if ($R.Base -gt 0) { [math]::Round($R.Sec / $R.Base, 1) } else { 0 }
    [PSCustomObject]@{
        "TIMESTAMP"      = "$DateJour $HeurePrec"
        "HOSTNAME"       = $Hostname
        "CPU_MODEL"      = $CPU
        "TEST_NAME"      = $R.Test
        "DURATION_SEC"   = $R.Sec
        "BASELINE_SEC"   = $R.Base
        "FRICTION_RATIO" = "x$Ratio"
        "S1_STATUS"      = $AgentStatusObj["S1"]
        "UWM_STATUS"     = $AgentStatusObj["UWM"]
        "FD_STATUS"      = $AgentStatusObj["FD"]
        "FP_STATUS"      = $AgentStatusObj["FP"]
        "TEST_INFO"      = $R.Info
    }
}

$FileName = "Audit_V17_$($Hostname)_$($HeurePrec).csv"
$FilePath = Join-Path -Path $TargetFolderPath -ChildPath $FileName
$FinalReport | Export-Csv -Path $FilePath -NoTypeInformation -Delimiter ";" -Encoding UTF8

Write-Host "`n[FIN] Rapport complet généré dans : $FilePath" -ForegroundColor Green
$FinalReport | Format-Table -AutoSize
