# =============================================================================
# CRACK - Genus étape 03 : synthèse
#   syn_generic -> gestion de hiérarchie -> syn_map -> syn_opt -> cellules tie
#
# Ordre calqué sur yosys_synthesis.tcl : optimisation générique avec la
# hiérarchie RTL, PUIS aplatissement (sauf modules "keep"), PUIS mapping.
# =============================================================================
crack_banner "Genus 03 : synthèse"

# -----------------------------------------------------------------------------
# Gestion de la hiérarchie
#   preserve   : modules à cellules instanciées à la main (tc_clk*)
#   yosys_like : on dégroupe tout ce qui n'est pas dans keep_hier_modules,
#                niveau par niveau (comme "flatten" + keep_hierarchy de Yosys)
# -----------------------------------------------------------------------------
proc crack_genus_hierarchy {mode keep_patterns preserve_patterns rpt_file} {
    # 1. preserve
    set n_pres 0
    foreach h [get_db hinsts] {
        if {[crack_name_matches [get_db $h .module.name] $preserve_patterns]} {
            set_db $h .preserve true
            incr n_pres
        }
    }
    crack_info "Hiérarchie : $n_pres instance(s) preserve"

    if {$mode ne "yosys_like"} {
        crack_info "Hiérarchie : mode '$mode', pas de dégroupage explicite"
    } else {
        # 2. dégroupage itératif : à chaque passe, on dégroupe les instances non
        #    gardées dont le parent est le top ou une instance gardée. Leurs
        #    enfants remontent d'un niveau et sont traités à la passe suivante.
        for {set pass 1} {$pass <= 50} {incr pass} {
            set todo [list]
            foreach h [get_db hinsts] {
                if {[crack_name_matches [get_db $h .module.name] $keep_patterns]} { continue }
                set p [get_db $h .parent]
                if {[get_db $p .obj_type] eq "design" || \
                    [crack_name_matches [get_db $p .module.name] $keep_patterns]} {
                    lappend todo $h
                }
            }
            if {[llength $todo] == 0} { break }
            crack_info "Hiérarchie passe $pass : dégroupage de [llength $todo] instance(s)"
            if {[catch {ungroup $todo} err]} {
                # une instance récalcitrante ne doit pas bloquer les autres
                foreach h $todo {
                    if {[catch {ungroup $h} err2]} {
                        crack_warn "ungroup impossible : [get_db $h .name] ($err2)"
                    }
                }
            }
        }
    }

    # 3. rapport de la hiérarchie finale (à comparer avec celle de Yosys)
    set s "# instance | module\n"
    foreach h [get_db hinsts] {
        append s "[get_db $h .name] | [get_db $h .module.name]\n"
    }
    crack_write_file $rpt_file $s
    crack_info "Hiérarchie finale : [llength [get_db hinsts]] instance(s) -> $rpt_file"
}

# --- 1. Optimisation générique ---------------------------------------------------
syn_generic
crack_report "$RUN(rpt)/03_generic_area.rpt"     "report_area"
crack_report "$RUN(rpt)/03_generic_datapath.rpt" "report_dp"

# --- 2. Hiérarchie ---------------------------------------------------------------
crack_genus_hierarchy $FLOW(hier_mode) $DESIGN(keep_hier_modules) \
    $DESIGN(preserve_modules) "$RUN(rpt)/03_hierarchy.rpt"

# --- 3. Mapping sur la techno ------------------------------------------------
syn_map
crack_report "$RUN(rpt)/03_map_timing.rpt" "report_timing -max_paths 10"
crack_report "$RUN(rpt)/03_map_area.rpt"   "report_area"

# --- 4. Optimisation incrémentale ----------------------------------------------
if {$FLOW(run_syn_opt)} {
    syn_opt
} else {
    crack_warn "syn_opt désactivé (CRACK_SYN_OPT=0)"
}

# --- 5. Cellules tie (Yosys : hilomap -hicell sg13g2_tiehi L_HI ...) ----------
if {[catch {
    insert_tiehilo_cells -hi $TECH(tiehi_cell) -lo $TECH(tielo_cell) -all -verbose
} err]} {
    crack_warn "insert_tiehilo_cells avec cellules explicites refusé ($err), essai par défaut"
    if {[catch {insert_tiehilo_cells -all -verbose} err2]} {
        crack_warn "insert_tiehilo_cells : $err2"
    }
}
