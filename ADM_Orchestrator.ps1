# ==============================================================================
# ORCHESTRATEUR ADMIN - GESTION DES SERVICES IVANTI
# ==============================================================================
$SignalFile = Join-Path $env:TEMP "bench_signal.txt"
$Svc = @{ AC="AmAgent"; UWM="EmCoreService"; FD="FileDirectorService" }

function Set-AllOn {
    Write-Host "[+] Restauration : Tout à ON" -ForegroundColor Gray
    foreach($s in $Svc.Values) { 
        Set-Service $s -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service $s -ErrorAction SilentlyContinue 
    }
}

# Séquence : Ce qu'on veut ÉTEINDRE pour chaque Run
$Sequence = @(
    @{ Name="RUN1_FULL_STACK"; OFF=@() },
    @{ Name="RUN2_NO_APPCO";   OFF=@($Svc.AC) },
    @{ Name="RUN3_NO_UWM";     OFF=@($Svc.UWM) },
    @{ Name="RUN4_NO_FD";      OFF=@($Svc.FD) },
    @{ Name="RUN5_UWM_OFF_AC_ON"; OFF=@($Svc.UWM) }
)

try {
    Set-AllOn
    foreach ($Step in $Sequence) {
        Write-Host "`n>>> Préparation : $($Step.Name)" -ForegroundColor Yellow
        
        # 1. État des lieux : Tout ON puis on coupe la cible
        Set-AllOn
        foreach ($target in $Step.OFF) { 
            Stop-Service $target -Force -ErrorAction SilentlyContinue
            Set-Service $target -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Host "[-] $target mis à OFF" -ForegroundColor Red
        }

        # 2. On attend la stabilisation des drivers (Fltmc)
        Start-Sleep -Seconds 5
        
        # 3. On crée le signal pour le script User
        "READY" | Out-File $SignalFile

        # 4. On attend que l'User finisse (il supprimera le fichier)
        Write-Host "En attente du benchmark utilisateur..." -ForegroundColor Cyan
        while (Test-Path $SignalFile) { Start-Sleep -Seconds 1 }
    }
} finally {
    Set-AllOn
    if (Test-Path $SignalFile) { Remove-Item $SignalFile }
    Write-Host "`n[FIN] Séquence terminée. Système restauré." -ForegroundColor Magenta
}
