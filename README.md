# Audit & Debug : Performance des Endpoints (Security Stack)

Ce document centralise la méthodologie pour identifier et prouver l'impact des agents de sécurité (**SentinelOne**, **Ivanti**, **ForcePoint**, **Flexera**) sur les performances des postes de travail.

---

## 1. Concepts de Mesure

### L'Indice de Friction Logicielle
Sur un matériel moderne (ex: Core i5 Ultra), la lenteur n'est pas due à un manque de puissance, mais à une **saturation de la pile d'interception**.
* **Performance Brute ($P_{raw}$)** : Temps d'exécution sur une image Windows nue.
* **Performance Réelle ($P_{real}$)** : Temps d'exécution avec la stack logicielle complète.
* **Ratio de Friction** : $I = \frac{P_{real}}{P_{raw}}$
    * *Exemple :* Chrome s'ouvre en 2.5s (base) mais prend 20s en prod. **Ratio = x8**. Le logiciel ralentit le matériel de 800%.

---

## 2. Architecture Technique : La Pile "FltMgr"

Le **Filter Manager** de Windows organise les drivers par **Altitudes**. Tout appel système (I/O) traverse cette pile de haut en bas.



* **Antivirus/EDR (S1) :** Altitude ~320 000. Voit tout en premier.
* **DLP (ForcePoint) :** Altitude ~280 000. Inspecte le contenu des flux.
* **Virtualisation/Sync (Ivanti FD) :** Altitude ~180 000. Gère la visibilité des fichiers.

**Le goulot d'étranglement :** Si plusieurs drivers tentent d'analyser le même fichier simultanément, le processeur entre en état de "Context Switching" permanent, ce qui crée une latence perçue par l'utilisateur.

---

## 3. Guide de Debugging (Pour les Techniciens)

### A. Audit via la Ligne de Commande (PowerShell Admin)
1.  **Identifier les drivers chargés :**
    ```powershell
    fltmc instances
    ```
    * *Check :* Vérifier si deux drivers ont des altitudes trop proches.
2.  **Mesurer la charge d'interception :**
    ```powershell
    fltmc statistics
    ```
    * *Check :* Si les compteurs `Pre-Op` d'un driver explosent lors d'un freeze, il est le suspect n°1.

### B. Analyse via l'Observateur d'Événements
Les preuves de blocage se trouvent dans trois journaux clés :
* **Système (Source: FilterManager, ID 4) :** "Le filtre [Nom] a mis trop de temps à répondre". C'est la preuve d'un timeout du driver.
* **Diagnostics-Performance (ID 100-110) :** Mesure l'impact des services sur le temps de boot.
* **Diagnostics-Performance (ID 203) :** Identifie les applications ralenties par des injections de DLL.



### C. Analyse via le Moniteur de Ressources (`resmon`)
1.  Aller dans l'onglet **Disque**.
2.  Observer la colonne **Temps de réponse (ms)**.
    * *Alerte :* > 100 ms sur un SSD NVMe indique une rétention par un driver de sécurité.
3.  **Analyser la chaîne d'attente :** Dans le Gestionnaire des tâches, clic droit sur l'app (ex: `chrome.exe`) > "Analyser la chaîne d'attente" pour voir quel processus agent bloque l'exécution.

---

## 4. Matrice de Corrélation (Symptômes vs Causes)

| Symptôme | Cause Probable | Action Recommandée |
| :--- | :--- | :--- |
| **Chrome / Edge > 20s** | Conflit EDR (Anti-Exploit) vs Sandbox Browser. | Tester avec exclusion temporaire du processus. |
| **Explorateur Windows lent** | Hooking Ivanti UWM sur les menus contextuels. | Vérifier la latence du driver `AmPsm`. |
| **AppData / Profil lent** | Conflit Ivanti FD vs Scan Temps Réel (S1). | Vérifier que le cache FD est exclu de l'antivirus. |
| **Latence Web (TTFB)** | Inspection réseau ForcePoint ou S1. | Vérifier la couche WFP (Windows Filtering Platform). |

---

## 5. Procédure de Reporting
Pour toute escalade, le technicien doit fournir :
1.  L'export CSV du **Script de Benchmark** (Ratio de Friction).
2.  Une capture de la commande **`fltmc instances`**.
3.  Une capture du **Moniteur de Ressources** (Onglet Disque).
