# run_flow.sh : flot open-source Croc (IHP130 sg13cmos5l)

`scripts/run_flow.sh` enchaîne les étapes du flot open-source de Croc (synthèse → P&R → GDS → DRC → LVS). Il vérifie automatiquement les tests du plan de validation et archive chaque run dans `logs/<RUN_ID>/`.

Il ne remplace pas les scripts d'origine du kit (`yosys/run_synthesis.sh`, `openroad/run_backend.sh`, `klayout/run_finishing.sh`, `klayout/run_drc.sh`). Il les appelle, puis ajoute la traçabilité (versions, durées, sommes de contrôle) et les checks.

---

## 1. Prérequis

| Élément | Vérification |
|---|---|
| Docker Engine natif (pas Docker Desktop) | `docker ps` répond sans erreur |
| Sous-modules initialisés | `git submodule status` : aucune ligne ne commence par `-` |
| Scripts exécutables | `chmod +x scripts/run_flow.sh scripts/run_detached.sh` |
| Runs longs (plus de quelques minutes) | `scripts/run_detached.sh` : le run survit à la déconnexion SSH (voir §2) |

> **Le script se lance DANS le conteneur.** Sur l'hôte, les outils (`bender`, `yosys`, `openroad`, `klayout`, `gawk`) n'existent pas.

---

## 2. Démarrage rapide

### Étape courte ou essai (terminal interactif)

```bash
# Sur l'hôte
cd ~/Documents/emilien/CRACK_docker/CRACK---Croc-Asic-Kit
./scripts/start_linux_nogui.sh      # entre dans le conteneur

# Dans le conteneur (/fosic/designs/croc)
which bender yosys openroad klayout gawk
./scripts/run_flow.sh synth
```

> Une session interactive **meurt avec la connexion SSH**. `tmux` n'est pas installé sur l'hôte du CIME, et un `tmux` lancé dans le conteneur ne protège pas : il disparaît avec le conteneur. Pour tout ce qui dure (backend ≈ 40 min, DRC full ≈ 43 min, `all` ≈ 1 h 30), utiliser le mode détaché ci-dessous.

### Run long (détaché, survit à la déconnexion)

```bash
# Sur l'hôte (pas dans le conteneur)
RUN_ID=baseline_open_ihp130 ./scripts/run_detached.sh all
./scripts/run_detached.sh status     # état du run, dernières lignes, derniers ECHEC/ECART/MANUEL
./scripts/run_detached.sh log        # suit la sortie (Ctrl+C quitte le suivi, pas le run)
./scripts/run_detached.sh stop       # arrête le run (les résultats partiels restent)
```

- Mêmes étapes et mêmes variables que `run_flow.sh` : `./scripts/run_detached.sh drc_report full`, `DRC_JOBS=8`, `CROC_PDK`, `RUN_ID`.
- **Un seul run à la fois** : les runs partagent `openroad/save`, `klayout/out`… et s'écraseraient (`FORCE=1` pour passer outre).
- La sortie complète est dans `logs/<RUN_ID>.out` ; les résultats habituels restent dans `logs/<RUN_ID>/`.
- Principe : `nohup docker compose run --rm -T --name croc_<RUN_ID> … --skip bash -c "./scripts/run_flow.sh <étape>"` lancé en arrière-plan sur l'hôte. Un essai avec `sleep 120` a fonctionné le 17/11/2026.

---

## 3. Étapes disponibles

```bash
./scripts/run_flow.sh <étape>
```

| Étape | Appelle | Sortie principale | Checks | Durée mesurée* |
|---|---|---|---|---|
| `synth` | `run_synthesis.sh --synth` | `yosys/out/croc_yosys.v` | VAL-01, VAL-02 | 139 s |
| `floorplan` | `run_backend.sh --floorplan` | `save/01_croc.floorplan.zip` | VAL-05 | 9 s |
| `placement` | `run_backend.sh --placement` | `save/02_croc.placed.zip` | VAL-06 | 154 s |
| `cts` | `run_backend.sh --cts` | `save/03_croc.cts.zip` | VAL-07 | 34 s |
| `routing` | `run_backend.sh --routing` | `save/04_croc.routed.zip` | VAL-08 | 2131 s |
| `finishing` | `run_backend.sh --finishing` | `out/croc.{def,v,odb,sdc}` | sorties | 55 s |
| `backend` | les 5 étapes ci-dessus | | VAL-05 à VAL-08 | ≈ 40 min |
| `gds` | `run_finishing.sh --gds --seal` | `klayout/out/croc.sealed.gds.gz` | GDS, VAL-17 (partiel) | 58 s |
| `drc_minimal` | `run_drc.sh --minimal` | `klayout/drc-minimal/` | VAL-13(min) | 242 s |
| `drc` | `run_drc.sh --full` (avec antenna), puis `drc_report` | `klayout/drc-full/` | VAL-13, VAL-15, VAL-16 | 2605 s (≈ 43 min) |
| `drc_report [full\|minimal]` | aucun : analyse les résultats DRC déjà présents | `logs/<RUN_ID>/drc_<mode>_summary.txt` | VAL-13 | à mesurer |
| `lvs` | `verilog2spice.py` puis `run_lvs.py` du PDK (voir §9) | `klayout/lvs/` | VAL-14 | à mesurer |
| `all` | synth + backend + gds + drc + lvs | | tous | |

