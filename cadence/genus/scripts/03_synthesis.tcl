# =============================================================================
# CRACK - Genus étape 03 : synthèse
#   preserve -> syn_generic -> hiérarchie -> syn_map -> syn_opt -> cellules tie
#
# Ordre calqué sur yosys_synthesis.tcl : optimisation générique avec la
# hiérarchie RTL, PUIS aplatissement (sauf modules "keep"), PUIS mapping.
# =============================================================================
crack_banner "Genus 03 : synthèse"

# -----------------------------------------------------------------------------
# Preserve des cellules instanciées à la main (tc_clk* : sg13g2_* dans le RTL)
#   Genus refuse "preserve" sur un bloc hiérarchique non entièrement mappé
#   (TUI-214). On le pose donc sur les CELLULES feuilles de ces blocs, qui
#   sont déjà des cellules de la lib dès l'élaboration. Fait AVANT syn_generic
#   pour qu'aucune optimisation ne les touche (= "keep" côté Yosys).
# -----------------------------------------------------------------------------
proc crack_genus_preserve {preserve_patterns rtl_modules} {
    set n_cells 0
    foreach h [get_db hinsts] {
        if {![crack_name_matches [get_db $h .module.name] $preserve_patterns $rtl_modules]} { continue }
        set cells [list]
        if {[catch {set cells [get_db $h .insts]} err]} {
            crack_warn "preserve : cellules de [get_db $h .name] illisibles ($err)"
            continue
        }
        foreach c $cells {
            if {[catch {set_db $c .preserve true} err]} {
                crack_warn "preserve impossible sur [get_db $c .name] ($err) -> journal des écarts"
            } else {
                incr n_cells
            }
        }
        crack_info "preserve : [get_db $h .name] ([llength $cells] cellule(s))"
    }
    crack_info "preserve : $n_cells cellule(s) au total"
}

# -----------------------------------------------------------------------------
# Hiérarchie (mode yosys_like) : on dégroupe tout ce qui n'est pas dans
# keep_hier_modules, niveau par niveau (comme "flatten" + keep_hierarchy de
# Yosys). Les modules sont reconnus par leur nom RTL d'origine.
# -----------------------------------------------------------------------------
proc crack_genus_hierarchy {mode keep_patterns rtl_modules rpt_file} {
    if {$mode ne "yosys_like"} {
        crack_info "Hiérarchie : mode '$mode', pas de dégroupage explicite"
    } else {
        # A chaque passe : dégroupe les instances non gardées dont le parent
        # est le top ou une instance gardée. Leurs enfants remontent d'un
        # niveau et sont traités à la passe suivante.
        for {set pass 1} {$pass <= 50} {incr pass} {
            set todo [list]
            foreach h [get_db hinsts] {
                if {[crack_name_matches [get_db $h .module.name] $keep_patterns $rtl_modules]} { continue }
                set p [get_db $h .parent]
                if {[get_db $p .obj_type] eq "design" || \
                    [crack_name_matches [get_db $p .module.name] $keep_patterns $rtl_modules]} {
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

    # Rapport de la hiérarchie finale (à comparer avec celle de Yosys)
    set s "# instance | module Genus | module RTL\n"
    foreach h [get_db hinsts] {
        set m [get_db $h .module.name]
        append s "[get_db $h .name] | $m | [crack_module_base $m $rtl_modules]\n"
    }
    crack_write_file $rpt_file $s
    crack_info "Hiérarchie finale : [llength [get_db hinsts]] instance(s) -> $rpt_file"
}

# --- 0. Preserve ---------------------------------------------------------------
crack_genus_preserve $DESIGN(preserve_modules) $DESIGN(rtl_modules)

# --- 1. Optimisation générique ---------------------------------------------------
syn_generic
crack_report "$RUN(rpt)/03_generic_area.rpt"     "report_area"
crack_report "$RUN(rpt)/03_generic_datapath.rpt" "report_dp"

# --- 2. Hiérarchie ---------------------------------------------------------------
crack_genus_hierarchy $FLOW(hier_mode) $DESIGN(keep_hier_modules) \
    $DESIGN(rtl_modules) "$RUN(rpt)/03_hierarchy.rpt"

# --- 3. Mapping sur la techno ------------------------------------------------
syn_map
crack_report "$RUN(rpt)/03_map_timing.rpt" "report_timing -max_paths 10"
crack_report "$RUN(rpt)/03_map_area.rpt"   "report_area"

# --- 4. Optimisation incrémentale ----------------------------------------------
if {$FLOW(run_syn_opt)} {
    syn_opt
    if {$FLOW(syn_opt_incr)} {
        crack_info "Profil $FLOW(profile) : passe syn_opt -incremental"
        if {[catch {syn_opt -incremental} err]} {
            crack_warn "syn_opt -incremental : $err"
        }
    }
} else {
    crack_warn "syn_opt désactivé (CRACK_SYN_OPT=0)"
}

# --- 5. Cellules tie (Yosys : hilomap -hicell sg13g2_tiehi L_HI ...) ----------
# Options Genus 21 : -high / -low (-hi est ambigu avec -high_low)
if {[catch {
    insert_tiehilo_cells -high $TECH(tiehi_cell) -low $TECH(tielo_cell) -all -verbose
} err]} {
    crack_warn "insert_tiehilo_cells avec cellules explicites refusé ($err), essai par défaut"
    if {[catch {insert_tiehilo_cells -all -verbose} err2]} {
        crack_warn "insert_tiehilo_cells : $err2"
    }
}
