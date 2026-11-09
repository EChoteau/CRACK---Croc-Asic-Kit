# =============================================================================
# CRACK - Genus étape 01 : initialisation
#   - attributs globaux (efforts, comportement HDL, clock gating...)
#   - génération du SDC et du MMMC propres au run (archivés dans le run)
#   - lecture MMMC (libs par coin) et LEF (si interconnect = ple)
# =============================================================================
crack_banner "Genus 01 : initialisation"

# set_db tolérant : un attribut absent d'une version de Genus ne doit pas
# faire planter le flot, mais doit être visible dans le log.
proc crack_set_db {attr value} {
    if {[catch {set_db / .$attr $value} err]} {
        crack_warn "set_db $attr $value refusé : $err"
        return 0
    }
    return 1
}

# Rapport tolérant : une commande absente/refusée ne doit pas arrêter le flot
#   crack_report <fichier> "<commande>"
proc crack_report {file cmd} {
    if {[catch {uplevel #0 "$cmd > $file"} err]} {
        crack_warn "rapport '$cmd' impossible : $err"
        return 0
    }
    return 1
}

# --- Généralités ---------------------------------------------------------------
crack_set_db information_level        7
crack_set_db max_cpus_per_server      $FLOW(threads)
crack_set_db hdl_track_filename_row_col true    ;# lien netlist <-> ligne RTL

# --- Efforts (budget de réglage du benchmark) --------------------------------
crack_set_db syn_generic_effort $FLOW(syn_generic_effort)
crack_set_db syn_map_effort     $FLOW(syn_map_effort)
crack_set_db syn_opt_effort     $FLOW(syn_opt_effort)

# --- Lecture HDL : mêmes garde-fous que les checks Yosys (VAL-01) ----------
crack_set_db hdl_error_on_blackbox  true   ;# module non résolu = erreur
crack_set_db hdl_unconnected_value  0      ;# = "setundef -zero" de Yosys

# --- Equivalences avec le flot open ----------------------------------------
# Pas de clock gating (Yosys n'en insère pas)
crack_set_db lp_insert_clock_gating [expr {$FLOW(clock_gating) ? "true" : "false"}]
# Constantes -> cellules tie (Yosys : hilomap)
crack_set_db use_tiehilo_for_const unique
# Pas d'"assign" dans la netlist (Yosys : splitnets/clean, Innovus les aime peu)
crack_set_db remove_assigns true
# Hiérarchie : Genus ne doit pas dégrouper de lui-même, sauf mode "auto"
if {$FLOW(hier_mode) eq "auto"} {
    crack_set_db auto_ungroup both
} else {
    crack_set_db auto_ungroup none
}

# --- Contraintes et MMMC du run ------------------------------------------------
set RUN(sdc)  [crack_write_croc_sdc "$RUN(cons)/croc.sdc"]
set RUN(mmmc) [crack_write_mmmc "$RUN(cons)/croc.mmmc.tcl" [list $RUN(sdc)]]

read_mmmc $RUN(mmmc)

# --- Vues physiques ------------------------------------------------------------
if {$FLOW(interconnect) eq "ple"} {
    crack_check_files $TECH(lefs) "LEF"
    read_physical -lef $TECH(lefs)
    crack_info "LEF lus ([llength $TECH(lefs)] fichiers), estimation PLE"
} else {
    crack_warn "interconnect=none : pas de LEF, wireload 'Zero' forcé après init_design"
}
