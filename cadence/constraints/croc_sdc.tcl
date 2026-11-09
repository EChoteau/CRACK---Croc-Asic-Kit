# =============================================================================
# CRACK - Flot licence (Cadence)
# constraints/croc_sdc.tcl : génère le SDC de Croc à partir de CONSTR() et TECH()
#
# Pourquoi générer au lieu de copier constraints.sdc ?
#   - constraints.sdc du flot open fait "source src/instances.tcl", qui utilise
#     des commandes OpenROAD (get_fanin/get_fanout, noms aplatis par Yosys)
#     non portables vers Genus/Innovus ;
#   - la période de clk_sys doit varier pour le benchmark ;
#   - le SDC écrit est archivé dans le run -> protocole traçable (VAL-19).
# Le contenu reste une copie ligne à ligne de constraints.sdc (hors CDC, qui
# sont dans croc_cdc.tcl). Toute différence doit apparaître dans
# doc/contraintes_flot_open.md.
# =============================================================================

proc crack_write_croc_sdc {path} {
    global CONSTR TECH

    set sys  $CONSTR(tck_sys)
    set jtg  $CONSTR(tck_jtg)
    set rtc  $CONSTR(tck_rtc)
    set fmin $CONSTR(io_min_frac)
    set fmax $CONSTR(io_max_frac)

    set s ""
    append s "# SDC généré par cadence/constraints/croc_sdc.tcl - NE PAS EDITER\n"
    append s "# Source : openroad/src/constraints.sdc (flot open Croc)\n"
    append s "# clk_sys = $sys ns ([format %.1f [expr {1000.0 / $sys}]] MHz)\n\n"

    append s "## Charges et pilotage\n"
    append s "set_load $CONSTR(output_load) \[all_outputs\]\n"
    append s "set_driving_cell \[all_inputs\] -lib_cell $TECH(io_driving_cell) -pin $TECH(io_driving_pin)\n\n"

    append s "## Horloges\n"
    append s "create_clock -name clk_sys -period $sys \[get_ports $CONSTR(clk_sys_port)\]\n"
    append s "create_clock -name clk_jtg -period $jtg \[get_ports $CONSTR(clk_jtg_port)\]\n"
    append s "create_clock -name clk_rtc -period $rtc \[get_ports $CONSTR(clk_rtc_port)\]\n\n"

    append s "set_clock_groups -asynchronous -name clk_groups_async \\\n"
    append s "    -group {clk_rtc} -group {clk_jtg} -group {clk_sys}\n"
    append s "set_clock_uncertainty $CONSTR(clk_uncertainty) \[all_clocks\]\n"
    append s "set_clock_transition  $CONSTR(clk_transition) \[all_clocks\]\n\n"

    append s "## Resets / testmode (doivent se propager en un cycle)\n"
    set rst_dly [expr {$jtg * $CONSTR(rst_frac_jtg)}]
    append s "set_input_delay -max $rst_dly \[get_ports {rst_ni testmode_i}\]\n"
    append s "set_false_path -hold -from \[get_ports {rst_ni testmode_i}\]\n"
    append s "set_max_delay $sys -from \[get_ports {rst_ni testmode_i}\]\n\n"

    append s "## JTAG\n"
    append s "set_input_delay  -min -add_delay -clock clk_jtg [expr {$jtg * $fmin}] \[get_ports {jtag_tdi_i jtag_tms_i}\]\n"
    append s "set_input_delay  -max -add_delay -clock clk_jtg [expr {$jtg * $fmax}] \[get_ports {jtag_tdi_i jtag_tms_i}\]\n"
    append s "set_output_delay -min -add_delay -clock clk_jtg [expr {$jtg * $fmin}] \[get_ports jtag_tdo_o\]\n"
    append s "set_output_delay -max -add_delay -clock clk_jtg [expr {$jtg * $CONSTR(jtag_out_max_frac)}] \[get_ports jtag_tdo_o\]\n"
    append s "set_input_delay -max $rst_dly \[get_ports jtag_trst_ni\]\n"
    append s "set_false_path -hold -from \[get_ports jtag_trst_ni\]\n"
    append s "set_max_delay $jtg -from \[get_ports jtag_trst_ni\]\n\n"

    append s "## GPIO\n"
    append s "set_input_delay  -min -add_delay -clock clk_sys [expr {$sys * $fmin}] \[get_ports {gpio*}\]\n"
    append s "set_input_delay  -max -add_delay -clock clk_sys [expr {$sys * $fmax}] \[get_ports {gpio*}\]\n"
    append s "set_output_delay -min -add_delay -clock clk_sys [expr {$sys * $fmin}] \[get_ports {gpio*}\]\n"
    append s "set_output_delay -max -add_delay -clock clk_sys [expr {$sys * $fmax}] \[get_ports {gpio*}\]\n"
    set st [expr {$sys * $CONSTR(status_frac)}]
    append s "set_output_delay -min -add_delay -clock clk_sys $st \[get_ports {status_o unused*}\]\n"
    append s "set_output_delay -max -add_delay -clock clk_sys $st \[get_ports {status_o unused*}\]\n\n"

    append s "## UART\n"
    append s "set_input_delay  -min -add_delay -clock clk_sys [expr {$sys * $fmin}] \[get_ports uart_rx_i\]\n"
    append s "set_input_delay  -max -add_delay -clock clk_sys [expr {$sys * $fmax}] \[get_ports uart_rx_i\]\n"
    append s "set_output_delay -min -add_delay -clock clk_sys [expr {$sys * $fmin}] \[get_ports uart_tx_o\]\n"
    append s "set_output_delay -max -add_delay -clock clk_sys [expr {$sys * $fmax}] \[get_ports uart_tx_o\]\n"

    crack_write_file $path $s
    crack_info "SDC écrit : $path"
    return $path
}
