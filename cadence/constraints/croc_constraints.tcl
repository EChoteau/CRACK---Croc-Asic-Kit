# =============================================================================
# CRACK - Flot licence (Cadence)
# constraints/croc_constraints.tcl : PARAMETRES des contraintes de Croc
#
# Valeurs extraites de openroad/src/constraints.sdc (flot open) :
#   - même horloges, mêmes incertitudes, mêmes délais d'E/S (en % de période),
#   - même charge et même cellule de pilotage sur les ports.
# Seule la période de clk_sys est un paramètre du benchmark (VAL-23 :
# >= 3 fréquences par flot). Les autres valeurs ne doivent PAS être changées
# sans changer aussi le flot open.
#
# Unités : ns et pF (unités des libs sg13g2 : time_unit 1ns, cap 1pF)
# =============================================================================

# --- Horloges (constraints.sdc : TCK_SYS / TCK_JTG / TCK_RTC) ---------------
set CONSTR(tck_sys)   [crack_env CRACK_CLK_SYS_NS 10.0] ;# 100 MHz par défaut
set CONSTR(tck_jtg)   [crack_env CRACK_CLK_JTG_NS 25.0]
set CONSTR(tck_rtc)   [crack_env CRACK_CLK_RTC_NS 50.0]

set CONSTR(clk_sys_port) clk_i
set CONSTR(clk_jtg_port) jtag_tck_i
set CONSTR(clk_rtc_port) ref_clk_i

# --- Incertitude / transition sur toutes les horloges -----------------------
set CONSTR(clk_uncertainty) 0.1
set CONSTR(clk_transition)  0.2

# --- Charges et pilotage (2 pads 74HC à 5 pF + 5 pF de piste) ---------------
set CONSTR(output_load)     [expr {2 * 5.0 + 5.0}]
# cellule/pin de pilotage : TECH(io_driving_cell) / TECH(io_driving_pin)

# --- Délais d'E/S en fraction de la période de l'horloge de référence -------
set CONSTR(io_min_frac)     0.10
set CONSTR(io_max_frac)     0.30
set CONSTR(jtag_out_max_frac) 0.20
set CONSTR(status_frac)     0.10   ;# status_o / unused* : min = max = 10 %
set CONSTR(rst_frac_jtg)    0.10   ;# reset : input_delay max = 10 % de TCK_JTG

# --- CDC JTAG <-> système (set_max_delay sur les cdc_2phase du DMI) ---------
set CONSTR(cdc_max_delay)   3.0
