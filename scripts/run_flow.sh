#!/usr/bin/env bash
# =============================================================================
# runflow.sh : flot open-source Croc (IHP130 sg13cmos5l), construit étape par étape
#
# A LANCER DANS LE CONTENEUR (iic-osic-tools), pas sur l'hôte.
#
# Usage :
#   ./scripts/runflow.sh synth          # une étape
#   ./scripts/runflow.sh all            # toutes les étapes déjà implémentées
#
# Chaque run produit un dossier logs/<RUN_ID>/ contenant :
#   versions.txt  : versions des outils et commit du dépôt (traçabilité)
#   <étape>.log   : log complet de l'étape
#   timing.txt    : durée de chaque étape (métrique "temps de run", VAL-22)
#   checks.txt    : résultat des vérifications (VAL-01, VAL-02, ...)
#   checksums.txt : sommes SHA-256 des fichiers produits (reproductibilité)
#
# Etapes implémentées : synth
# A ajouter (une fois validées à la main) : backend, finish, drc
# =============================================================================
set -euo pipefail   # arrêt à la 1re erreur, variable non définie = erreur,
                    # et code retour d'un pipe = celui de la commande qui échoue

# --- Configuration -----------------------------------------------------------
# Racine du dépôt déduite de l'emplacement du script (pas de chemin en dur)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLOW="open"                    # open | licence
TECH="ihp130"                  # ihp130 | ams035
RUN_ID="${RUN_ID:-${FLOW}_${TECH}_$(date +%Y%m%d_%H%M)}"
LOGDIR="$ROOT/logs/$RUN_ID"

# Fichiers produits par la synthèse (chemins relatifs à $ROOT)
SYNTH_NETLIST="yosys/out/croc_yosys.v"

mkdir -p "$LOGDIR"

# --- Fonctions utilitaires ---------------------------------------------------

# log_check <ID> <statut> <message> : écrit une ligne dans checks.txt et à l'écran
# statuts du plan de validation : OK | ECART | ECHEC
log_check() {
  echo "[CHECK] $1 : $2 : $3" | tee -a "$LOGDIR/checks.txt"
}

# run_step <nom> <dossier> <commande...> : exécute une commande dans un dossier,
# enregistre son log et sa durée. Une erreur arrête tout le flot.
run_step() {
  local name=$1 dir=$2; shift 2
  local t0; t0=$(date +%s)
  echo "[FLOW] >>> $name"
  ( cd "$ROOT/$dir" && "$@" ) 2>&1 | tee "$LOGDIR/$name.log"
  echo "$name : $(( $(date +%s) - t0 )) s" | tee -a "$LOGDIR/timing.txt"
}

# --- Traçabilité : versions des outils et du dépôt ---------------------------
record_versions() {
  {
    echo "date     : $(date -Iseconds)"
    echo "machine  : $(hostname)  ($(nproc) coeurs)"
    echo "commit   : $(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo inconnu)"
    echo "modifie  : $(git -C "$ROOT" status --short | wc -l) fichier(s) modifié(s)"
    echo "yosys    : $(yosys -V 2>&1 | head -1)"
    echo "openroad : $(openroad -version 2>&1 | head -1)"
    echo "klayout  : $(klayout -v 2>&1 | head -1)"
    echo "bender   : $(bender --version 2>&1 | head -1)"
    echo "--- sous-modules (PDK) ---"
    git -C "$ROOT" submodule status 2>&1
  } > "$LOGDIR/versions.txt"
}

# =============================================================================
# ETAPE 1 : SYNTHESE (Bender -> Yosys)
#   run_synthesis.sh --synth : génère src/croc.flist avec Bender, puis synthétise
#   le RTL (Yosys + ABC) vers les cellules sg13cmos5l.
#   Sortie : yosys/out/croc_yosys.v
# =============================================================================
step_synth() {
  run_step synth yosys ./run_synthesis.sh --synth

  # --- VAL-01 : checks de la netlist ----------------------------------------
  # 1) la netlist existe et n'est pas vide
  if [[ -s "$ROOT/$SYNTH_NETLIST" ]]; then
    log_check VAL-01a OK "netlist présente ($(du -h "$ROOT/$SYNTH_NETLIST" | cut -f1))"
  else
    log_check VAL-01a ECHEC "netlist absente ou vide : $SYNTH_NETLIST"
    exit 1
  fi

  # 2) pas d'erreur dans le log (on exclut la ligne bénigne "0 Error, 0 Warning")
  local errs
    errs=$(sed 's/\x1b\[[0-9;]*m//g' "$LOGDIR/synth.log" \
       | grep -i "error" | grep -viE "(^|[^0-9])0[^[:alnum:]]*error" || true)
  if [[ -z "$errs" ]]; then
    log_check VAL-01b OK "aucune erreur dans le log de synthèse"
  else
    log_check VAL-01b ECHEC "erreurs dans le log (voir synth.log)"
    echo "$errs" | head -10
    exit 1
  fi

  # 3) latches inférés (cellules dlh/dll de sg13cmos5l) : à justifier si > 0
  local nlatch
  nlatch=$(grep -ciE "sg13[a-z0-9]*_(dlh|dll)" "$ROOT/$SYNTH_NETLIST" || true)
  if [[ "$nlatch" -eq 0 ]]; then
    log_check VAL-01c OK "0 latch dans la netlist"
  else
    log_check VAL-01c ECART "$nlatch latch(es) : à justifier dans le journal des écarts"
  fi

  # 4) SRAM : doivent apparaître comme instances de macros RM_IHPSG13_*
  local srams
  srams=$(grep -o "RM_IHPSG13_[A-Za-z0-9_]*" "$ROOT/$SYNTH_NETLIST" | sort | uniq -c || true)
  log_check VAL-01d OK "macros SRAM instanciées : ${srams:-AUCUNE (vérifier)}"

  # --- VAL-02 : statistiques (nombre de cellules) ---------------------------
  # Rapports éventuels produits par le flot (nom exact à confirmer au 1er run)
  find "$ROOT/yosys" -maxdepth 2 \( -name "*stat*" -o -name "*.rpt" \) -type f \
    -newer "$LOGDIR/versions.txt" -exec cp {} "$LOGDIR/" \; 2>/dev/null || true
  log_check VAL-02 OK "rapports de stat copiés dans $LOGDIR (à vérifier à la main)"

  # --- Archivage : copie de la netlist + somme de contrôle ------------------
  cp "$ROOT/$SYNTH_NETLIST" "$LOGDIR/"
  ( cd "$ROOT" && sha256sum "$SYNTH_NETLIST" ) >> "$LOGDIR/checksums.txt"
}

# --- (à venir) ---------------------------------------------------------------
# step_backend() { run_step backend openroad ./run_backend.sh --all ; ... }
# step_finish()  { run_step finish  klayout  ./run_finishing.sh --gds --seal ; ... }
# step_drc()     { run_step drc     klayout  ./run_drc.sh --minimal ; ... }

# =============================================================================
# Point d'entrée
# =============================================================================
STEP="${1:-all}"
record_versions
echo "[FLOW] run $RUN_ID -> $LOGDIR"

case "$STEP" in
  synth) step_synth ;;
  all)   step_synth ;;      # compléter au fur et à mesure : step_backend ...
  *)     echo "Usage : $0 {synth|all}"; exit 2 ;;
esac

echo "[FLOW] terminé : $LOGDIR"