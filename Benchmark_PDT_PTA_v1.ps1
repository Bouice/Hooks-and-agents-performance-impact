# ==============================================================================
# DIAGNOSTIC PERF V18 - FORMAT DOUBLE EXPORT & STRESS CPU INTENSIF
# ==============================================================================

# --- 1. CONFIGURATION DES BASES DE REFERENCE ---
# Les mesures sont prises sur le resultat de la machine LP_DEV_W11 qui sert de reference pour calculer l'indice de friction
$Baselines = @{
    "Launch_Chrome"      = 0.34
    "Launch_Edge"        = 0.14
    "Launch_Firefox"     = 0.38
    "Launch_Notepad"     = 0.28
    "Stress_Registre"    = 159.47   
    "Ecriture_10k_Files" = 37.84  
    "Compression_ZIP"    = 250  
    "Stress_SHA512"      = 3.67
}

# --- 2. CONFIGURATION DES EXECUTABLES ---
$AppsToBench = @{ "Chrome"="chrome"; "Edge"="msedge"; "Firefox"="firefox"; "Notepad"="notepad" }

# --- 3. IDENTITE ET DOSSIER DE SORTIE ---
$Hostname  = $env:COMPUTERNAME
$DateJour  = Get-Date -Format "yyyy-MM-dd"
$HeurePrec = Get-Date -Format "HHmm"
$CPU       = (Get-WmiObject Win32_Processor).Name

$TargetFolderName = "Audit_$($Hostname)_$($DateJour)"
$TargetFolderPath = Join-Path -Path ([Environment]::GetFolderPath("Desktop")) -ChildPath $TargetFolderName
if (!(Test-Path $TargetFolderPath)) { New-Item -Path $TargetFolderPath -ItemType Directory | Out-Null }

# Statut des Agents
$AgentsMap = @{ "S1"="SentinelAgent"; "UWM"="EmUser"; "AppControl"="AMAgent";"FD"="DataNow_Service"; "DLP"="fppsvc" }
$AgentStatusObj = @{}
foreach ($A in $AgentsMap.Keys) {
    $State = if (Get-Process $AgentsMap[$A] -ErrorAction SilentlyContinue) { "ON" } else { "OFF" }
    $AgentStatusObj.Add($A, $State)
}

$Results = @()

# --- 4. EXECUTION DES TESTS ---

# [A] LANCEMENT APPS
Write-Host "`n--- [1/4] LANCEMENT APPS ---" -ForegroundColor Yellow
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
        Write-Host " Termine en $val sec" -ForegroundColor Green
        Start-Sleep -Seconds 5 
        Stop-Process $p -Force -ErrorAction SilentlyContinue
    } catch { $val = 0 ; Write-Host " Erreur" -ForegroundColor Red }
    
    $Results += [PSCustomObject]@{ Test="Launch_$AppName"; Sec=$val; Base=$Baselines["Launch_$AppName"] }
}

# [B] STRESS REGISTRE
Write-Host "`n--- [2/4] STRESS REGISTRE (10k ops) ---" -ForegroundColor Yellow
$RegPath = "HKCU:\Software\Bench_Perf_Test"
if (!(Test-Path $RegPath)) { New-Item $RegPath -Force | Out-Null }
$SW_Reg = [System.Diagnostics.Stopwatch]::StartNew()
1..10000 | ForEach-Object {
    $null = New-ItemProperty -Path $RegPath -Name "Val_$_" -Value "Friction_Test" -Force
    $null = Get-ItemProperty -Path $RegPath -Name "Val_$_"
}
$SW_Reg.Stop()
$valReg = [math]::Round($SW_Reg.Elapsed.TotalSeconds, 2)
Write-Host " -> Termine en $valReg sec" -ForegroundColor Green
$Results += [PSCustomObject]@{ Test="Stress_Registre"; Sec=$valReg; Base=$Baselines["Stress_Registre"] }
Remove-Item $RegPath -Force -Recurse

