# =============================================================================
# CRACK - Flot licence (Cadence)
# config/design_croc.tcl : description du DESIGN (indépendante de la techno
#                          et de l'outil). Remplit le tableau global DESIGN().
#
# Tout ce qui est ici est repris du flot open-source de Croc (yosys/, openroad/)
# pour que le benchmark compare les outils et pas des designs différents.
# Voir doc/contraintes_flot_open.md pour la correspondance ligne à ligne.
# =============================================================================

# Racine du clone Croc (exportée par run_implem.sh)
set DESIGN(croc_root)   [crack_env_required CROC_ROOT]

# Nom de projet / top (mêmes valeurs par défaut que env.sh du flot open)
set DESIGN(proj_name)   [crack_env PROJ_NAME  "croc"]
set DESIGN(top)         [crack_env TOP_DESIGN "croc_chip"]

# -----------------------------------------------------------------------------
# Sources RTL : on lit LA MÊME file list que Yosys (générée par Bender avec
# les cibles asic/ihp13/rtl/synthesis). Les chemins y sont relatifs à yosys/.
# Si la flist est régénérée par le flot open (run_synthesis.sh --flist),
# le flot licence suit automatiquement.
# -----------------------------------------------------------------------------
set DESIGN(flist)       [crack_env CRACK_FLIST "$DESIGN(croc_root)/yosys/src/croc.flist"]
set DESIGN(flist_base)  [crack_env CRACK_FLIST_BASE "$DESIGN(croc_root)/yosys"]

# Defines ajoutés à ceux de la flist (en plus des defines propres à la techno,
# cf. TECH(extra_defines)). Vide par défaut : on garde ceux de Bender.
set DESIGN(extra_defines) [list]

# -----------------------------------------------------------------------------
# Hiérarchie conservée : copie de la liste "keep_hierarchy" de
# yosys/scripts/yosys_synthesis.tcl. Yosys aplatit tout le reste.
# Motifs appliqués aux noms de modules (voir crack_name_matches).
# -----------------------------------------------------------------------------
set DESIGN(keep_hier_modules) [list \
    croc_soc croc_domain user_domain core_wrap \
    cve2_register_file_ff cve2_cs_registers \
    dmi_jtag dm_top gpio clint bootrom obi_timer croc_idma obi_uart \
    soc_ctrl_regs \
    tc_clk* tc_sram_impl \
    cdc_reset* cdc*phase_* cdc*_src* cdc*_dst* sync \
]

# Modules dont le contenu ne doit pas être touché (cellules instanciées à la
# main dans le RTL : ihp13/tc_clk.sv instancie directement des sg13g2_*).
# Equivalent du "keep"/dont_touch respecté par Yosys.
set DESIGN(preserve_modules) [list tc_clk*]

# Macros mémoire attendues dans la netlist (contrôle VAL-01 / VAL-17)
set DESIGN(sram_cell_pattern) "RM_IHPSG13_*"
