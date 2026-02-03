# ==============================================================================
# SCRIPT DE DIAGNOSTIC DE PERFORMANCE GLOBAL - V5
# Cibles : SentinelOne, Ivanti, ForcePoint, Flexera
# Focus : AppData, SHA256, Registre, Apps
# ==============================================================================

$Results = @()
$ReportPath = "$HOME\Desktop\Rapport_Performance_Final.csv"

Write-Host "--- Preparation de l'environnement ---" -ForegroundColor Cyan
$AppsToTest = @{
    "Edge"    = "msedge"
    "Chrome"  = "chrome"
    "Firefox" = "firefox"
    "Notepad" = "notepad"
}

# 1. NETTOYAGE : Fermeture des apps pour garantir un "Cold Start"
Write-Host "Fermeture des processus pour test Cold Start..." -ForegroundColor Gray
foreach ($processName in $AppsToTest.Values) {
    Get-Process $processName -ErrorAction SilentlyContinue | Stop-Process -Force
}
Start-Sleep -Seconds 2

Write-Host "--- Demarrage des tests (Resultats en secondes) ---" -ForegroundColor Yellow

# TEST 1 : Latence d'ouverture des navigateurs (Injection Hooks)
foreach ($appName in $AppsToTest.Keys) {
    $exe = $AppsToTest[$appName]
    Write-Host "Mesure du lancement : $appName..." -ForegroundColor White
    try {
        $Time = Measure-Command {
            $Proc = Start-Process $exe -PassThru -WindowStyle Minimized -ErrorAction Stop
            $null = $Proc.WaitForInputIdle(20000)
            Stop-Process $Proc -Force
        }
        $Results += [PSCustomObject]@{ Categorie = "App Launch"; Test = "Ouverture $appName"; Valeur_Sec = [math]::Round($Time.TotalSeconds, 4) }
    } catch {
        Write-Host "   [!] $appName non trouve ou erreur de lancement." -ForegroundColor Red
    }
}

# TEST 2 : I/O Intensif dans AppData\Local (Cible: File Director / S1 / DLP)
$TestPath = "$env:LOCALAPPDATA\Bench_FD_Test"
if (!(Test-Path $TestPath)) { New-Item -Path $TestPath -ItemType Directory -Force | Out-Null }

Write-Host "Mesure I/O dans AppData Local (2500 cycles)..." -ForegroundColor White
$IOTime = Measure-Command {
    1..2500 | ForEach-Object { 
        "Donnees de test pour analyse de performance AppData - ID $_" | Out-File "$TestPath\audit_$_.tmp" -Encoding ascii
    }
    $null = Get-ChildItem $TestPath | Get-Content
}
$Results += [PSCustomObject]@{ Categorie = "File System"; Test = "I/O AppData (FD Hooking)"; Valeur_Sec = [math]::Round($IOTime.TotalSeconds, 4) }

# TEST 3 : Calcul SHA256 (Cible: Inspection profonde EDR/DLP)
Write-Host "Mesure Calcul SHA256 (Scan intensif)..." -ForegroundColor White
$SHATime = Measure-Command {
    # On calcule le hash de 100 fichiers generes precedemment
    Get-ChildItem $TestPath | Select-Object -First 100 | ForEach-Object {
        Get-FileHash $_.FullName -Algorithm SHA256 | Out-Null
    }
}
$Results += [PSCustomObject]@{ Categorie = "CPU/Security"; Test = "Calcul SHA256 (100 fichiers)"; Valeur_Sec = [math]::Round($SHATime.TotalSeconds, 4) }

# Nettoyage des fichiers temporaires
Remove-Item "$TestPath\*" -Force
Remove-Item $TestPath -Recurse -Force

# TEST 4 : Stress Registre (Cible: Ivanti UWM / Personnalisation)
Write-Host "Mesure Reactivite Registre (5000 iterations)..." -ForegroundColor White
$RegTime = Measure-Command {
    $path = "HKCU:\Software\Benchmark_Audit"
    if (!(Test-Path $path)) { New-Item $path | Out-Null }
    1..5000 | ForEach-Object { 
        Set-ItemProperty -Path $path -Name "Key_$_" -Value "Data_Value_$_"
        $null = Get-ItemProperty -Path $path -Name "Key_$_"
    }
    Remove-Item $path -Recurse -Force
}
$Results += [PSCustomObject]@{ Categorie = "Interface/Registry"; Test = "Stress Registre (UWM)"; Valeur_Sec = [math]::Round($RegTime.TotalSeconds, 4) }

# AFFICHAGE
Write-Host "`n--- RESULTATS FINAUX ---" -ForegroundColor Green
$Results | Format-Table -AutoSize
$Results | Export-Csv -Path $ReportPath -NoTypeInformation -Delimiter ";"
Write-Host "Rapport exporte sur le bureau : $ReportPath" -ForegroundColor Cyan
