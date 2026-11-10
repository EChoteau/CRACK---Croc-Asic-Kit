# =============================================================================
# CRACK - Genus étape 02 : lecture du RTL et élaboration
#   - mêmes fichiers / incdirs / defines que Yosys (yosys/src/croc.flist)
#     + defines propres à la techno (ex. IHP_SG13CMOS5L=1)
#   - elaborate + init_design (applique le MMMC et le SDC)
#   - contraintes CDC, dont_use, checks (VAL-01)
# =============================================================================
crack_banner "Genus 02 : lecture RTL et élaboration"

# --- Sources ---------------------------------------------------------------------
set _fl      [crack_parse_flist $DESIGN(flist) $DESIGN(flist_base)]
set _files   [dict get $_fl files]
set _incdirs [dict get $_fl incdirs]
set _defines [crack_merge_defines [dict get $_fl defines] \
                  [concat $TECH(extra_defines) $DESIGN(extra_defines)]]

crack_info "flist   : $DESIGN(flist) ([llength $_files] fichiers)"

# Noms des modules RTL (pour reconnaître les modules paramétrés, étape 03)
set DESIGN(rtl_modules) [crack_rtl_modules $_files]
crack_info "modules RTL : [llength $DESIGN(rtl_modules)]"
crack_info "defines : $_defines"

# Trace exacte de ce qui a été lu (reproductibilité / comparaison avec Yosys)
set _trace "# Sources lues par Genus\n"
foreach d $_incdirs { append _trace "+incdir+$d\n" }
foreach d $_defines { append _trace "+define+$d\n" }
foreach f $_files   { append _trace "$f\n" }
crack_write_file "$RUN(out)/rtl_sources.f" $_trace

set_db / .init_hdl_search_path $_incdirs
read_hdl -language sv -define $_defines $_files

# --- Elaboration -----------------------------------------------------------------
elaborate $DESIGN(top)
init_design

crack_report "$RUN(rpt)/02_check_unresolved.rpt"  "check_design -unresolved"
crack_report "$RUN(rpt)/02_check_design_elab.rpt" "check_design -all"

# --- Contraintes complémentaires -------------------------------------------
# CDC du DMI JTAG (best-effort, voir constraints/croc_cdc.tcl)
crack_apply_croc_cdc

# Cellules interdites (flot open : set_dont_use IOPad*)
foreach _pat $TECH(dont_use) {
    set _cells [get_db lib_cells *$_pat]
    if {[llength $_cells] == 0} {
        crack_warn "dont_use : aucune lib_cell pour '$_pat'"
    } else {
        set_db $_cells .dont_use true
        crack_info "dont_use : '$_pat' -> [llength $_cells] lib_cells"
    }
}

# Mode sans modèle de fil : wireload "Zero" de la lib sg13g2
if {$FLOW(interconnect) eq "none"} {
    if {[catch {
        set_db / .interconnect_mode wireload
        set_db [get_db designs] .force_wireload [lindex [get_db wireloads *Zero] 0]
    } err]} {
        crack_warn "wireload Zero non appliqué : $err"
    }
}

crack_report "$RUN(rpt)/02_check_timing_intent.rpt" "check_timing_intent -verbose"

# Point de reprise (permet de relancer la synthèse sans relire le RTL)
if {[catch {write_db -to_file "$RUN(out)/$DESIGN(proj_name)_elab.db"} err]} {
    crack_warn "write_db (elab) : $err"
}
