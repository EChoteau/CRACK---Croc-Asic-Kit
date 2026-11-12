# run_flow.sh : flot open-source Croc (IHP130 sg13cmos5l)

`scripts/run_flow.sh` enchaîne les étapes du flot open-source de Croc (synthèse → P&R → GDS → DRC). Il vérifie automatiquement les tests du plan de validation et archive chaque run dans `logs/<RUN_ID>/`.

Il ne remplace pas les scripts d'origine du kit (`yosys/run_synthesis.sh`, `openroad/run_backend.sh`, `klayout/run_finishing.sh`, `klayout/run_drc.sh`). Il les appelle, puis ajoute la traçabilité (versions, durées, sommes de contrôle) et les checks.

---

## 1. Prérequis

| Élément | Vérification |
|---|---|
| Docker Engine natif (pas Docker Desktop) | `docker ps` répond sans erreur |
| Sous-modules initialisés | `git submodule status` : aucune ligne ne commence par `-` |
| Script exécutable | `chmod +x scripts/run_flow.sh` |
| Session `tmux` (runs longs, SSH) | `tmux new -s croc` |

> **Le script se lance DANS le conteneur.** Sur l'hôte, les outils (`bender`, `yosys`, `openroad`, `klayout`, `gawk`) n'existent pas.

---

## 2. Démarrage rapide

```bash
# Sur l'hôte
cd ~/crack/CRACK---Croc-Asic-Kit
tmux new -s croc                    # ou : tmux attach -t croc
./scripts/start_linux_nogui.sh      # entre dans le conteneur

# Dans le conteneur (/fosic/designs/croc)
which bender yosys openroad klayout gawk
./scripts/run_flow.sh all           # flot complet
```

Pour se détacher sans arrêter le run : `Ctrl+B` puis `D`. Pour revenir : `tmux attach -t croc`.

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
| `gds` | `run_finishing.sh --gds --seal` | `klayout/out/croc.sealed.gds.gz` | GDS, VAL-17 (partiel) | à mesurer |
| `drc_minimal` | `run_drc.sh --minimal` | `klayout/drc-minimal/` | VAL-13(min) | à mesurer |
| `drc` | `run_drc.sh --full` (avec antenna) | `klayout/drc-full/` | VAL-13, VAL-15, VAL-16 | à mesurer |
| `lvs` | `verilog2spice.py` puis `run_lvs.py` du PDK (voir §9) | `klayout/lvs/` | VAL-14 | à mesurer |
| `all` | synth + backend + gds + drc + lvs | | tous | |

\* PC CIME distant, run du 23/10/2026. Le nombre de cœurs est noté dans `versions.txt`.

Les étapes du backend repartent du checkpoint de l'étape précédente (`openroad/save/*.zip`). On peut donc relancer une seule étape après une correction.

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
└── klayout/         # logs KLayout + rapports DRC (*.lyrdb)
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
| `ECART` | Résultat anormal mais non bloquant (latch, violation DRC…) | corriger, ou justifier dans le **journal des écarts** |
| `ECHEC` | Critère non rempli. Arrête le flot sauf pour le routage, la finition et le DRC | corriger avant de continuer |
| `MANUEL` | Non vérifiable automatiquement (skew, congestion, grille d'alim…) | lire le rapport indiqué |

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
| Violations de densité au DRC full | `run_drc.sh` vérifie le GDS **sans fill** | Attendu ; le fill (`--fill`) n'est pas encore intégré |

---

## 8. Limites actuelles et suite

- **STA multi-coins (VAL-09/VAL-10)** : non intégrée. L'extraction RC (`write_spef`) est commentée dans `05_finishing.tcl`, et aucun coin lent n'a été trouvé dans `technology/lib`.
- **LVS (VAL-14)** : intégré (étape `lvs`, voir §9) mais **jamais exécuté sur le vrai design** : la conversion Verilog → SPICE et les règles de comparaison sont à valider au premier run.
- **Fill et DRC sur GDS rempli (VAL-16)** : non intégrés.
- `set_thread_count 8` est en dur dans les Tcl de placement et de routage : à prendre en compte pour comparer les durées entre machines.
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

