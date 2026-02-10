# ==============================================================================
# ORCHESTRATEUR ADMIN - GESTION DES SERVICES IVANTI
# ==============================================================================
$SignalFile = "C:/Applications/bench_signal.txt"
$Svc = @{ AppControl="AppSense Application Manager Agent"; UWM="AppSense EmCoreService"; FD="DataNow_Service" }

function Set-AllOn {
    Write-Host "[+] Restauration : Tout a ON" -ForegroundColor Blue
    foreach($s in $Svc.Values) { 
        Set-Service $s -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service $s -ErrorAction SilentlyContinue 
    }
}

# Sequence : Ce qu'on veut eteindre pour chaque Run
$Sequence = @(
    @{ Name="Benchmark 1 : Tous services actifs"; OFF=@() },
    @{ Name="Benchmark 2 : Application Control Desactive";   OFF=@($Svc.AppControl) },
    @{ Name="Benchmark 3 : UWM Desactive";     OFF=@($Svc.UWM) },
    @{ Name="Benchmark 4 : File Director Desactive";      OFF=@($Svc.FD) },
    @{ Name="Benchmark 5 : UWM Reactive"; ON=@($Svc.UWM) },
	@{ Name="Benchmark 6 : UWM + AppControl Reactive"; ON=@($Svc.AppControl) }
)

try {
    foreach ($Step in $Sequence) {
        Write-Host "`n---> Preparation : $($Step.Name)" -ForegroundColor Yellow
        
        # 1. etat des lieux : Tout ON puis on coupe la cible
        foreach ($target in $Step.OFF) { 
            Stop-Service $target -Force -ErrorAction SilentlyContinue
            Set-Service $target -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Host "[-] $target mis a OFF" -ForegroundColor Red
        }
		foreach ($target in $Step.ON) { 
            Set-Service $target -StartupType Automatic -ErrorAction SilentlyContinue
			Start-Service $target
            Write-Host "[+] $target mis a ON" -ForegroundColor Blue
        }

        # 2. On attend la stabilisation des drivers (Fltmc)
        Start-Sleep -Seconds 20
        
        # 3. On cree le signal pour le script User
        "READY" | Out-File $SignalFile

        # 4. On attend que l'User finisse (il supprimera le fichier)
        Write-Host "En attente du benchmark utilisateur..." -ForegroundColor Cyan
        while (Test-Path $SignalFile) { Start-Sleep -Seconds 1 }
    }
} finally {
    Set-AllOn
    if (Test-Path $SignalFile) { Remove-Item $SignalFile }
    Write-Host "`n[FIN] Sequence terminee. Systeme restaure." -ForegroundColor Magenta
}
