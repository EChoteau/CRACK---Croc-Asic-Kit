# Récapitulatif des réglages : flot open vs flot licence

Fiche de référence du projet CRACK (Croc, IHP130). Pour chaque étape, elle dit
**quel fichier fixe quoi, avec quelle valeur**, dans le flot open-source
(`yosys/`, `openroad/`, `klayout/`) et dans le flot licence (`cadence/`).

Elle est tenue à jour à chaque changement de réglage (voir l'historique en bas).
C'est le document de référence unique pour les réglages et le principe du
benchmark (il remplace `contraintes_flot_open.md`). La méthode complète du
benchmark (expériences, métriques, limites) est dans `benchmark.md`.

**Légende du statut**

| Statut | Sens |
|---|---|
| `=` | identique (même valeur, même fichier source ou copie fidèle) |
| `≈` | équivalent : même intention, mise en œuvre propre à l'outil |
| `≠` | différent : capacité propre à un outil ou choix assumé (à commenter dans le benchmark) |
| `⏳` | pas encore implémenté côté licence |

Chemins relatifs à la racine du dépôt. Valeurs pour la techno par défaut
`sg13cmos5l` et le profil `iso`, sauf mention contraire.

---

## Principe du benchmark (décision du 09/11/2026)

On compare des **flots**, c'est-à-dire ce que chaque outil sait faire à partir des
mêmes données.

- **Identique pour les deux flots** : RTL, file list, defines, top, bibliothèques et
  coins, SDC (horloges, E/S, charges, CDC), hiérarchie conservée, cellules
  interdites, fréquences cibles du balayage.
- **Libre pour chaque outil** : ses optimisations, avec ses réglages par défaut,
  sans réglage fin spécifique à Croc.
- On **ne neutralise pas** une capacité propre à un outil. Exemple : Genus utilise
  des bascules scan comme bascules à enable, Yosys non. C'est un résultat du
  benchmark, à commenter dans l'analyse, pas un biais à corriger.
- Toute exception à ces règles est notée dans le journal des écarts.

Deux scénarios côté licence, mêmes contraintes dans les deux cas
(`cadence/config/flow_defaults.tcl`, option `--profile`) :

| Profil | Réglage | Question |
|---|---|---|
| `iso` (défaut) | outils par défaut, efforts Genus `medium`, aucun réglage fin | écart entre les outils à budget de réglage égal |
| `max` | efforts `high` + passe `syn_opt -incremental` | jusqu'où peut-on pousser le flot licence |

### Points à garder en tête pour l'analyse

| Point | Conséquence |
|---|---|
| Le flot open est **déjà réglé pour Croc** par ses développeurs (ETH, tape-outs) ; le flot licence part des réglages par défaut | biais plutôt favorable au flot open, à écrire dans le rapport |
| Yosys n'a **pas de SDC** : ABC vise un délai fixe (`period_ps = 10000`) avec ses propres hypothèses (`abc.constr`) | comparer les flots **après routage**, avec le même SDC et le même STA (VAL-11) ; les chiffres de synthèse servent à expliquer les écarts |
| `period_ps` (`yosys/scripts/yosys_synthesis.tcl`) et `TCK_SYS` (`openroad/src/constraints.sdc`) sont **en dur à 10 ns** | à rendre paramétrables avant le balayage côté open, sinon Yosys/OpenROAD restent à 100 MHz |
| Pas de coin slow dans le miroir public du PDK | setup vérifié sur tt dans les deux flots ; coin ss = option hors benchmark |
| Pas de modèle RC IHP pour Cadence (D1) | parasites estimés différemment selon l'outil ; d'où l'intérêt d'un STA commun |

---

## 0. Lancement et environnement

| Paramètre | Flot open | Flot licence | Statut |
|---|---|---|---|
| Point d'entrée | `yosys/run_synthesis.sh --synth`, puis `openroad/run_backend.sh`, puis `klayout/run_finishing.sh` / `run_drc.sh` | `cadence/run_implem.sh` (toutes étapes), `cadence/sweep_synth.sh` (balayage) | ≈ |
| Environnement | `env.sh` (chemins PDK, `CROC_PDK`, `PROJ_NAME`, `TOP_DESIGN`) | `cadence/env_cime.sh` → `cadence/env/cds_cime_ic617_isr15.sh` (licences, outils) | ≈ |
| Outils | Yosys + plugin slang, OpenROAD, KLayout | Genus 21.18 isr8 (`/softslin/cdsgenus21_18_000_isr8`) ; Innovus : version à fixer | ≠ |
| Licences | aucune | `LM_LICENSE_FILE=5287@cimeldap:5280@cimekey1` (+ Synopsys 1721, Mentor 1718) | – |
| Choix techno | `CROC_PDK=sg13cmos5l\|sg13g2` | `--tech ihp130_sg13cmos5l\|ihp130_sg13g2` → `cadence/config/tech/<tech>.tcl` | ≈ |
| Organisation des sorties | `yosys/{out,reports,tmp}`, `openroad/{reports,save,out}` (écrasés à chaque run) | `cadence/runs/licence-<profil>_<tech>_<f>MHz_<date>/` (un dossier par run, archivé) | ≠ |
| Logs | sortie terminal + rapports | `run_implem.log`, `genus/logs/genus.{log,cmd,stdout}` ; terminal : messages `[CRACK]` seuls | ≠ |
| Traçabilité | – | `run_info.txt` (commit, options, variables) + copie de `config/` et `constraints/` | ≠ |

---

## 1. Entrées du design

| Paramètre | Flot open | Flot licence | Statut |
|---|---|---|---|
| Top | `croc_chip` (`TOP_DESIGN`, `env.sh`) | `croc_chip` (`cadence/config/design_croc.tcl`) | = |
| Liste des sources | `yosys/src/croc.flist` (Bender `-t asic -t ihp13 -t rtl -t synthesis`, 167 fichiers) | **même fichier**, relu tel quel (`design_croc.tcl` : `DESIGN(flist)`) | = |
| Ordre des fichiers | ordre de la flist | idem | = |
| Defines | `TARGET_ASIC TARGET_FLIST TARGET_IHP13 TARGET_RTL TARGET_SYNTHESIS VERILATOR=1 SYNTHESIS=1 COMMON_CELLS_ASSERTS_OFF=1` + `IHP_SG13CMOS5L=1` (`BENDER_PDK_ARGS`, `env.sh`) | mêmes defines de la flist + `IHP_SG13CMOS5L=1` (`config/tech/ihp130_sg13cmos5l.tcl` : `TECH(extra_defines)`) | = |
| Lecteur HDL | `read_slang --compat-mode --keep-hierarchy --allow-use-before-declare --ignore-unknown-modules` | `read_hdl -language sv -define …` puis `elaborate croc_chip` ; module non résolu = erreur (`hdl_error_on_blackbox true`) | ≈ |
| Valeurs non définies | `setundef -zero` | `hdl_unconnected_value 0` | ≈ |
| SRAM | 2 × `RM_IHPSG13_1P_512x32_c2_bm_bist` (`ihp13/tc_sram_impl.sv`) | idem | = |

> La `croc.flist` versionnée a été générée pour sg13g2 (sans `IHP_SG13CMOS5L`).
> `run_synthesis.sh --synth` la régénère ; le flot licence ajoute le define par la config techno.

---

## 2. Technologie, bibliothèques et coins

| Paramètre | Flot open | Flot licence | Statut |
|---|---|---|---|
| Dossier des vues | `technology/` si présent, sinon `ihp13/pdk/` (`env.sh`) | même règle (`config/tech/ihp130_common.tcl` : `TECH(libs_root)`) | = |
| Liberty synthèse | `sg13g2_stdcell_typ_1p20V_25C.lib` (mapping) + SRAM typ + IO typ en `-lib` (`yosys/scripts/init_tech_sg13cmos5l.tcl`) | vue `view_tt` du MMMC : mêmes 3 familles de libs typ | = |
| Coins P&R | `define_corners tt ff` (`openroad/scripts/init_tech_sg13cmos5l.tcl`) | MMMC : `tt` (setup), `ff` (hold) (`cadence/common/mmmc.tcl`) | = |
| Coin tt | stdcell typ 1,20 V 25 °C ; IO typ 1,2/3,3 V ; SRAM typ 1,20 V 25 °C | idem | = |
| Coin ff | stdcell fast 1,32 V −40 °C ; IO fast 1,32/3,6 V ; SRAM fast 1,32 V −55 °C | idem | = |
| Coin ss | absent du miroir public | option `CRACK_ENABLE_SS=1` (PDK complet, hors benchmark) | ≠ |
| LEF | tech `sg13cmos5l_tech.lef`, `sg13g2_stdcell.lef`, `sg13cmos5l_io.lef`, `bondpad5l_70x70.lef`, `RM_IHPSG13_*.lef` | mêmes 11 LEF (`TECH(lefs)`) | = |
| Modèle RC | `set_wire_rc -clock/-signal -layer Metal3` (estimation) ; **pas d'extraction** : `extract_parasitics` (OpenRCX, `IHP_rcx_patterns.rules`) est commenté dans `05_finishing.tcl` | pas de QRC/captable IHP (décision D1) : modèle interne Genus (PLE à partir des LEF) | ≠ |

---

## 3. Contraintes de timing (SDC)

| Paramètre | Flot open | Flot licence | Statut |
|---|---|---|---|
| Fichier | `openroad/src/constraints.sdc` (+ `openroad/src/instances.tcl`) | SDC **généré** par `cadence/constraints/croc_sdc.tcl` à partir de `croc_constraints.tcl` → `runs/<run>/constraints/croc.sdc` | ≈ |
| Appliqué dès | le P&R (Yosys ne lit pas de SDC) | la synthèse (Genus, via MMMC) | ≠ |
| `clk_sys` (`clk_i`) | 10 ns (`TCK_SYS`, en dur) | 10 ns par défaut, paramètre `--clk` | = (≠ en balayage) |
| `clk_jtg` (`jtag_tck_i`) | 25 ns | 25 ns | = |
| `clk_rtc` (`ref_clk_i`) | 50 ns | 50 ns | = |
| Groupes d'horloges | rtc / jtg / sys asynchrones | idem | = |
| Incertitude / transition | 0,1 ns / 0,2 ns | idem | = |
| Charge sorties | 15 pF (`set_load`) | idem | = |
| Pilotage entrées | `sg13cmos5l_IOPadOut16mA`, pin `pad` | idem | = |
| Délais d'E/S | GPIO/UART in/out min 10 % max 30 % ; JTAG in 10/30 %, tdo 10/20 % ; `status_o`/`unused*` 10 % | idem (`croc_constraints.tcl`) | = |
| Resets (`rst_ni`, `testmode_i`, `jtag_trst_ni`) | input_delay max 10 % TCK_JTG, false_path hold, max_delay | idem | = |
| CDC DMI JTAG | `set_max_delay 3.0 -ignore_clock_latency`, bascules trouvées par `get_fanin`/`get_fanout` OpenROAD sur la netlist aplatie | même valeur, ports `async*` des `cdc_2phase` gardés (`all_fanin`/`all_fanout`, `cadence/constraints/croc_cdc.tcl`) : 86 + 72 ports | ≈ |
| Hypothèses internes de synthèse | ABC : `-D 10000` ps, `set_driving_cell sg13g2_buf_1`, `set_load 0.015` (`yosys/src/abc.constr`) | – (le vrai SDC sert directement) | ≠ |

---

## 4. Synthèse

### 4.1 Déroulé

| Étape | Flot open (`yosys/scripts/yosys_synthesis.tcl`) | Flot licence (`cadence/genus/scripts/`) | Statut |
|---|---|---|---|
| Lecture / élaboration | `read_slang`, `hierarchy`, `proc` | `02_elaborate.tcl` : `read_hdl`, `elaborate`, `init_design` | ≈ |
| Optimisation générique | `opt`, `fsm`, `wreduce`, `peepopt`, `booth`, `share`, `memory_map`, `opt_dff -sat -nodffe -nosdff`, `techmap` | `syn_generic` (effort `medium` ; `high` en profil max) | ≈ |
| Aplatissement | `flatten` (après générique), sauf modules `keep_hierarchy` | dégroupage itératif après `syn_generic`, sauf mêmes modules (nom RTL d'origine) | ≈ |
| Mapping bascules | `dfflibmap` (bascules simples de la lib) | `syn_map` (Genus choisit, bascules scan comprises) | ≠ |
| Mapping logique | `abc` avec `scripts/abc-opt.script` : 8 × (`&if`/`&syn2`) puis 8 × (opt + `&nf` mapping), `buffer -p`, `upsize`/`dnsize` × 2 | `syn_map` puis `syn_opt` (+ `syn_opt -incremental` en profil max) | ≠ |
| Cellules tie | `hilomap -singleton` `sg13g2_tiehi/L_HI`, `sg13g2_tielo/L_LO` | `insert_tiehilo_cells -high sg13g2_tiehi -low sg13g2_tielo -all` (`use_tiehilo_for_const unique`) | ≈ |
| Nettoyage netlist | `splitnets -ports`, `clean -purge` | `remove_assigns true` | ≈ |

### 4.2 Hiérarchie conservée

Mêmes 22 motifs des deux côtés (`yosys_synthesis.tcl` : `setattr -set keep_hierarchy` /
`cadence/config/design_croc.tcl` : `DESIGN(keep_hier_modules)`) :
`croc_soc`, `croc_domain`, `user_domain`, `core_wrap`, `cve2_register_file_ff`,
`cve2_cs_registers`, `dmi_jtag`, `dm_top`, `gpio`, `clint`, `bootrom`, `obi_timer`,
`croc_idma`, `obi_uart`, `soc_ctrl_regs`, `tc_clk*`, `tc_sram_impl`, `cdc_reset*`,
`cdc*phase_*`, `cdc*_src*`, `cdc*_dst*`, `sync`. Statut `=`.

Comparaison sur le **nom exact du module RTL** des deux côtés (`gpio` garde `gpio`
mais pas `gpio_reg_top`). Contrôle : `runs/<run>/genus/reports/03_hierarchy.rpt`.

### 4.3 Réglages et options

| Réglage | Flot open | Flot licence | Statut |
|---|---|---|---|
| Effort | script ABC fixe | `medium` (iso) / `high` (max) : `cadence/config/flow_defaults.tcl` | ≠ |
| Clock gating | non | non (`lp_insert_clock_gating false`) | = |
| Insertion de scan (DFT) | non | non | = |
| Bascules à preset asynchrone | légalisées par `dfflibmap` (bascule à reset + inverseurs) | `lbr_seq_in_out_phase_opto true` (même principe) | ≈ |
| Dégroupage automatique | – | `auto_ungroup none` (sauf `--hier auto`) | ≈ |
| Modèle de fil | aucun | PLE (LEF) ; `--interconnect none` = wireload `Zero` | ≠ |
| Contraintes CDC | non (pas de SDC) | oui (`croc_cdc.tcl`) | ≠ |
| CPU | – | 8 (`CRACK_THREADS`) | – |

### 4.4 Cellules : bloquées, protégées, utilisées

| Sujet | Flot open | Flot licence | Statut |
|---|---|---|---|
| Interdites par la lib (`dont_use : true` dans `sg13g2_stdcell_typ`) | `sg13g2_antennanp`, `sg13g2_decap_4/8`, `sg13g2_fill_1/2/4/8`, `sg13g2_lgcp_1`, `sg13g2_slgcp_1` (clock gating), `sg13g2_sdfbbp_1` (bascule scan set+reset), `sg13g2_sighold` | idem (lu dans la lib) | = |
| Interdites par le flot en synthèse | aucune (`dont_use_list` vide) | `sg13cmos5l_IOPad*` (15 cellules) | ≈ (pads instanciés à la main de toute façon) |
| Cellules protégées | attribut `keep`/`dont_touch` respecté (`tc_clk*`) | `preserve true` sur les cellules sg13g2 instanciées dans `tc_clk*`, posé avant `syn_generic` | ≈ |
| Bascules utilisées | bascules simples (`dfflibmap`) | `sg13g2_dfrbpq_1`, `sg13g2_dfrbp_1` **et bascules scan** `sg13g2_sdfrbpq_1`, `sg13g2_sdfrbp_1` utilisées comme bascules à enable (≈ 2 257 / 4 159 au run du 09/11, 100 MHz) | ≠ (capacité outil, conservée) |
| Bibliothèque de mapping | stdcells seules (`-liberty` stdcell) | stdcells (IO et SRAM non inférables) | = |
| Tie | `sg13g2_tiehi`, `sg13g2_tielo` | idem (9 tiehi + 2 tielo au run du 09/11) | = |

### 4.5 Sorties et rapports

| Sortie | Flot open | Flot licence |
|---|---|---|
| Netlist | `yosys/out/croc_yosys.v` | `runs/<run>/genus/out/croc_genus.v` |
| SDC | – | `genus/out/croc_genus.sdc` (`write_sdc -view view_tt`) |
| Base pour le P&R | – | `genus/out/innovus/` (`write_design -innovus`) |
| Équivalence formelle | – | `genus/out/lec_rtl2gate.do` (Conformal) + `genus/fv/` |
| Rapports | `yosys/reports/croc_{area,area_logic,registers,instances,synth}.rpt` | `genus/reports/0{2,3,4}_*.rpt`, `runtime.txt`, `tool_version.txt` |
| Métriques communes | `extract_metrics.py yosys yosys/` → `yosys/reports/metrics_yosys.*` | automatique → `runs/<run>/metrics/synth_genus.*` |

---

## 5. Floorplan

| Paramètre | Flot open (`openroad/scripts/01_floorplan.tcl`) | Flot licence | Statut |
|---|---|---|---|
| Die | 1916 × 1916 µm | à reproduire | ⏳ |
| Marge cœur | padD 180 + padBond 70 + powerRing 80 = 330 µm | à reproduire | ⏳ |
| Site | `CoreSite` | `TECH(core_site)` = `CoreSite` | ⏳ |
| Padring | `openroad/src/padring.tcl` ; coin `sg13cmos5l_Corner` ; fillers IO `sg13cmos5l_Filler10000…200` ; bondpad `bondpad5l_70x70` | à reproduire | ⏳ |
| SRAM | 2 bancs en haut du cœur, gauche et droite, padding 20 µm, orientation R0, halo 10 µm (`cut_rows`) | à reproduire | ⏳ |
| Grille d'alimentation | `power_grid_sg13cmos5l.tcl` : anneau TopMetal1/Metal4 (largeur 8, espacement 4) ; rails Metal1 0,32 µm ; straps TopMetal1 3 µm pas 90 (12 straps) + straps dédiés SRAM ; straps Metal4 1 µm pas 180 | à reproduire | ⏳ |
| Connexions alim | `power_connect.tcl` (`global_connect`) | à reproduire | ⏳ |
| Tap cells | aucune (`insertTapCells` vide) | – | ⏳ |

## 6. Placement

| Paramètre | Flot open (`02_placement.tcl`) | Flot licence | Statut |
|---|---|---|---|
| dont_use | `sg13cmos5l_IOPad*` | idem (`TECH(dont_use)`) | ⏳ |
| Tie | `repair_tie_fanout` hi/lo | à définir | ⏳ |
| Pré-optimisation | `remove_buffers`, `repair_design` | à définir | ⏳ |
| Densité | `global_placement -density 0.60` (2 passes : la 2ᵉ `-routability_driven -routability_check_overflow 0.30 -timing_driven`) | à définir | ⏳ |
| Optimisation | `repair_design` + `repair_timing -setup` entre les passes | à définir | ⏳ |
| Placement détaillé | `detailed_placement`, `optimize_mirroring` | à définir | ⏳ |
| CPU | 8 | à définir | ⏳ |

## 7. Arbre d'horloge (CTS)

| Paramètre | Flot open (`03_cts.tcl`) | Flot licence | Statut |
|---|---|---|---|
| Buffers | `sg13g2_buf_16/8/4/2`, racine `sg13g2_buf_8` | `TECH(cts_bufs)`, `TECH(cts_root_buf)` (mêmes valeurs) | ⏳ |
| Options | `-sink_clustering_enable -repair_clock_nets`, `repair_clock_inverters` | à définir | ⏳ |
| Après CTS | horloges propagées, `repair_timing -setup` | à définir | ⏳ |

## 8. Routage

| Paramètre | Flot open (`04_routing.tcl`) | Flot licence | Statut |
|---|---|---|---|
| Couches | signal et horloge Metal2 → TopMetal1 | à définir | ⏳ |
| Réduction de capacité | TopMetal1 0,20 (`set_global_routing_layer_adjustment`) | à définir | ⏳ |
| Optimisations | `repair_design` ; `repair_timing -setup -repair_tns 100` ; `repair_timing -hold -hold_margin 0.1 -repair_tns 100` | à définir | ⏳ |
| Antennes | `repair_antennas -ratio_margin 30 -iterations 5` | à définir | ⏳ |
| Routage détaillé | `detailed_route -drc_report_iter_step 5 -clean_patches` | à définir | ⏳ |

## 9. Finition

| Paramètre | Flot open (`05_finishing.tcl`, `klayout/run_finishing.sh`) | Flot licence | Statut |
|---|---|---|---|
| Fillers | `sg13g2_fill_8/4/2/1` (`filler_placement`) | `TECH(std_fillers)` (mêmes valeurs) | ⏳ |
| Sorties | DEF, netlist LVS (avec alim, sans fillers ni bondpads), netlist, ODB, SDC | à définir | ⏳ |
| GDS | DEF → GDS (KLayout, `def2stream.py`), seal ring, remplissage métal et activ (`--fill`) | à définir | ⏳ |

## 10. Signoff

| Vérification | Flot open | Flot licence | Statut |
|---|---|---|---|
| DRC | KLayout, règles du PDK (`klayout/run_drc.sh`, mode minimal ou complet) | à définir (Calibre / Pegasus selon disponibilité au CIME) | ⏳ |
| LVS | à confirmer | à définir | ⏳ |
| STA signoff | OpenSTA (dans OpenROAD), coins tt/ff, sur parasites **estimés** (`estimate_parasitics -global_routing`) | à définir ; arbitre commun aux deux sorties (VAL-11, voir `benchmark.md` §6) | ⏳ |
| Extraction | aucune (OpenRCX désactivé) | Quantus (pas de QRC IHP pour l'instant, D1) | ⏳ |
| Puissance | `report_power -corner tt` sans activité (`reports.tcl`) | `report_power` sans activité (Genus) | ≈ |

---

## Historique des modifications

| Date | Flot | Modification |
|---|---|---|
| 09/11/2026 | licence | Création de la structure `cadence/` et du flot Genus (étapes 01 à 04). |
| 09/11/2026 | licence | Environnement : copie versionnée de `.bashrc_cdsic617_823_isr15` (lignes csh corrigées) ; Genus 21.18 au lieu de 25.11 (lib Qt manquante). |
| 09/11/2026 | licence | Contraintes CDC appliquées en MMMC (`set_interactive_constraint_modes`). |
| 09/11/2026 | licence | `lbr_seq_in_out_phase_opto true` : bascules à preset asynchrone (MAP-2). |
| 09/11/2026 | licence | `preserve` posé sur les cellules des `tc_clk*` avant `syn_generic`. |
| 09/11/2026 | licence | Hiérarchie conservée comparée sur le nom RTL exact, comme Yosys. |
| 09/11/2026 | licence | `insert_tiehilo_cells -high/-low` ; `write_sdc -view view_tt`. |
| 09/11/2026 | les deux | Principe du benchmark : mêmes contraintes, outils libres de leurs optimisations ; profils `iso` et `max`. |
| 09/11/2026 | doc | `contraintes_flot_open.md` fusionné dans ce document. |
| 09/11/2026 | doc | Correction : le flot open n'extrait pas les parasites (OpenRCX commenté). Ajout de `benchmark.md`. |
