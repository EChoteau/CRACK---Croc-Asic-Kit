# =============================================================================
# CRACK - Flot licence (Cadence)
# config/tech/ihp130_sg13cmos5l.tcl : IHP SG13CMOS5L (techno par défaut du
#                                     flot open, CROC_PDK=sg13cmos5l)
# =============================================================================
set TECH(name)          ihp130_sg13cmos5l
set TECH(variant)       sg13cmos5l
set TECH(io_prefix)     sg13cmos5l
set TECH(tech_lef)      sg13cmos5l_tech.lef
set TECH(bondpad)       bondpad5l_70x70

# env.sh du flot open : BENDER_PDK_ARGS="-D IHP_SG13CMOS5L=1"
# -> sélectionne les pads sg13cmos5l_* dans rtl/croc_chip.sv.
# ATTENTION : la croc.flist versionnée ne contient pas ce define (elle a été
# générée pour sg13g2), on l'ajoute donc ici explicitement.
set TECH(extra_defines) [list IHP_SG13CMOS5L=1]

source [file join [file dirname [info script]] ihp130_common.tcl]