\* `ocaepc69` (CIME, 20 cœurs, 31 Go de RAM), run `open_ihp130_20261023_0855` (étapes lancées entre le 23/10 et le 12/11/2026). La durée du DRC full est relevée dans `klayout/drc-full/drc-coordinator.log`. Le nombre de cœurs de chaque run est noté dans `versions.txt`.

Les étapes du backend repartent du checkpoint de l'étape précédente (`openroad/save/*.zip`). On peut donc relancer une seule étape après une correction.

**DRC full.** `run_drc.py` lance une trentaine de tables de règles en parallèle (`DRC_JOBS`). La table `sg13cmos5l_maximal` fixe la durée totale (≈ 43 min) ; les autres finissent en ≈ 18 min. `run_drc.py` **sort avec un code d'erreur dès qu'il y a des violations** (« KLayout DRC Check Failed ») : ce n'est pas un plantage. Le script intercepte ce code ; seuls l'absence de résultat (`.lyrdb`) ou l'exception d'un worker (`drc-coordinator.log`) arrêtent le flot. `drc_report` analyse ensuite les résultats : violations par table et par règle dans `drc_<mode>_summary.txt`, règles obligatoires (`ECART`) séparées des règles recommandées dont le nom se termine par `R`, par exemple `Pad.fR_M2` (`MANUEL`). On peut le relancer seul : `RUN_ID=<nom> ./scripts/run_flow.sh drc_report full`.

---

## 4. Variables

| Variable | Rôle | Défaut |
|---|---|---|
| `RUN_ID` | Nom du dossier de run. Garder le même pour regrouper plusieurs étapes | `open_ihp130_AAAAMMJJ_HHMM` |
| `DRC_JOBS` | Nombre de tables DRC en parallèle (à baisser si la RAM sature) | `nproc` |
| `PROJ_NAME` / `TOP_DESIGN` | Nom du projet / module top (hérités de `env.sh`) | `croc` / `croc_chip` |

Exemple :

```bash
RUN_ID=baseline_open_ihp130 ./scripts/run_flow.sh all
DRC_JOBS=4 RUN_ID=baseline_open_ihp130 ./scripts/run_flow.sh drc
```

---

## 5. Contenu d'un dossier de run

```
logs/<RUN_ID>/
├── versions.txt     # date, machine, commit, outils, sous-modules (PDK)
├── checks.txt       # résultats des vérifications (voir §6)
├── timing.txt       # durée de chaque étape (VAL-22)
├── checksums.txt    # SHA-256 des fichiers produits (VAL-21)
├── <étape>.log      # log complet de chaque étape, sans codes couleur
├── croc_yosys.v     # copie de la netlist
├── openroad/        # copie de reports/, save/, out/, logs/
├── klayout/         # logs KLayout + rapports DRC (*.lyrdb), logs et schéma du LVS
└── drc_<mode>_summary.txt  # violations DRC par table et par règle (étape drc_report)
```

Chaque lancement ajoute une ligne `===== date : étape '...' =====` dans `checks.txt` et `timing.txt`. Elle permet de distinguer plusieurs lancements dans un même dossier.

---

## 6. Lire `checks.txt`

```
[CHECK] <ID du test> : <statut> : <message>
```