# [C] I/O MASSIF ET COMPRESSION
Write-Host "`n--- [3/4] I/O MASSIF (10k fichiers 1Ko-1Mo) ---" -ForegroundColor Yellow
$WorkPath = "$env:LOCALAPPDATA\Bench_V18"
$ZipPath  = "$env:LOCALAPPDATA\Bench_Archive.zip"
if (Test-Path $WorkPath) { Remove-Item $WorkPath -Recurse -Force }
New-Item $WorkPath -ItemType Directory | Out-Null

$SW_IO = [System.Diagnostics.Stopwatch]::StartNew()
$Rand = New-Object System.Random
1..10000 | ForEach-Object {
    $Buffer = New-Object Byte[] ($Rand.Next(1KB, 1MB))
    $Rand.NextBytes($Buffer)
    [System.IO.File]::WriteAllBytes("$WorkPath\f$_.tmp", $Buffer)
}
$SW_IO.Stop()
$valIO = [math]::Round($SW_IO.Elapsed.TotalSeconds, 2)
Write-Host " -> Ecriture terminee en $valIO sec" -ForegroundColor Green
$Results += [PSCustomObject]@{ Test="Ecriture_10k_Random"; Sec=$valIO; Base=$Baselines["Ecriture_10k_Files"] }

Write-Host " -> Compression ZIP en cours..." -ForegroundColor Cyan
$SW_Zip = [System.Diagnostics.Stopwatch]::StartNew()
Compress-Archive -Path "$WorkPath\*" -DestinationPath $ZipPath -Force
$SW_Zip.Stop()
$valZip = [math]::Round($SW_Zip.Elapsed.TotalSeconds, 2)
Write-Host " -> Termine en $valZip sec" -ForegroundColor Green
$Results += [PSCustomObject]@{ Test="Compression_ZIP"; Sec=$valZip; Base=$Baselines["Compression_ZIP"] }

# [D] STRESS CPU INTENSIF (SHA512 - 2000 fichiers)
Write-Host "`n--- [4/4] STRESS CPU HASH (2000 SHA512) ---" -ForegroundColor Yellow
$SW_Hash = [System.Diagnostics.Stopwatch]::StartNew()
Get-ChildItem $WorkPath | Select-Object -First 2000 | ForEach-Object {
    Get-FileHash $_.FullName -Algorithm SHA512 | Out-Null
}
$SW_Hash.Stop()
$valHash = [math]::Round($SW_Hash.Elapsed.TotalSeconds, 2)
Write-Host " -> Termine en $valHash sec" -ForegroundColor Green
$Results += [PSCustomObject]@{ Test="Stress_SHA512_Intense"; Sec=$valHash; Base=$Baselines["Stress_SHA512"] }

# Nettoyage final
Remove-Item $WorkPath -Recurse -Force -ErrorAction SilentlyContinue
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue }

# --- 5. EXPORT DOUBLE FORMAT ---

# A. Format Standard (Lignes)
$ReportLong = foreach ($R in $Results) {
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
		"APPCONTROL_STATUS" = $AgentStatusObj["AppControl"]	
        "FD_STATUS"      = $AgentStatusObj["FD"]
        "FP_STATUS"      = $AgentStatusObj["FP"]
    }
}
$ReportLong | Export-Csv -Path (Join-Path $TargetFolderPath "Audit_$($Hostname)_$($HeurePrec).csv") -NoTypeInformation -Delimiter ";" -Encoding UTF8

# B. Format RAW (Une colonne par test)
$RawData = [ordered]@{
    "TIMESTAMP" = "$DateJour $HeurePrec"
    "HOSTNAME"  = $Hostname
    "CPU"       = $CPU
    "S1"        = $AgentStatusObj["S1"]
    "UWM"       = $AgentStatusObj["UWM"]
	"APPCONTROL"= $AgentStatusObj["AppControl"]	
    "FD"        = $AgentStatusObj["FD"]
    "DLP"        = $AgentStatusObj["DLP"]
}
foreach ($R in $Results) { $RawData.Add($R.Test, $R.Sec) }
[PSCustomObject]$RawData | Export-Csv -Path (Join-Path $TargetFolderPath "RAW_$($Hostname)_$($HeurePrec).csv") -NoTypeInformation -Delimiter ";" -Encoding UTF8

Write-Host "`n[FIN] Rapports generes (Standard et RAW) dans : $TargetFolderName" -ForegroundColor Green
