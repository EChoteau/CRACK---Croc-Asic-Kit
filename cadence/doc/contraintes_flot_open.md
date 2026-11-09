# Contraintes du flot open-source de Croc et leur équivalent dans le flot licence

Ce document fait la correspondance entre ce que fait le flot open (Yosys + OpenROAD,
dossiers `yosys/` et `openroad/`) et ce que fait le flot licence (`cadence/`).
Il sert de base au protocole du benchmark (VAL-19 / VAL-20) : toute différence
entre les deux flots doit apparaître ici, avec sa justification.

Sources lues : `env.sh`, `yosys/run_synthesis.sh`, `yosys/scripts/*.tcl`,
`yosys/scripts/abc-opt.script`, `yosys/src/abc.constr`, `openroad/src/constraints.sdc`,
`openroad/src/instances.tcl`, `openroad/scripts/init_tech_*.tcl`,
`openroad/scripts/0[1-4]_*.tcl`.

## 1. Design

| Élément | Flot open | Flot licence | Fichier |
|---|---|---|---|
| Top | `croc_chip` (`TOP_DESIGN`) | idem | `config/design_croc.tcl` |
| Sources RTL | `yosys/src/croc.flist` (Bender : `-t asic -t ihp13 -t rtl -t synthesis`) | **même fichier**, relu tel quel | `config/design_croc.tcl` |
| Defines | `VERILATOR=1 SYNTHESIS=1 COMMON_CELLS_ASSERTS_OFF=1 TARGET_*` + `IHP_SG13CMOS5L=1` si sg13cmos5l | idem (defines de la flist + `TECH(extra_defines)`) | `config/tech/*.tcl` |
| Hiérarchie gardée | `keep_hierarchy` sur croc_soc, croc_domain, user_domain, core_wrap, cve2_register_file_ff, cve2_cs_registers, dmi_jtag, dm_top, gpio, clint, bootrom, obi_timer, croc_idma, obi_uart, soc_ctrl_regs, tc_clk\*, tc_sram_impl, cdc_reset\*, cdc\*phase_\*, cdc\*_src\*, cdc\*_dst\*, sync ; le reste aplati | même liste, mode `yosys_like` : dégroupage de tout le reste après `syn_generic` | `config/design_croc.tcl`, `genus/scripts/03_synthesis.tcl` |
| SRAM | macros `RM_IHPSG13_1P_*` (2 bancs 512x32 dans la config par défaut) | idem (mêmes libs/LEF) | – |

> ⚠️ La `croc.flist` versionnée ne contient pas `IHP_SG13CMOS5L` (elle a été générée
> pour sg13g2). `run_synthesis.sh --synth` la régénère à chaque run open. Le flot
> licence ajoute le define via la config techno pour ne pas dépendre de cet état.

## 2. Technologie et coins

| Élément | Flot open | Flot licence |
|---|---|---|
| Vues | `technology/` si présent, sinon `ihp13/pdk/` (miroir public) | idem |
| Coin de synthèse | Yosys/ABC : **tt** seul (`sg13g2_stdcell_typ_1p20V_25C`) | vue setup = **tt** |
| Coins d'analyse | OpenROAD : `define_corners tt ff` | MMMC : tt (setup), ff (hold) |
| Coin slow | **absent** du miroir public | option `CRACK_ENABLE_SS=1` (PDK complet, hors benchmark) |
| Modèle RC | `set_wire_rc -layer Metal3` (estimation), OpenRCX à la fin | pas de QRC (D1) : modèle interne Genus (PLE via LEF) |
| dont_use | `set_dont_use *_IOPad*` (au P&R) ; aucun en synthèse | `*_IOPad*` dès la synthèse |
| Tie cells | `hilomap` sg13g2_tiehi/L_HI, sg13g2_tielo/L_LO | `insert_tiehilo_cells` mêmes cellules |
| Cellules dont_use de la lib | antennanp, decap_4/8, fill_1/2 (attribut de la lib) | idem (lu dans la lib) |

## 3. Contraintes de timing (`openroad/src/constraints.sdc`)

