# ==============================================================================
# DIAGNOSTIC PERF V18.1 - EXPORT RAW UNIQUE & APPEND JOURNALIER
# ==============================================================================

# --- 1. CONFIGURATION DES EXECUTABLES ---
$AppsToBench = @{ "Chrome"="chrome"; "Edge"="msedge"; "Firefox"="firefox"; "Notepad"="notepad" }

# --- 2. IDENTITE ET FICHIER DE SORTIE ---
$Hostname  = $env:COMPUTERNAME
$DateJour  = Get-Date -Format "yyyy-MM-dd"
$HeurePrec = Get-Date -Format "HHmm"
$CPU       = (Get-WmiObject Win32_Processor).Name

# Dossier sur le bureau
$TargetFolderName = "Audit_Benchmark_$($DateJour)"
$TargetFolderPath = Join-Path -Path ([Environment]::GetFolderPath("Desktop")) -ChildPath $TargetFolderName
if (!(Test-Path $TargetFolderPath)) { New-Item -Path $TargetFolderPath -ItemType Directory | Out-Null }

# Fichier CSV unique pour la journée
$CsvPath = Join-Path $TargetFolderPath "Benchmark_RAW_$($Hostname)_$($DateJour).csv"

# Statut des Agents
$AgentsMap = @{ "S1"="SentinelAgent"; "UWM"="AppSense EmCoreService"; "AppCo"="AppSense Application Manager Agent"; "FD"="DataNow_Service"; "DLP"="fppsvc" }
$AgentStatusObj = @{}
foreach ($A in $AgentsMap.Keys) {
    $State = if (Get-Service -Name $AgentsMap[$A] -ErrorAction SilentlyContinue) { "ON" } else { "OFF" }
    $AgentStatusObj.Add($A, $State)
}

$Results = @()

# --- 3. EXECUTION DES TESTS ---

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
        Stop-Process -Name $ExeName -Force -ErrorAction SilentlyContinue
    } catch { $val = 0 ; Write-Host " Erreur" -ForegroundColor Red }
    
    $Results += [PSCustomObject]@{ Test="Launch_$AppName"; Sec=$val }
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
$Results += [PSCustomObject]@{ Test="Stress_Registre"; Sec=$valReg }
Remove-Item $RegPath -Force -Recurse

# [C] I/O MASSIF ET COMPRESSION
Write-Host "`n--- [3/4] I/O MASSIF (10k fichiers) ---" -ForegroundColor Yellow
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
$Results += [PSCustomObject]@{ Test="Ecriture_10k_Random"; Sec=$valIO }

Write-Host " -> Compression ZIP..." -ForegroundColor Cyan
$SW_Zip = [System.Diagnostics.Stopwatch]::StartNew()
Compress-Archive -Path "$WorkPath\*" -DestinationPath $ZipPath -Force
$SW_Zip.Stop()
$valZip = [math]::Round($SW_Zip.Elapsed.TotalSeconds, 2)
Write-Host " -> Termine en $valZip sec" -ForegroundColor Green
$Results += [PSCustomObject]@{ Test="Compression_ZIP"; Sec=$valZip }

# [D] STRESS CPU INTENSIF
Write-Host "`n--- [4/4] STRESS CPU HASH (SHA512) ---" -ForegroundColor Yellow
$SW_Hash = [System.Diagnostics.Stopwatch]::StartNew()
Get-ChildItem $WorkPath | Select-Object -First 2000 | ForEach-Object {
    Get-FileHash $_.FullName -Algorithm SHA512 | Out-Null
}
$SW_Hash.Stop()
$valHash = [math]::Round($SW_Hash.Elapsed.TotalSeconds, 2)
Write-Host " -> Termine en $valHash sec" -ForegroundColor Green
$Results += [PSCustomObject]@{ Test="Stress_SHA512_Intense"; Sec=$valHash }

# Nettoyage final
Remove-Item $WorkPath -Recurse -Force -ErrorAction SilentlyContinue
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue }

# --- 4. EXPORT RAW UNIQUE (APPEND) ---

$RawData = [ordered]@{
    "TIMESTAMP" = "$DateJour $HeurePrec"
    "HOSTNAME"  = $Hostname
    "CPU"       = $CPU
    "S1"        = $AgentStatusObj["S1"]
    "UWM"       = $AgentStatusObj["UWM"]
    "AppCo"     = $AgentStatusObj["AppCo"]    
    "FD"        = $AgentStatusObj["FD"]
    "DLP"       = $AgentStatusObj["DLP"]
}

# Ajout des mesures de test dynamiquement
foreach ($R in $Results) { $RawData.Add($R.Test, $R.Sec) }

# Vérification si le fichier existe pour décider d'ajouter l'en-tête ou non
$ExportObj = [PSCustomObject]$RawData
if (Test-Path $CsvPath) {
    # On ajoute la ligne sans réécrire l'en-tête
    $ExportObj | Export-Csv -Path $CsvPath -NoTypeInformation -Delimiter ";" -Encoding UTF8 -Append
} else {
    # Premier run : on crée le fichier avec l'en-tête
    $ExportObj | Export-Csv -Path $CsvPath -NoTypeInformation -Delimiter ";" -Encoding UTF8
}

Write-Host "`n[FIN] Donnees ajoutees au fichier : $CsvPath" -ForegroundColor Green
