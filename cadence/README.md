# CRACK – Flot licence (Cadence) pour Croc

Flot d'implémentation de Croc avec les outils Cadence du CIME, en parallèle du flot
open-source (`yosys/`, `openroad/`, `klayout/`) qui reste intact.
Objectif : des contraintes et des objectifs **identiques** au flot open pour que le
benchmark (O4) compare les outils, pas les réglages. La correspondance détaillée
est dans [`doc/recap_flows.md`](doc/recap_flows.md).

## Utilisation

```bash
cd cadence
chmod +x run_implem.sh                         # une fois
./run_implem.sh --tech ihp130_sg13cmos5l --steps synth
./run_implem.sh -t ihp130_sg13g2 -c 8.0 --tag sweep  # 125 MHz
./run_implem.sh --stop-after 02_elaborate            # tester la lecture RTL seule
./run_implem.sh --help
```

L'environnement outils (licences, Genus/Innovus 25.11, Calibre, QRC...) est chargé
automatiquement depuis `env_cime.sh` -> `env/cds_cime_ic617_isr15.sh`, copie
versionnée de `ams_cds_isr/.bashrc_cdsic617_823_isr15` (lignes csh corrigées).
Pour l'avoir dans son shell : `source cadence/env_cime.sh`.

Le terminal n'affiche que les messages `[CRACK]` (avancement, warnings) et les
erreurs des outils. Tout le reste est dans les logs du run (`-v` pour tout voir).

Chaque run crée `runs/licence_<techno>_<freq>MHz_<date>[_tag]/` (lien `runs/latest`) :

```
run_implem.log         log complet du script (env, commandes, erreurs)
genus/logs/            genus.log, genus.cmd, genus.stdout
run_info.txt           commit git, options, variables CRACK_* (traçabilité)
config/ constraints/   copie de la config utilisée
constraints/croc.sdc   SDC généré pour ce run
constraints/croc.mmmc.tcl
genus/logs/genus.log
genus/reports/         02_* élaboration, 03_* synthèse, 04_* finaux, runtime.txt
genus/out/             croc_genus.v, croc_genus.sdc, innovus/, lec_rtl2gate.do
```

## Organisation

```
cadence/
├── run_implem.sh            script racine : options -> variables CRACK_* -> outils
├── sweep_synth.sh           balayage en fréquence (enchaîne run_implem.sh)
├── env_cime.sh              environnement outils CIME (sourcé par run_implem.sh)
├── env/cds_cime_ic617_isr15.sh  copie du bashrc Cadence CIME (IC617, DDI 25.11)
├── config/
│   ├── design_croc.tcl      design : top, flist, hiérarchie gardée (indépendant techno/outil)
│   ├── flow_defaults.tcl    réglages outils = budget de réglage du benchmark
│   └── tech/                une config par techno (chemins, coins, cellules)
│       ├── ihp130_common.tcl
│       ├── ihp130_sg13cmos5l.tcl
│       ├── ihp130_sg13g2.tcl
│       └── ams035.tcl       gabarit (lot 5), chemins via AMS_KIT_ROOT
├── constraints/
│   ├── croc_constraints.tcl valeurs extraites de openroad/src/constraints.sdc
│   ├── croc_sdc.tcl         génération du SDC
│   └── croc_cdc.tcl         CDC du DMI JTAG (Genus + Innovus)
├── scripts/extract_metrics.py  métriques communes Genus / Yosys + comparaison
├── common/
│   ├── utils.tcl            logs, lecture flist, helpers (Tcl pur)
│   └── mmmc.tcl             génération du MMMC (Genus + Innovus)
├── genus/scripts/
│   ├── genus_main.tcl       enchaîne les étapes
│   ├── 01_init.tcl          attributs, SDC/MMMC, libs, LEF
│   ├── 02_elaborate.tcl     RTL, elaborate, init_design, CDC, dont_use
│   ├── 03_synthesis.tcl     syn_generic, hiérarchie, syn_map, syn_opt, tie cells
│   └── 04_export.tcl        rapports, netlist, SDC, base Innovus, LEC
├── innovus/                 (à venir)
└── doc/
    ├── recap_flows.md       réglages des deux flots, étape par étape
    └── benchmark.md         méthode du benchmark : expériences, métriques, limites
```

Séparation techno / outil (ENF2) : ajouter une techno = ajouter
`config/tech/<nom>.tcl` qui remplit `TECH()`. Les scripts d'étapes ne changent pas.

## Métriques et comparaison des synthèses (VAL-22)

`scripts/extract_metrics.py` est le script unique d'extraction des métriques.
Il est lancé automatiquement à la fin de l'étape `synth` :
`runs/<run>/metrics/synth_genus.{txt,json,csv}`.

