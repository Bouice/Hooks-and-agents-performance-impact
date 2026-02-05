# ==============================================================================
# DIAGNOSTIC PERF V16 - DOSSIER DE SORTIE ORGANISÉ
# ==============================================================================

# --- 1. CONFIGURATION DES BASES DE RÉFÉRENCE ---
$Baselines = @{
    "Launch_Chrome"      = 2.5
    "Launch_Edge"        = 2.0
    "Launch_Firefox"     = 2.5
    "Launch_Notepad"     = 1.0
    "Stress_Registre"    = 8.0   
    "Ecriture_10k_Files" = 15.0  
    "Compression_ZIP"    = 12.0  
    "Stress_SHA512"      = 10.0  
}

# --- 2. CONFIGURATION DES EXÉCUTABLES ---
$AppsToBench = @{
    "Chrome"   = "chrome"
    "Edge"     = "msedge"
    "Firefox"  = "firefox"
    "Notepad"  = "notepad"
}

# --- 3. IDENTITÉ ET CRÉATION DU DOSSIER DE SORTIE ---
$Hostname  = $env:COMPUTERNAME
$DateJour  = Get-Date -Format "yyyy-MM-dd"
$HeurePrec = Get-Date -Format "HHmm"
$CPU       = (Get-WmiObject Win32_Processor).Name

# Dossier cible sur le bureau : "Audit_HOSTNAME_DATE"
$TargetFolderName = "Audit_$($Hostname)_$($DateJour)"
$TargetFolderPath = Join-Path -Path ([Environment]::GetFolderPath("Desktop")) -ChildPath $TargetFolderName

if (!(Test-Path $TargetFolderPath)) {
    New-Item -Path $TargetFolderPath -ItemType Directory | Out-Null
    Write-Host "Dossier cree : $TargetFolderName" -ForegroundColor Green
}

# État des Agents
$AgentsMap = @{ "S1"="SentinelAgent"; "UWM"="EmUser"; "FD"="FileDirector"; "FP"="DLPScanner" }
$StatusList = foreach ($A in $AgentsMap.Keys) {
    $State = if (Get-Process $AgentsMap[$A] -ErrorAction SilentlyContinue) { "ON" } else { "OFF" }
    "$A=$State"
}
$FinalStatus = $StatusList -join " / "

$Results = @()

# --- 4. EXÉCUTION DES TESTS ---

# [A] LANCEMENT APPS (MÉTHODE STOPWATCH PRÉCISE)
Write-Host "`n--- [1/4] LANCEMENT APPS (COLD START) ---" -ForegroundColor Yellow
foreach ($AppName in $AppsToBench.Keys) {
    $ExeName = $AppsToBench[$AppName]
    
    # 1. Nettoyage complet
    Get-Process $ExeName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    
    Write-Host " -> Bench : $AppName" -ForegroundColor Cyan
    
    # 2. Démarrage du Chronomètre de précision
    $SW = [System.Diagnostics.Stopwatch]::StartNew()
    
    try {
        $p = Start-Process $ExeName -PassThru -WindowStyle Minimized -ErrorAction SilentlyContinue
        
        # On attend que l'interface soit prête (Signal OS)
        $null = $p.WaitForInputIdle(15000)
        
        # ARRÊT DU CHRONO ici pour capturer le ressenti de lancement réel
        $SW.Stop()
        $LaunchDuration = [math]::Round($SW.Elapsed.TotalSeconds, 2)
        
        # 3. Phase de monitoring (On laisse l'EDR travailler pendant 5s sans compter ce temps)
        Start-Sleep -Seconds 5
        Stop-Process $p -Force -ErrorAction SilentlyContinue
        
    } catch {
        $LaunchDuration = 0
    }
    
    # On enregistre uniquement le temps de lancement pur dans le CSV
    $Results += [PSCustomObject]@{ 
        Test = "Launch_$AppName"; 
        Sec  = $LaunchDuration; 
        Base = $Baselines["Launch_$AppName"]; 
        Info = "Cold Start (Stopwatch)" 
    }
}
# [B] STRESS REGISTRE
Write-Host "`n--- [2/4] STRESS REGISTRE ---" -ForegroundColor Yellow
$RegPath = "HKCU:\Software\Bench_Perf_Test"
if (!(Test-Path $RegPath)) { New-Item $RegPath -Force | Out-Null }
$T_Reg = Measure-Command {
    1..10000 | ForEach-Object {
        $null = New-ItemProperty -Path $RegPath -Name "Val_$_" -Value "Friction" -Force
        $null = Get-ItemProperty -Path $RegPath -Name "Val_$_"
    }
}
$Results += [PSCustomObject]@{ Test="Stress_Registre"; Sec=[math]::Round($T_Reg.TotalSeconds, 2); Base=$Baselines["Stress_Registre"]; Info="10k Reg Ops" }
Remove-Item $RegPath -Force -Recurse

