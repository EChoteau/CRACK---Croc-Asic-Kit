# =============================================================================
# CRACK - Flot licence (Cadence)
# genus/scripts/genus_main.tcl : point d'entrée Genus (mode Stylus)
#
# Lancé par run_implem.sh, depuis <run>/genus/ :
#   genus -batch -files genus_main.tcl -log logs/genus
#
# Enchaîne les étapes (un fichier par étape, sourcé dans l'ordre) :
#   01_init       attributs, SDC + MMMC du run, lecture libs/LEF
#   02_elaborate  lecture RTL (flist du flot open), elaborate, init_design
#   03_synthesis  syn_generic -> hiérarchie -> syn_map -> syn_opt
#   04_export     rapports, netlist, SDC, base Innovus, dofile LEC
#
# CRACK_GENUS_STOP=<étape> arrête après cette étape (debug), ex. 02_elaborate.
# CRACK_GENUS_INTERACTIVE=1 : ne quitte pas Genus à la fin (lancer sans -batch).
# =============================================================================

# --- Chemins -----------------------------------------------------------------
set CRACK_ROOT [file normalize [expr {[info exists ::env(CRACK_ROOT)] \
    ? $::env(CRACK_ROOT) : [file join [file dirname [info script]] .. ..]}]]
set GENUS_SCRIPTS "$CRACK_ROOT/genus/scripts"

source "$CRACK_ROOT/common/utils.tcl"
source "$CRACK_ROOT/common/mmmc.tcl"

set RUN(dir)        [crack_env_required CRACK_RUN_DIR]
set RUN(tech)       [crack_env_required CRACK_TECH]
set RUN(stop_after) [crack_env CRACK_GENUS_STOP ""]
set RUN(rpt)        "$RUN(dir)/genus/reports"
set RUN(out)        "$RUN(dir)/genus/out"
set RUN(cons)       "$RUN(dir)/constraints"
foreach d [list $RUN(rpt) $RUN(out) $RUN(cons)] { file mkdir $d }

# --- Configuration (design -> outils -> techno -> contraintes) --------------
source "$CRACK_ROOT/config/design_croc.tcl"
source "$CRACK_ROOT/config/flow_defaults.tcl"
set _tech_cfg "$CRACK_ROOT/config/tech/$RUN(tech).tcl"
crack_check_files [list $_tech_cfg] "config techno"
source $_tech_cfg
source "$CRACK_ROOT/constraints/croc_constraints.tcl"
source "$CRACK_ROOT/constraints/croc_sdc.tcl"
source "$CRACK_ROOT/constraints/croc_cdc.tcl"

crack_banner "Genus : $DESIGN(top) / $TECH(name) / clk_sys $CONSTR(tck_sys) ns"
crack_info "Run     : $RUN(dir)"
crack_info "Profil  : $FLOW(profile)"
crack_info "Efforts : generic=$FLOW(syn_generic_effort) map=$FLOW(syn_map_effort) opt=$FLOW(syn_opt_effort) incr=$FLOW(syn_opt_incr)"
crack_info "Hiérarchie : $FLOW(hier_mode)   interconnect : $FLOW(interconnect)"

# --- Exécution des étapes -----------------------------------------------------
set _t0 [clock seconds]
foreach step {01_init 02_elaborate 03_synthesis 04_export} {
    set _ts [clock seconds]
    source "$GENUS_SCRIPTS/$step.tcl"
    crack_info "Etape $step terminée en [expr {[clock seconds] - $_ts}] s"
    if {$RUN(stop_after) eq $step} {
        crack_warn "Arrêt demandé après $step (CRACK_GENUS_STOP)"
        break
    }
}
set RUN(runtime_s) [expr {[clock seconds] - $_t0}]
crack_info "Durée totale Genus : $RUN(runtime_s) s"

# Temps de run archivé pour le benchmark (métrique VAL-22)
crack_write_file "$RUN(rpt)/runtime.txt" "genus_runtime_s $RUN(runtime_s)\n"

if {![crack_env CRACK_GENUS_INTERACTIVE 0]} {
    exit
}
