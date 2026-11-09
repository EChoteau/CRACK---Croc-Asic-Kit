# =============================================================================
# CRACK - Flot licence (Cadence)
# config/tech/ihp130_sg13g2.tcl : IHP SG13G2 (CROC_PDK=sg13g2 du flot open)
# =============================================================================
set TECH(name)          ihp130_sg13g2
set TECH(variant)       sg13g2
set TECH(io_prefix)     sg13g2
set TECH(tech_lef)      sg13g2_tech.lef
set TECH(bondpad)       bondpad_70x70

# env.sh du flot open : BENDER_PDK_ARGS="" -> pads sg13g2_* (pas de define)
set TECH(extra_defines) [list]

source [file join [file dirname [info script]] ihp130_common.tcl]