# [C] I/O & COMPRESSION
Write-Host "`n--- [3/4] I/O & COMPRESSION ---" -ForegroundColor Yellow
$WorkPath = "$env:LOCALAPPDATA\Bench_V16"
$ZipPath  = "$env:LOCALAPPDATA\Bench_Archive.zip"
if (Test-Path $WorkPath) { Remove-Item $WorkPath -Recurse -Force }
New-Item $WorkPath -ItemType Directory | Out-Null

$T_Write = Measure-Command {
    1..10000 | ForEach-Object { "Stress Data" | Out-File "$WorkPath\f$_.tmp" -Encoding ascii }
}
$Results += [PSCustomObject]@{ Test="Ecriture_10k_Files"; Sec=[math]::Round($T_Write.TotalSeconds, 2); Base=$Baselines["Ecriture_10k_Files"]; Info="10k Files" }

$T_Zip = Measure-Command {
    Compress-Archive -Path "$WorkPath\*" -DestinationPath $ZipPath -Force
}
$Results += [PSCustomObject]@{ Test="Compression_ZIP"; Sec=[math]::Round($T_Zip.TotalSeconds, 2); Base=$Baselines["Compression_ZIP"]; Info="ZIP 10k files" }

# [D] CALCUL SHA512
Write-Host "`n--- [4/4] STRESS HASH ---" -ForegroundColor Yellow
$T_Hash = Measure-Command {
    Get-ChildItem $WorkPath | Select-Object -First 500 | ForEach-Object {
        Get-FileHash $_.FullName -Algorithm SHA512 | Out-Null
    }
}
$Results += [PSCustomObject]@{ Test="Stress_SHA512"; Sec=[math]::Round($T_Hash.TotalSeconds, 2); Base=$Baselines["Stress_SHA512"]; Info="Hash SHA512" }

# NETTOYAGE
Remove-Item $WorkPath -Recurse -Force -ErrorAction SilentlyContinue
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue }

# --- 5. COMPILATION ET EXPORT ---
$FinalReport = foreach ($R in $Results) {
    $Ratio = if ($R.Base -gt 0) { [math]::Round($R.Sec / $R.Base, 1) } else { 0 }
    [PSCustomObject]@{
        Date           = "$DateJour $HeurePrec"
        Machine        = $Hostname
        CPU            = $CPU
        Test           = $R.Test
        Resultat_Sec   = $R.Sec
        Baseline_Sec   = $R.Base
        Ratio_Friction = "x$Ratio"
        Agents_State   = $FinalStatus
    }
}

$FileName = "Audit_$($Hostname)_$($HeurePrec).csv"
$FilePath = Join-Path -Path $TargetFolderPath -ChildPath $FileName

$FinalReport | Format-Table -AutoSize
$FinalReport | Export-Csv -Path $FilePath -NoTypeInformation -Delimiter ";" -Encoding UTF8

Write-Host "`nRapport genere : $FilePath" -ForegroundColor Green
