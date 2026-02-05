# Documentation Technique : Benchmark de Friction Security Stack (V18)

## 1. Objectifs de Mesure
Ce script evalue l'impact de la suite logicielle de securite (EDR, DLP, Indexation) sur les performances du systeme d'exploitation. Il isole la latence introduite par les drivers de filtrage de fichiers et les agents d'analyse comportementale en contexte utilisateur reel (sans privileges administrateur).

## 2. Methodologie de Test Applicatif
La mesure du temps de lancement repose sur la precision du compteur materiel plutot que sur l'horloge systeme standard.

* **Classe de mesure** : `System.Diagnostics.Stopwatch` (.NET).
* **Protocole Cold Start** : 
    1. Identification et fermeture forcee des processus cibles (`Get-Process | Stop-Process -Force`).
    2. Temporisation de 2 secondes pour assurer la cloture des handles systeme et le relachement des ressources par les drivers de securite.
* **Point de mesure (InputIdle)** : La mesure s'arrete des que le thread principal de l'application est pret a recevoir une instruction utilisateur (`WaitForInputIdle`). 
* **Isolation du Monitoring** : Un delai post-mesure de 5 secondes est applique pour capturer l'activite residuelle des agents sans l'inclure dans la donnee de lancement (`DURATION_SEC`).



## 3. Stress Test I/O et Systeme de Fichiers
Le test simule une activite de stockage intensive pour saturer la pile de filtrage des entrees/sorties (I/O stack).

* **Volume de donnees** : 10 000 iterations d'ecriture binaire.
* **Payload Aleatoire** : Chaque fichier possede une entropie unique (`[System.Random]::NextBytes`).
    * **Contournement de cache** : Interdit l'usage des listes de confiance par signature (Hashes).
    * **Saturation DLP** : Force l'inspection de contenu sur chaque flux de donnees cree.
* **Technique d'ecriture** : Appel direct a `[System.IO.File]::WriteAllBytes` pour eliminer l'overhead lie a l'interpreteur de commandes et solliciter directement le driver `NTFS.sys`.



## 4. Stress Test CPU et Analyse (SHA512)
Validation de la capacite de calcul sous contrainte d'inspection.

* **Charge** : 2 000 operations de hachage via l'algorithme SHA512.
* **Mecanique** : Lecture intensive de fichiers non indexes couplee a un algorithme de condensation gourmand en cycles CPU.
* **Indicateur de friction** : Met en evidence la contention lors de l'analyse en temps reel des flux de lecture par les agents de securite.

## 5. Gestion des Donnees et Exports
Le script genere deux structures de donnees distinctes pour faciliter l'analyse post-test :

| Format | Prefixe | Usage |
| :--- | :--- | :--- |
| **Long (Lignes)** | `Audit_` | Ideal pour l'ingestion dans Power BI ou outils de Business Intelligence. |
| **Large (Colonnes)** | `RAW_` | Format pivote (une ligne par poste). Ideal pour la comparaison directe entre machines dans Excel. |

* **Friction Ratio** : Calcule par la formule $Valeur / Baseline$. Un ratio superieur a 2.0 indique une degradation de performance perceptible par l'utilisateur final.
* **Encodage** : UTF-8 (sans BOM) avec delimiteur `;` pour garantir l'interoperabilite sans retraitement.

## 6. Prerequis et Execution
* **Privileges** : Utilisateur Standard (le script ne necessite pas de droits Administrateur).
* **Compatibilite** : PowerShell 5.1+.
* **Sortie** : Creation automatique d'un dossier racine sur le Bureau au format `Audit_HOSTNAME_YYYY-MM-DD`.
