# Recommandations Techniques : Optimisation de la Friction Security Stack

## 1. Constatations sur la Friction Ivanti (AppControl & UWM)
L'analyse des donnees brutes demontre que le cumul des drivers Ivanti est le facteur limitant principal :
* **Latence de lancement** : Le passage de Chrome de **3,25s** (AppControl seul) a **16,26s** (AppControl + UWM) indique une contention majeure.
* **Conflit d'interception** : Les drivers semblent se scruter mutuellement, creant une boucle de verification a chaque chargement de DLL.

### Actions recommandees :
* **Exclusions mutuelles** : Configurer des exclusions de processus croisees entre les agents. Le driver `AmFileSystemFilter` ne doit pas inspecter l'activite du driver `EmDriver` et vice-versa.
* **Optimisation des Hooks** : Reduire la profondeur de l'analyse comportementale d'AppControl pour les applications deja signees et de confiance (Navigateurs, Office).



## 2. Gestion de la Concurrence (Stress Registre)
Les donnees sur le poste **L2074** (Teams ouvert + TaskMgr) montrent un bond du temps de registre de **311s a 428s**.
* **Saturation I/O** : La stack de securite ne parvient pas a gerer efficacement la file d'attente (Queue Depth) lorsque plusieurs applications a haute frequence de lecture/ecriture (Teams) sont actives.

### Actions recommandees :
* **Profilage UWM** : Desactiver la virtualisation du registre pour les cles temporaires de Teams et des outils de monitoring.
* **Priority I/O** : Ajuster la priorite des processus de benchmark ou des applications metier pour eviter qu'ils ne soient bloques par le balayage des agents en arriere-plan.

## 3. Analyse du DLP et de l'EDR
Les tests montrent que **SentinelOne (S1)** et **Forcepoint (DLP)** ont un impact marginal sur le temps de lancement applicatif par rapport a Ivanti.
* **S1 Transparent** : En l'absence des drivers Ivanti, les temps de lancement retombent a **0,2s** (niveau Baseline VM), prouvant que S1 est parfaitement optimise.

### Actions recommandees :
* **DLP Content Inspection** : Maintenir la configuration actuelle car elle n'est pas le goulot d'etranglement principal de l'UX (User Experience).

## 4. Synthese pour la DSI
Le materiel recent (**Intel Core Ultra 5**) est bride par la couche logicielle. 
1. **Priorite 1** : Rationaliser l'usage combine d'AppControl et UWM.
2. **Priorite 2** : Valider les regles d'exclusion mutuelle pour retrouver un temps de lancement "Cold Start" inferieur a 2 secondes.