| Statut | Signification | Action |
|---|---|---|
| `OK` | Critère vérifié automatiquement | aucune |
| `ECART` | Résultat anormal mais non bloquant (latch, violation d'une règle DRC obligatoire, mismatch LVS…) | corriger, ou justifier dans le **journal des écarts** |
| `ECHEC` | Critère non rempli. Arrête le flot, sauf pour le routage et la finition | corriger avant de continuer |
| `MANUEL` | Non vérifiable automatiquement (skew, congestion, grille d'alim…), ou règle DRC recommandée | lire le rapport indiqué |

Relecture rapide :

```bash
grep -E "ECHEC|ECART|MANUEL" logs/<RUN_ID>/checks.txt
cat logs/<RUN_ID>/timing.txt
```

> Un `OK` signifie que le check automatique est passé, pas que le test du plan de validation est clos. Exemple : `VAL-08 : 0 violation` est le compteur interne du routeur, pas un DRC signoff (c'est VAL-13).

---

## 7. Pièges connus

| Symptôme | Cause | Solution |
|---|---|---|
| `mounts denied: /tmp/.X11-unix` | Docker Desktop ne partage pas le socket X11 | Utiliser `start_linux_nogui.sh` (montages X11 retirés) ou Docker Engine natif |
| `bender: command not found`, `gawk: command not found` | Script lancé sur l'hôte | Le lancer dans le conteneur |
| `env: 'docker': No such file or directory` | `start_linux*.sh` lancé dans le conteneur | Ce script se lance sur l'hôte |
| `Permission denied` sur `run_flow.sh` | Droit d'exécution perdu (`scp`, clone) | `chmod +x`, et committer avec `git add --chmod=+x` |
| Sous-module `artistic` : `Permission denied (publickey)` | Sous-module déclaré en SSH | Ajouter une clé GitHub, ou `git config --global url."https://github.com/".insteadOf git@github.com:` |
| `VAL-01b : ECHEC` alors que le log dit `0 Error` | Codes couleur ANSI dans le log Bender | Corrigé dans le script (filtre ANSI) |
| Résultats d'un ancien run mélangés | `openroad/{save,reports,out,logs}` non vidés | Archiver/supprimer ces dossiers avant une baseline propre |
| Violations de densité au DRC full (`AFil.g`, `GFil.g`, `M1Fil.h`…) | `run_drc.sh` vérifie le GDS **sans fill** | Attendu ; le fill (`--fill`) n'est pas encore intégré |
| Violations `Pad.fR_*`, `Pad.dR`, `Pad.d1R` au DRC full, absentes du DRC minimal | Règles **recommandées** (suffixe `R`), exclues du mode minimal (`--no_recommended`) | Classées `MANUEL` par `drc_report` ; à faire valider par l'enseignant |
| Le DRC full s'arrête sans aucun check dans `checks.txt` | `run_drc.py` renvoie un code ≠ 0 dès qu'il y a des violations, et `set -e` arrête le script | Corrigé dans la version actuelle de `run_flow.sh` (code retour intercepté) ; relancer l'analyse avec `drc_report` |
| Run perdu quand la session SSH se coupe | Session interactive (ou `tmux` dans le conteneur) liée à la connexion ; pas de `tmux` sur l'hôte | Lancer avec `scripts/run_detached.sh` (voir §2) |
| `run_drc.py` : `No module named 'klayout'` | Lancé sur l'hôte | Le lancer dans le conteneur |
| `VAL-17 : ECART` alors que le log ne signale rien | Le log `def2stream` contient la ligne `[INFO] Checking for missing cell...` | Ligne exclue du filtre dans la version actuelle |

---

## 8. Limites actuelles et suite

- **STA multi-coins (VAL-09/VAL-10)** : non intégrée. L'extraction RC (`write_spef`) est commentée dans `05_finishing.tcl`, et aucun coin lent n'a été trouvé dans `technology/lib`.
- **LVS (VAL-14)** : intégré (étape `lvs`, voir §9) mais **jamais exécuté sur le vrai design** : la conversion Verilog → SPICE et les règles de comparaison sont à valider au premier run.
- **Fill et DRC sur GDS rempli (VAL-16)** : non intégrés.
- `set_thread_count 8` est en dur dans les Tcl de placement et de routage : à prendre en compte pour comparer les durées entre machines.
- `versions.txt` est **réécrit** à chaque lancement dans un même `RUN_ID` : les versions notées sont celles du dernier lancement. Les checkpoints sont comparés à ce fichier (`-nt`), donc relancer une étape recrée la référence de date.
- **SDC** : 4 entrées sans `set_input_delay`, 4 sorties sans `set_output_delay` (warnings du floorplan). Ne pas modifier `constraints.sdc` avant de figer le protocole (tâche 4.1).

---

## 9. Étape `lvs` (VAL-14)

```bash
./scripts/run_flow.sh lvs        # après backend et gds (même RUN_ID si possible)
```

1. **`scripts/verilog2spice.py`** convertit `openroad/out/croc_lvs.v` (Verilog avec VDD/VSS, sans fillers ni bondpads) en `klayout/lvs/croc_chip_schematic.cir`. `run_lvs.py` n'accepte que du SPICE/CDL. L'ordre des broches vient des CDL du PDK : cellules standard, IO (PDK choisi par `CROC_PDK`) et SRAM (`ihp13/sg13g2/.../sg13g2_sram/cdl`).
2. **`run_lvs.py`** (dans `ihp13/<pdk>/.../tech/lvs/`) extrait la netlist du GDS et la compare au schéma.

Choix à connaître :
- Le LVS tourne sur le GDS **non scellé** `klayout/out/croc.gds.gz`. Le deck cherche dans le schéma un circuit du même nom que le top cell du layout (`croc_chip`) ; le top cell du GDS scellé s'appelle `croc_chip_sealed`.
- Le verdict est lu dans les logs (`Congratulations! Netlists match.` / `Netlists don't match`), pas dans le code retour.
- Les cellules absentes des CDL sont ignorées et listées dans `VAL-14a` (bondpads attendus ; toute autre cellule est suspecte).
- Le `.lvsdb` complet reste dans `klayout/lvs/` et n'est pas copié dans `logs/<RUN_ID>/` (seuls les logs et le schéma le sont).

Points à surveiller au premier run : noms des cellules `sg13cmos5l_stdcell.cdl` contre ceux du Verilog (`sg13g2_*`), broches des bus SRAM, alimentations des cellules IO, ports du top.

