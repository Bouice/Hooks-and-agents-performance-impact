# ==============================================================================
# LANCEUR USER - EXeCUTION DU BENCHMARK V18.2
# ==============================================================================
$SignalFile = "C:/Applications/bench_signal.txt"
$BenchmarkScript = ".\ReturnTrue.ps1"

# --- BLOC ANTI-VERROUILLAGE ---
$KeepAliveScript = {
    $wsh = New-Object -ComObject WScript.Shell
    while($true) {
        $wsh.SendKeys('{F15}') # Touche virtuelle inoffensive
        Start-Sleep -Seconds 50 # Doit être inférieur au timeout GPO
    }
}
$KeepAliveJob = Start-Job -ScriptBlock $KeepAliveScript
#--------------------------------

Write-Host "[!] Anti-verrouillage actif (Job ID: $($KeepAliveJob.Id))" -ForegroundColor Yellow
Write-Host "Demarrage de la sequence de tests..." -ForegroundColor Green

try {
    # On boucle 6 fois (pour les 6 etats definis côte Admin)
    for ($i=1; $i -le 6; $i++) {
        Write-Host "`n--- Attente du signal Admin pour le Run $i ---" -ForegroundColor Cyan
        
        # 1. Attente que l'Admin dise "READY"
        while (!(Test-Path $SignalFile)) { Start-Sleep -Seconds 1 }
        
        # 2. Execution du benchmark reel
        Write-Host "Signal recu. Lancement du benchmark..." -ForegroundColor Yellow
        & $BenchmarkScript
        
        # 3. On supprime le signal pour dire a l'Admin de passer a la suite
        Remove-Item $SignalFile -ErrorAction SilentlyContinue
        Write-Host "Run $i termine. Signal envoye a l'Admin." -ForegroundColor Green
    }
} finally {
# --- ARRET DU KEEP-ALIVE ---
    Stop-Job $KeepAliveJob
    Remove-Job $KeepAliveJob
    Write-Host "`n[!] Anti-verrouillage desactive." -ForegroundColor Yellow

}

Write-Host "`n[FIN] Tous les tests sont termines." -ForegroundColor Magenta
