# =============================================================================
# CRACK - Flot licence (Cadence)
# config/flow_defaults.tcl : réglages des OUTILS (efforts, options).
#
# C'est ici que se trouve le "budget de réglage" du benchmark (ENF4, VAL-19/20).
# Toute valeur modifiée doit être notée dans le protocole AVANT la campagne.
# Chaque valeur est surchargeable par une variable d'environnement CRACK_*
# (run_implem.sh les exporte à partir de ses options).
# =============================================================================

# --- Genus : efforts (low | medium | high | express) ------------------------
# "medium" = valeurs par défaut de l'outil (pas de réglage)
set FLOW(syn_generic_effort) [crack_env CRACK_SYN_EFFORT "medium"]
set FLOW(syn_map_effort)     [crack_env CRACK_MAP_EFFORT "medium"]
set FLOW(syn_opt_effort)     [crack_env CRACK_OPT_EFFORT "medium"]

# syn_opt (optimisation incrémentale après mapping) : 1 = oui
set FLOW(run_syn_opt)        [crack_env CRACK_SYN_OPT 1]

# --- Hiérarchie --------------------------------------------------------------
#  yosys_like : garde DESIGN(keep_hier_modules), aplatit le reste (= flot open)
#  keep_all   : garde toute la hiérarchie RTL
#  auto       : laisse Genus décider (auto_ungroup)
set FLOW(hier_mode)          [crack_env CRACK_HIER_MODE "yosys_like"]

# --- Modèle d'interconnexion pendant la synthèse ----------------------------
#  ple  : lecture des LEF, estimation physique (PLE) -> plus réaliste
#  none : pas de LEF, pas de modèle de fil (proche de Yosys/ABC qui n'en a pas)
set FLOW(interconnect)       [crack_env CRACK_INTERCONNECT "ple"]

# --- Clock gating : désactivé, Yosys n'en insère pas ------------------------
set FLOW(clock_gating)       [crack_env CRACK_CLOCK_GATING 0]

# --- Divers ------------------------------------------------------------------
set FLOW(threads)            [crack_env CRACK_THREADS 8]
set FLOW(max_paths)          [crack_env CRACK_MAX_PATHS 50]