| Contrainte | Valeur |
|---|---|
| `clk_sys` sur `clk_i` | **10 ns (100 MHz)** – paramètre du benchmark (`--clk`) |
| `clk_jtg` sur `jtag_tck_i` | 25 ns |
| `clk_rtc` sur `ref_clk_i` | 50 ns |
| Groupes | rtc / jtg / sys asynchrones entre eux |
| Incertitude / transition horloges | 0,1 ns / 0,2 ns |
| Charge sorties | 15 pF (2 × 5 pF + 5 pF) |
| Pilotage entrées | `<io>_IOPadOut16mA`, pin `pad` |
| `rst_ni`, `testmode_i` | input_delay max 10 % TCK_JTG, false_path hold, max_delay TCK_SYS |
| JTAG tdi/tms | in min 10 % / max 30 % TCK_JTG ; tdo out min 10 % / max 20 % |
| `jtag_trst_ni` | input_delay max 10 % TCK_JTG, false_path hold, max_delay TCK_JTG |
| GPIO | in/out min 10 % / max 30 % TCK_SYS |
| `status_o`, `unused*` | out min = max = 10 % TCK_SYS |
| UART | in/out min 10 % / max 30 % TCK_SYS |
| CDC DMI (req/resp) | `set_max_delay 3.0 -ignore_clock_latency` sur les chemins async des `cdc_2phase` |

Dans le flot licence ces valeurs sont dans `constraints/croc_constraints.tcl`, le
SDC est **généré** par `constraints/croc_sdc.tcl` et archivé dans chaque run
(`runs/<run>/constraints/croc.sdc`).

**Écart connu – CDC** : le flot open trouve les bascules CDC avec `get_fanin`/`get_fanout`
(commandes OpenROAD) sur les noms aplatis par Yosys. Le flot licence utilise
`all_fanin`/`all_fanout` (SDC standard) sur les ports `async*` des sous-blocs
`cdc_2phase` conservés (`constraints/croc_cdc.tcl`). Si aucun port n'est trouvé, un
WARNING est émis et l'écart va au journal. Impact faible : ces chemins sont de toute
façon exclus par `set_clock_groups -asynchronous` dans les deux flots.

## 4. Différences inhérentes aux outils (à documenter dans le rapport)

| Point | Flot open | Flot licence | Commentaire |
|---|---|---|---|
| Contraintes en synthèse | **pas de SDC** : ABC optimise pour un délai cible `-D 10000` ps, avec `abc.constr` (driving cell `sg13g2_buf_1`, charge 0,015 pF) | SDC complet dès la synthèse | Le SDC n'est appliqué qu'au P&R côté open. Comparer les flots **après routage**, avec le même SDC. Pour un balayage de fréquence, penser à faire varier aussi `period_ps` de `yosys_synthesis.tcl` côté open. |
| Effort d'optimisation | script ABC fixe (LMS, 8 itérations) | efforts Genus `medium` (défaut outil) | budget de réglage à figer dans le protocole |
| Clock gating | non | désactivé | identique |
| Modèle de fil en synthèse | aucun | PLE (LEF) ; `--interconnect none` force le wireload `Zero` | `none` = plus proche de Yosys |
| DFT / scan | non | non | identique |

## 5. Paramètres P&R du flot open (pour la suite, Innovus)

| Élément | Valeur open |
|---|---|
| Die | 1916 × 1916 µm |
| Marge cœur | padD 180 + padBond 70 + powerRing 80 = 330 µm |
| Site | `CoreSite` |
| Densité placement | `global_placement -density 0.60` (timing + routability driven) |
| CTS | buffers sg13g2_buf_16/8/4/2, racine buf_8 |
| Routage | Metal2 → TopMetal1, ajustement TopMetal1 0,20 |
| Hold | `repair_timing -hold -hold_margin 0.1` |
| Antennes | `repair_antennas -ratio_margin 30` |
| Padring / macros | `openroad/src/padring.tcl`, placement manuel des SRAM dans `01_floorplan.tcl` |
