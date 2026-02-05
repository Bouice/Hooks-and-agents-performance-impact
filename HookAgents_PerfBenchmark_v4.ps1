# ==============================================================================
# DIAGNOSTIC PERF V14 - ÉDITION FINALE AVEC RATIO DE FRICTION
# ==============================================================================

# --- 1. CONFIGURATION DES BASES DE RÉFÉRENCE (À ajuster selon vos tests sur PC nu) ---
$Baselines = @{
    "Launch_Chrome"      = 2.5
    "Launch_Edge"        = 2.0
    "Launch_Firefox"     = 2.5
    "Launch_Notepad"     = 1.0
    "Stress_Registre"    = 8.0   # Référence pour 10k entrées
    "Ecriture_10k_Files" = 15.0  # Référence création fichiers
    "Compression_ZIP"    = 12.0  # Référence archivage
    "Stress_SHA512"      = 10.0  # Référence calcul hash
}

# --- 2. CONFIGURATION DES EXÉCUTABLES ---
$AppsToBench = @{
    "Chrome"   = "chrome"
    "Edge"     = "msedge"
    "Firefox"  = "firefox"
    "Notepad"  = "notepad"
}

# --- 3. IDENTITÉ ET ÉTAT ---
$Hostname = $env:COMPUTERNAME
$Date     = Get-Date -Format "dd-MM-yyyy_HHmm"
$CPU      = (Get-WmiObject Win32_Processor).Name

$AgentsMap = @{ "S1"="SentinelAgent"; "UWM"="EmUser"; "FD"="FileDirector"; "FP"="DLPScanner" }
$StatusList = foreach ($A in $AgentsMap.Keys) {
    $State = if (Get-Process $AgentsMap[$A] -ErrorAction SilentlyContinue) { "ON" } else { "OFF" }
    "$A=$State"
}
$FinalStatus = $StatusList -join " / "

$Results = @()

# --- 4. EXÉCUTION DES TESTS ---

# [A] LANCEMENT APPS
Write-Host "`n--- [1/4] LANCEMENT APPS ---" -ForegroundColor Yellow
foreach ($AppName in $AppsToBench.Keys) {
    Write-Host " -> Bench : $AppName" -ForegroundColor Cyan
    $T = Measure-Command {
        try {
            $p = Start-Process $AppsToBench[$AppName] -PassThru -WindowStyle Minimized -ErrorAction SilentlyContinue
            $null = $p.WaitForInputIdle(15000)
            Start-Sleep -Seconds 5
            Stop-Process $p -Force -ErrorAction SilentlyContinue
        } catch { }
    }
    $val = [math]::Round($T.TotalSeconds, 2)
    $base = $Baselines["Launch_$AppName"]
    $Results += [PSCustomObject]@{ Test="Launch_$AppName"; Sec=$val; Base=$base; Info="Ouverture + 5s" }
}

# [B] STRESS REGISTRE
Write-Host "`n--- [2/4] STRESS REGISTRE (10k itérations) ---" -ForegroundColor Yellow
$RegPath = "HKCU:\Software\Bench_Perf_Test"
if (!(Test-Path $RegPath)) { New-Item $RegPath -Force | Out-Null }

$T_Reg = Measure-Command {
    1..10000 | ForEach-Object {
        $null = New-ItemProperty -Path $RegPath -Name "Val_$_" -Value "Friction_Test" -Force
        $null = Get-ItemProperty -Path $RegPath -Name "Val_$_"
    }
}
$val = [math]::Round($T_Reg.TotalSeconds, 2)
$Results += [PSCustomObject]@{ Test="Stress_Registre"; Sec=$val; Base=$Baselines["Stress_Registre"]; Info="10k Write/Read HKCU" }
Remove-Item $RegPath -Force -Recurse

# [C] I/O MASSIF & COMPRESSION
Write-Host "`n--- [3/4] I/O & COMPRESSION (10k fichiers) ---" -ForegroundColor Yellow
$WorkPath = "$env:LOCALAPPDATA\Heavy_Stress_V14"
$ZipPath  = "$env:LOCALAPPDATA\Heavy_Stress_Archive.zip"
if (!(Test-Path $WorkPath)) { New-Item $WorkPath -ItemType Directory | Out-Null }

$T_Write = Measure-Command {
    1..10000 | ForEach-Object { "Donnees de stress" | Out-File "$WorkPath\f$_.tmp" -Encoding ascii }
}
$Results += [PSCustomObject]@{ Test="Ecriture_10k_Files"; Sec=[math]::Round($T_Write.TotalSeconds, 2); Base=$Baselines["Ecriture_10k_Files"]; Info="Création fichiers" }

$T_Zip = Measure-Command {
    Compress-Archive -Path "$WorkPath\*" -DestinationPath $ZipPath -Force
}
$Results += [PSCustomObject]@{ Test="Compression_ZIP"; Sec=[math]::Round($T_Zip.TotalSeconds, 2); Base=$Baselines["Compression_ZIP"]; Info="Archivage 10k fichiers" }

# [D] CALCUL SHA512
Write-Host "`n--- [4/4] STRESS HASH SHA512 (500 fichiers) ---" -ForegroundColor Yellow
$T_Hash = Measure-Command {
    Get-ChildItem $WorkPath | Select-Object -First 500 | ForEach-Object {
        Get-FileHash $_.FullName -Algorithm SHA512 | Out-Null
    }
}
$Results += [PSCustomObject]@{ Test="Stress_SHA512"; Sec=[math]::Round($T_Hash.TotalSeconds, 2); Base=$Baselines["Stress_SHA512"]; Info="Hash SHA512" }

Remove-Item $WorkPath -Recurse -Force
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }

# --- 5. COMPILATION DU RAPPORT FINAL ---
$FinalReport = foreach ($R in $Results) {
    $Ratio = if ($R.Base -gt 0) { [math]::Round($R.Sec / $R.Base, 1) } else { 0 }
    [PSCustomObject]@{
        Date           = $Date
        Machine        = $Hostname
        CPU            = $CPU
        Test           = $R.Test
        Resultat_Sec   = $R.Sec
        Baseline_Sec   = $R.Base
        Ratio_Friction = "x$Ratio"
        Description    = $R.Info
        Agents_State   = $FinalStatus
    }
}

Write-Host "`n--- RÉSULTATS FINAUX ---" -ForegroundColor Green
$FinalReport | Format-Table -AutoSize
$FinalReport | Export-Csv -Path "$HOME\Desktop\Audit_Complet_$Hostname.csv" -NoTypeInformation -Delimiter ";" -Encoding UTF8