Les comptes et surfaces par catégorie (séquentiel, logique, buffers,
inverseurs, tie, SRAM, pads) sont **recalculés de la même façon pour les deux
flots** à partir de l'histogramme des cellules et des surfaces de la liberty
typ. Les valeurs propres à un outil sont préfixées `tool_`.

```bash
# flot open (après ./run_synthesis.sh --synth dans yosys/)
python3 cadence/scripts/extract_metrics.py yosys yosys/
#   -> yosys/reports/metrics_yosys.{txt,json,csv}

# flot licence (déjà fait par run_implem.sh, sinon à la main)
python3 cadence/scripts/extract_metrics.py genus cadence/runs/latest

# comparaison A (open) / B (licence)
python3 cadence/scripts/extract_metrics.py compare \
    yosys/reports/metrics_yosys.json cadence/runs/latest/metrics/synth_genus.json \
    -o compare_synth.txt           # + compare_synth.csv
```

Yosys n'a pas d'analyse de timing : côté open, le timing est mesuré par
OpenSTA au P&R. Les métriques de timing de synthèse n'existent donc que pour Genus.

## Balayage en fréquence et profils de réglage

Deux scénarios de benchmark, mêmes contraintes dans les deux cas
(voir `doc/recap_flows.md`, « Principe du benchmark ») :

| Profil | Réglage | Question |
|---|---|---|
| `iso` (défaut) | outils par défaut, efforts `medium`, aucun réglage fin | écart entre les outils à budget de réglage égal |
| `max` | efforts `high` + passe `syn_opt -incremental` | jusqu'où peut-on pousser le flot licence |

```bash
./sweep_synth.sh                         # iso, 50 80 100 125 150 200 MHz
./sweep_synth.sh -p max                  # même balayage, profil max
./sweep_synth.sh -f "100 125 150 175"    # autres fréquences
./run_implem.sh -p max -c 8.0            # un seul point
```

Les runs s'enchaînent (une licence Genus à la fois). Le résultat est dans
`runs/sweep_<profil>_<techno>_<date>/sweep_synth.{txt,csv}` : une ligne par
fréquence (WNS/TNS, surface, cellules, bascules scan, puissance, temps) et la plus
haute fréquence tenue. Les runs individuels se nomment `licence-<profil>_...`.

Pour superposer plusieurs balayages (iso, max, open) dans un seul tableau :
`python3 scripts/extract_metrics.py sweep runs/*/metrics/*.json <yosys.json...> -o tout.txt`

## Variables

| Variable | Rôle | Défaut |
|---|---|---|
| `CRACK_CADENCE_ENV` | fichier d'env. outils à sourcer (= `--env`) | `env_cime.sh` |
| `CDS_DDI` | installation Cadence DDI (Genus/Innovus) | `/softl1/cdsddi25_11_000` |
| `CRACK_CLK_SYS_NS` | période clk_sys (= `--clk`) | 10.0 |
| `CRACK_PROFILE` | profil de réglage iso / max (= `--profile`) | iso |
| `CRACK_SYN/MAP/OPT_EFFORT` | efforts Genus (= `--effort`) | medium |
| `CRACK_HIER_MODE` | yosys_like / keep_all / auto | yosys_like |
| `CRACK_INTERCONNECT` | ple / none | ple |
| `CRACK_SYN_OPT` | 0 pour sauter syn_opt | 1 |
| `CRACK_THREADS` | CPU Genus | 8 |
| `CRACK_IHP_LIBS_ROOT` | autre dossier lib/lef IHP | `technology/` ou `ihp13/pdk/` |
| `IHP_PDK_ROOT` | PDK IHP complet (QRC, slow, DRC) | – |
| `CRACK_ENABLE_SS` | ajoute le coin slow (PDK complet) | 0 |
| `CRACK_IHP_QRC` / `CRACK_IHP_CAPTABLE` | modèle RC | – |
| `AMS_KIT_ROOT` | kit AMS 0.35 (jamais dans git) | – |

## Points à vérifier au premier run

Les commandes Genus sensibles à la version sont dans des `catch` et affichent
`[CRACK][WARNING]` si elles sont refusées ; `run_implem.sh` liste ces warnings à
la fin. À regarder en particulier :

- lecture SV de la flist (defines `VERILATOR=1`, packages) → `02_check_unresolved.rpt` ;
- `crack_apply_croc_cdc` : nombre de ports `async*` trouvés ;
- `03_hierarchy.rpt` : hiérarchie finale à comparer avec celle de Yosys ;
- `insert_tiehilo_cells` et `write_do_lec`.
