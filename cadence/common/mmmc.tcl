# =============================================================================
# CRACK - Flot licence (Cadence)
# common/mmmc.tcl : génère le fichier MMMC (Multi-Mode Multi-Corner) à partir
#                   de TECH() et du SDC du run. Syntaxe Stylus commune à
#                   Genus et Innovus -> le même fichier sert aux deux outils.
#
# Un coin = library_set + rc_corner + timing_condition + delay_corner + vue.
# Un seul mode fonctionnel "func" (le SDC de Croc).
# =============================================================================

proc crack_write_mmmc {path sdc_files} {
    global TECH

    set s ""
    append s "# MMMC généré par cadence/common/mmmc.tcl - NE PAS EDITER\n"
    append s "# Techno : $TECH(name)  coins : $TECH(corners)\n\n"

    foreach c $TECH(corners) {
        crack_check_files $TECH($c,libs) "liberty ($c)"
        append s "create_library_set -name libs_$c -timing \[list \\\n"
        foreach l $TECH($c,libs) { append s "    $l \\\n" }
        append s "\]\n"

        # rc_corner : QRC si dispo, sinon captable, sinon modèle interne
        append s "create_rc_corner -name rc_$c -temperature $TECH($c,temperature)"
        if {$TECH(qrc_tech) ne ""} {
            append s " -qrc_tech $TECH(qrc_tech)"
        } elseif {$TECH(captable) ne ""} {
            append s " -cap_table $TECH(captable)"
        }
        append s "\n"

        append s "create_timing_condition -name tc_$c -library_sets \[list libs_$c\]\n"
        append s "create_delay_corner -name dc_$c -timing_condition tc_$c -rc_corner rc_$c\n\n"
    }

    append s "create_constraint_mode -name func -sdc_files \[list [join $sdc_files { }]\]\n\n"

    foreach c $TECH(corners) {
        append s "create_analysis_view -name view_$c -constraint_mode func -delay_corner dc_$c\n"
    }

    # (pas de lmap : compatibilité Tcl 8.5 des anciennes versions d'outils)
    set setup_views [list]
    set hold_views  [list]
    foreach c $TECH(setup_corners) { lappend setup_views "view_$c" }
    foreach c $TECH(hold_corners)  { lappend hold_views  "view_$c" }
    append s "\nset_analysis_view -setup \[list $setup_views\] -hold \[list $hold_views\]\n"

    crack_write_file $path $s
    crack_info "MMMC écrit : $path (setup: $setup_views / hold: $hold_views)"
    return $path
}
