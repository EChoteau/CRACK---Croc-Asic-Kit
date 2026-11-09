# =============================================================================
# CRACK - Genus étape 04 : rapports et sorties
#
# Rapports (noms stables -> script d'extraction des métriques, VAL-22) :
#   04_check_design.rpt     checks finaux (VAL-01)
#   04_area.rpt / gates     surface et nombre de cellules (VAL-02)
#   04_timing_<vue>.rpt     chemins critiques par vue
#   04_qor.rpt              synthèse WNS/TNS/surface
#   04_power.rpt            puissance (vectorless, indicative)
#   04_registers.rpt        liste des registres
#   04_macros.rpt           instances SRAM / IO (VAL-01, VAL-17)
# Sorties :
#   <proj>_genus.v          netlist (entrée Innovus + simu gate-level VAL-04)
#   <proj>_genus.sdc        SDC écrit par Genus
#   innovus/<proj>          base pour Innovus (write_design -innovus)
#   <proj>_genus.db         base Genus
#   lec_rtl2gate.do         dofile Conformal LEC (VAL-03)
# =============================================================================
crack_banner "Genus 04 : rapports et sorties"

set _p $DESIGN(proj_name)

# --- Rapports --------------------------------------------------------------------
crack_report "$RUN(rpt)/04_check_design.rpt"   "check_design -all"
crack_report "$RUN(rpt)/04_area.rpt"           "report_area"
crack_report "$RUN(rpt)/04_area_hier.rpt"      "report_area -depth 3"
crack_report "$RUN(rpt)/04_gates.rpt"          "report_gates"
crack_report "$RUN(rpt)/04_qor.rpt"            "report_qor"
crack_report "$RUN(rpt)/04_timing.rpt"         "report_timing -max_paths $FLOW(max_paths)"
crack_report "$RUN(rpt)/04_timing_summary.rpt" "report_timing_summary"
crack_report "$RUN(rpt)/04_power.rpt"          "report_power"
crack_report "$RUN(rpt)/04_clocks.rpt"         "report_clocks"

# Timing par vue (setup + hold)
foreach _c $TECH(corners) {
    crack_report "$RUN(rpt)/04_timing_view_${_c}.rpt" \
        "report_timing -view view_${_c} -max_paths 10"
}

# Registres et macros (équivalents de <proj>_registers.rpt / _instances.rpt Yosys)
if {[catch {
    set _regs [get_db insts -if {.is_sequential == true}]
    set _s "# [llength $_regs] éléments séquentiels\n"
    foreach _i $_regs { append _s "[get_db $_i .name] [get_db $_i .base_cell.name]\n" }
    crack_write_file "$RUN(rpt)/04_registers.rpt" $_s
} err]} {
    crack_warn "liste des registres : $err"
}

set _s "# Macros (SRAM / IO / bondpads)\n"
foreach _i [get_db insts] {
    set _bc [get_db $_i .base_cell.name]
    if {[string match $DESIGN(sram_cell_pattern) $_bc] || [string match "*IOPad*" $_bc] \
        || [string match "bondpad*" $_bc]} {
        append _s "[get_db $_i .name] $_bc\n"
    }
}
crack_write_file "$RUN(rpt)/04_macros.rpt" $_s

# --- Sorties -------------------------------------------------------------------
write_hdl > "$RUN(out)/${_p}_genus.v"
write_sdc > "$RUN(out)/${_p}_genus.sdc"

if {[catch {write_design -innovus -base_name "$RUN(out)/innovus/${_p}"} err]} {
    crack_warn "write_design -innovus : $err"
}
if {[catch {write_db -to_file "$RUN(out)/${_p}_genus.db"} err]} {
    crack_warn "write_db : $err"
}
# Dofile Conformal LEC RTL -> netlist (VAL-03)
if {[catch {
    write_do_lec -revised_design "$RUN(out)/${_p}_genus.v" \
        -logfile "$RUN(dir)/genus/logs/lec_rtl2gate.log" > "$RUN(out)/lec_rtl2gate.do"
} err]} {
    crack_warn "write_do_lec : $err"
}

# Infos outil pour l'archivage (VAL-19, nommage/traçabilité du run)
set _ver "inconnue"
catch {set _ver [get_db / .program_version]}
crack_write_file "$RUN(rpt)/tool_version.txt" "genus $_ver\n"

crack_info "Netlist : $RUN(out)/${_p}_genus.v"
