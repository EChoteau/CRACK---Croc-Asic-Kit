# =============================================================================
# CRACK - Flot licence (Cadence)
# config/tech/ams035.tcl : AMS 0.35 µm (kit CIME) - GABARIT, A COMPLETER (lot 5)
#
# ENF3 : aucun fichier du kit dans le dépôt. Tous les chemins partent de
# AMS_KIT_ROOT (à exporter dans l'environnement CIME, pas dans git).
# Les noms de fichiers/cellules ci-dessous sont des PLACEHOLDERS (<...>) à
# remplacer après l'étude du kit (tâche 5.1).
# =============================================================================
set TECH(name)          ams035
set TECH(variant)       ams035
set TECH(io_prefix)     "<AMS_IO_PREFIX>"
set TECH(extra_defines) [list TARGET_AMS035=1]

set _kit [crack_env AMS_KIT_ROOT ""]
if {$_kit eq ""} {
    crack_error "AMS_KIT_ROOT non défini : chemin du kit AMS 0.35 au CIME"
}
set TECH(libs_root) $_kit
set TECH(pdk_root)  $_kit

# --- Coins (à adapter aux libs du kit : typ / worst / best) ------------------
set TECH(corners)        [list tt ff]
set TECH(tt,temperature) 25
set TECH(tt,libs)        [list "$_kit/<chemin>/<CORELIB_TYP>.lib"]
set TECH(ff,temperature) -40
set TECH(ff,libs)        [list "$_kit/<chemin>/<CORELIB_BEST>.lib"]
set TECH(setup_corners)  [list tt]
set TECH(hold_corners)   [list ff]

set TECH(qrc_tech)  ""
set TECH(captable)  [crack_env CRACK_AMS_CAPTABLE ""]

# --- LEF -----------------------------------------------------------------
set TECH(lefs) [list \
    "$_kit/<chemin>/<tech>.lef" \
    "$_kit/<chemin>/<corelib>.lef" ]

# --- Cellules ------------------------------------------------------------
set TECH(dont_use)        [list]
set TECH(tiehi_cell)      "<TIEHI>"
set TECH(tiehi_pin)       "<Q>"
set TECH(tielo_cell)      "<TIELO>"
set TECH(tielo_pin)       "<Q>"
set TECH(io_driving_cell) "<BUF_IO>"
set TECH(io_driving_pin)  "<PAD>"
set TECH(cts_bufs)        [list]
set TECH(cts_root_buf)    ""
set TECH(std_fillers)     [list]
set TECH(core_site)       "<SITE>"
set TECH(power_net)       vdd!
set TECH(ground_net)      gnd!

crack_error "config/tech/ams035.tcl n'est pas encore rempli (lot 5)"
