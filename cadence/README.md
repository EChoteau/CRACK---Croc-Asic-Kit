# CRACK – Flot licence (Cadence) pour Croc

Flot d'implémentation de Croc avec les outils Cadence du CIME, en parallèle du flot
open-source (`yosys/`, `openroad/`, `klayout/`) qui reste intact.
Objectif : des contraintes et des objectifs **identiques** au flot open pour que le
benchmark (O4) compare les outils, pas les réglages. La correspondance détaillée
est dans [`doc/contraintes_flot_open.md`](doc/contraintes_flot_open.md).

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
└── doc/contraintes_flot_open.md
```

Séparation techno / outil (ENF2) : ajouter une techno = ajouter
`config/tech/<nom>.tcl` qui remplit `TECH()`. Les scripts d'étapes ne changent pas.

## Variables

| Variable | Rôle | Défaut |
|---|---|---|
| `CRACK_CADENCE_ENV` | fichier d'env. outils à sourcer (= `--env`) | `env_cime.sh` |
| `CDS_DDI` | installation Cadence DDI (Genus/Innovus) | `/softl1/cdsddi25_11_000` |
| `CRACK_CLK_SYS_NS` | période clk_sys (= `--clk`) | 10.0 |
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
