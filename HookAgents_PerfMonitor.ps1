<#
.SYNOPSIS
    Super-Script de Diagnostic de Performance pour Environnements Durcis.
    Analyse l'impact de SentinelOne, Ivanti, ForcePoint et Flexera.
#>

$Results = @()
$ReportPath = "$PSScriptRoot\Rapport_Diagnostic_Global.csv"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   BENCHMARK GLOBAL : PERFORMANCE POSTE DE TRAVAIL       " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Ce test va simuler une activité utilisateur intense." -ForegroundColor Gray

# --- 1. TEST DE LATENCE D'OUVERTURE D'APPLICATIONS (COLD START) ---
Write-Host "`n[1/4] Mesure de la latence d'ouverture (App Launch)..." -ForegroundColor Yellow
$Apps = @("msedge.exe", "notepad.exe", "explorer.exe")
foreach ($App in $Apps) {
    $Time = Measure-Command {
        $Proc = Start-Process $App -PassThru -WindowStyle Minimized
        # Attend que l'app soit prête (Wait For Input Idle)
        $Idle = $Proc.WaitForInputIdle(15000)
        Stop-Process $Proc -Force
    }
    $Results += [PSCustomObject]@{ Categorie = "Latence App"; Test = "Ouverture $App"; Valeur_Sec = [math]::Round($Time.TotalSeconds, 3); Unite = "Secondes" }
}

# --- 2. TEST DE RÉACTIVITÉ DE L'INTERFACE & REGISTRE (HOOKS UWM/DLP) ---
Write-Host "[2/4] Test de réactivité Registry & Shell (Impact Hooks)..." -ForegroundColor Yellow
$RegTime = Measure-Command {
    $Path = "HKCU:\Software\DiagnosticPerformance"
    New-Item $Path -Force | Out-Null
    1..2000 | ForEach-Object { 
        Set-ItemProperty -Path $Path -Name "Entry$_" -Value "Data_Audit_Value_Test_Performance"
        $null = Get-ItemProperty -Path $Path -Name "Entry$_"
    }
    Remove-Item $Path -Recurse -Force
}
$Results += [PSCustomObject]@{ Categorie = "Réactivité UI"; Test = "Stress-Test Registre (2000 ops)"; Valeur_Sec = [math]::Round($RegTime.TotalSeconds, 3); Unite = "Secondes" }

# --- 3. TEST DE FILTRAGE I/O (IMPACT EDR/DLP/FILE DIRECTOR) ---
Write-Host "[3/4] Test de filtrage fichiers (Impact Mini-Filters)..." -ForegroundColor Yellow
$IOTime = Measure-Command {
    $TempFolder = "$env:TEMP\BenchAudit"
    New-Item $TempFolder -ItemType Directory -Force | Out-Null
    # Création + Ecriture
    1..1000 | ForEach-Object { 
        "Contenu de test pour inspection DLP et EDR" | Out-File "$TempFolder\file_$_.txt"
    }
    # Lecture (Force le scan on-access)
    Get-ChildItem $TempFolder | Get-Content | Out-Null
    Remove-Item $TempFolder -Recurse -Force
}
$Results += [PSCustomObject]@{ Categorie = "Filtrage I/O"; Test = "Cycle Vie 1000 fichiers"; Valeur_Sec = [math]::Round($IOTime.TotalSeconds, 3); Unite = "Secondes" }

# --- 4. EXTRACTION DES STATISTIQUES KERNEL (FLTMC) ---
Write-Host "[4/4] Analyse des drivers de filtrage (Bas niveau)..." -ForegroundColor Yellow
$FltStats = fltmc statistics | Out-String
$Drivers = @("S1Core", "fnefilter", "AsFilter", "FileDirector", "Sentinel")
foreach ($D in $Drivers) {
    if ($FltStats -match "$D") {
        Write-Host " -> Driver $D détecté avec une charge active." -ForegroundColor Green
    }
}

# --- AFFICHAGE ET EXPORT ---
Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "                SYNTHÈSE DES RÉSULTATS                    " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green

$Results | Format-Table -AutoSize
$Results | Export-Csv -Path $ReportPath -NoTypeInformation -Delimiter ";"

Write-Host "`nLe rapport complet a été enregistré ici : $ReportPath" -ForegroundColor White
Write-Host "CONSEIL : Si 'Ouverture msedge.exe' > 4s, vérifiez le conflit S1 / Forcepoint." -ForegroundColor Gray
