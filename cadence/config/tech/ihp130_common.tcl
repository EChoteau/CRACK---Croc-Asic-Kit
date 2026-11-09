# =============================================================================
# CRACK - Flot licence (Cadence)
# config/tech/ihp130_common.tcl : partie commune aux deux variantes IHP130
#   (sg13g2 et sg13cmos5l partagent les cellules standard et les SRAM sg13g2,
#    seuls la tech LEF, les IO et le bondpad changent).
#
# Ce fichier est sourcé par ihp130_sg13g2.tcl / ihp130_sg13cmos5l.tcl, qui
# définissent avant lui : TECH(variant), TECH(io_prefix), TECH(tech_lef),
#                         TECH(bondpad), TECH(extra_defines)
#
# Fichiers : les mêmes que le flot open (miroir public ihp13/pdk, ou le
# répertoire technology/ s'il existe, exactement comme env.sh).
# =============================================================================

set _croc_root [crack_env_required CROC_ROOT]

# --- Racine des vues (lib/lef/gds/verilog) ----------------------------------
if {[file exists "$_croc_root/technology"]} {
    set _default_libs_root "$_croc_root/technology"
} else {
    set _default_libs_root "$_croc_root/ihp13/pdk"
}
set TECH(libs_root)  [crack_env CRACK_IHP_LIBS_ROOT $_default_libs_root]
set _lib "$TECH(libs_root)/lib"
set _lef "$TECH(libs_root)/lef"

# PDK IHP complet cloné au CIME (QRC, DRC/LVS, coin slow...). Optionnel ici.
set TECH(pdk_root)   [crack_env IHP_PDK_ROOT ""]

# -----------------------------------------------------------------------------
# Coins PVT
# Le flot open (openroad/scripts/init_tech_*.tcl) définit UNIQUEMENT :
#   tt : typ 1.20 V 25 °C   (Yosys synthétise sur ce coin)
#   ff : fast 1.32 V -40 °C (SRAM : fast 1.32 V -55 °C)
# Le miroir public ne contient pas de coin slow. On garde la même chose par
# défaut pour le benchmark ; le coin ss est une option (CRACK_ENABLE_SS=1)
# qui demande IHP_PDK_ROOT (PDK complet) -> à valider en phase 0.
# -----------------------------------------------------------------------------
set TECH(corners) [list tt ff]

set TECH(tt,temperature) 25
set TECH(tt,libs) [concat \
    [list "$_lib/sg13g2_stdcell_typ_1p20V_25C.lib"] \
    [list "$_lib/$TECH(io_prefix)_io_typ_1p2V_3p3V_25C.lib"] \
    [crack_glob $_lib "RM_IHPSG13_*_typ_1p20V_25C.lib"] ]

set TECH(ff,temperature) -40
set TECH(ff,libs) [concat \
    [list "$_lib/sg13g2_stdcell_fast_1p32V_m40C.lib"] \
    [list "$_lib/$TECH(io_prefix)_io_fast_1p32V_3p6V_m40C.lib"] \
    [crack_glob $_lib "RM_IHPSG13_*_fast_1p32V_m55C.lib"] ]

if {[crack_env CRACK_ENABLE_SS 0]} {
    if {$TECH(pdk_root) eq ""} {
        crack_error "CRACK_ENABLE_SS=1 demande IHP_PDK_ROOT (PDK IHP complet)"
    }
    # Chemins du dépôt IHP-Open-PDK : à vérifier sur le clone du CIME
    set _ref "$TECH(pdk_root)/ihp-sg13g2/libs.ref"
    lappend TECH(corners) ss
    set TECH(ss,temperature) 125
    set TECH(ss,libs) [concat \
        [list "$_ref/sg13g2_stdcell/lib/sg13g2_stdcell_slow_1p08V_125C.lib"] \
        [crack_glob "$_ref/sg13g2_io/lib" "sg13g2_io_slow_*.lib"] \
        [crack_glob "$_ref/sg13g2_sram/lib" "RM_IHPSG13_*_slow_*.lib"] ]
}

# Coins utilisés pour l'analyse setup / hold
#   flot open : OpenSTA vérifie setup ET hold sur tt et ff ; Yosys optimise
#   sur tt. On optimise donc le setup sur tt (et ss si activé), hold sur ff.
set TECH(setup_corners) [list tt]
if {[lsearch $TECH(corners) ss] >= 0} { lappend TECH(setup_corners) ss }
set TECH(hold_corners)  [list ff]

# -----------------------------------------------------------------------------
# Extraction RC
# Pas de fichier QRC/captable IHP disponible pour l'instant (hypothèse H2,
# décision D1). Laisser vide = Genus/Innovus utilisent leur modèle interne
# basé sur la tech LEF. Le flot open utilise set_wire_rc -layer Metal3.
# -----------------------------------------------------------------------------
set TECH(qrc_tech)  [crack_env CRACK_IHP_QRC ""]
set TECH(captable)  [crack_env CRACK_IHP_CAPTABLE ""]

# -----------------------------------------------------------------------------
# Vues physiques (LEF). Ordre : tech LEF en premier.
# -----------------------------------------------------------------------------
set TECH(lefs) [concat \
    [list "$_lef/$TECH(tech_lef)"] \
    [list "$_lef/sg13g2_stdcell.lef"] \
    [list "$_lef/$TECH(io_prefix)_io.lef"] \
    [list "$_lef/$TECH(bondpad).lef"] \
    [crack_glob $_lef "RM_IHPSG13_*.lef"] ]

# -----------------------------------------------------------------------------
# Cellules (mêmes choix que init_tech_*.tcl du flot open)
# -----------------------------------------------------------------------------
# Interdites à la synthèse / optimisation (open : set_dont_use IOPad*)
set TECH(dont_use)        [list "$TECH(io_prefix)_IOPad*"]

# Cellules de tie (Yosys : hilomap ; OpenROAD : repair_tie_fanout)
set TECH(tiehi_cell)      sg13g2_tiehi
set TECH(tiehi_pin)       L_HI
set TECH(tielo_cell)      sg13g2_tielo
set TECH(tielo_pin)       L_LO

# Cellule qui pilote les entrées (SDC open : set_driving_cell ... -pin pad)
set TECH(io_driving_cell) "$TECH(io_prefix)_IOPadOut16mA"
set TECH(io_driving_pin)  pad

# Pour Innovus (étapes suivantes) : CTS, fillers, sites
set TECH(cts_bufs)        [list sg13g2_buf_16 sg13g2_buf_8 sg13g2_buf_4 sg13g2_buf_2]
set TECH(cts_root_buf)    sg13g2_buf_8
set TECH(std_fillers)     [list sg13g2_fill_8 sg13g2_fill_4 sg13g2_fill_2 sg13g2_fill_1]
set TECH(core_site)       CoreSite

# Alimentations (noms des pg_pin des libs sg13g2)
set TECH(power_net)       VDD
set TECH(ground_net)      VSS
