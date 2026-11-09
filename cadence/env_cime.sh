#!/bin/bash
# =============================================================================
# CRACK - Flot licence (Cadence)
# env_cime.sh : point d'entrée de l'environnement outils au CIME
#
# Sourcé automatiquement par run_implem.sh (sauf --env / CRACK_CADENCE_ENV).
# A la main :  source cadence/env_cime.sh
#
# 1. Charge env/cds_cime_ic617_isr15.sh (copie versionnée du bashrc
#    ams_cds_isr/.bashrc_cdsic617_823_isr15 : licences, IC617, DDI 25.11...).
# 2. Surcharge Genus : Genus 25.11 de DDI 25.11 ne démarre pas sur les cimeld
#    ("libcdsQt5Core.so.5: cannot open shared object file", installation
#    incomplète, constaté le 09/11/2026). On met Genus 21.18 isr8 en tête du
#    PATH, validé sur cimeld21 (élaboration de Croc OK).
#    Pour retenter la 25.11 : export CRACK_GENUS_HOME=none avant le source.
# =============================================================================

_crack_env_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env"
# shellcheck disable=SC1091
source "$_crack_env_dir/cds_cime_ic617_isr15.sh"
unset _crack_env_dir

# --- Genus : 21.18 en priorité (voir en-tête) --------------------------------
CRACK_GENUS_HOME="${CRACK_GENUS_HOME:-/softslin/cdsgenus21_18_000_isr8}"
if [[ "$CRACK_GENUS_HOME" != "none" ]]; then
    if [[ -d "$CRACK_GENUS_HOME" ]]; then
        export GENUS_HOME="$CRACK_GENUS_HOME"
        export PATH="$GENUS_HOME/bin:$GENUS_HOME/tools/bin:$PATH"
    else
        echo "[CRACK][WARNING][ENV] CRACK_GENUS_HOME introuvable : $CRACK_GENUS_HOME" >&2
    fi
fi

for _t in genus innovus quantus qrc calibre; do
    echo "[CRACK][INFO][ENV] $(printf '%-8s' $_t): $(command -v $_t || echo 'absent')"
done
unset _t
echo "[CRACK][INFO][ENV] licences: ${LM_LICENSE_FILE:-<non défini>}"
