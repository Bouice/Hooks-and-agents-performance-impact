# ==============================================================================
# LANCEUR USER - EXÉCUTION DU BENCHMARK V18.2
# ==============================================================================
$SignalFile = Join-Path $env:TEMP "bench_signal.txt"
$BenchmarkScript = ".\Benchmark_PDT_V18_2.ps1" # Ton fichier intact

Write-Host "Démarrage de la séquence de tests..." -ForegroundColor Green

# On boucle 5 fois (pour les 5 états définis côté Admin)
for ($i=1; $i -le 5; $i++) {
    Write-Host "`n--- Attente du signal Admin pour le Run $i ---" -ForegroundColor Cyan
    
    # 1. Attente que l'Admin dise "READY"
    while (!(Test-Path $SignalFile)) { Start-Sleep -Seconds 1 }
    
    # 2. Exécution du benchmark réel
    Write-Host "Signal reçu. Lancement du benchmark..." -ForegroundColor Yellow
    & $BenchmarkScript
    
    # 3. On supprime le signal pour dire à l'Admin de passer à la suite
    Remove-Item $SignalFile -ErrorAction SilentlyContinue
    Write-Host "Run $i terminé. Signal envoyé à l'Admin." -ForegroundColor Green
}

Write-Host "`n[FIN] Tous les tests sont terminés." -ForegroundColor Magenta
