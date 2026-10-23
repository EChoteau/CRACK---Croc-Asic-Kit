#!/usr/bin/env bash
# =============================================================================
# run_flow.sh : flot open-source Croc (IHP130 sg13cmos5l), construit étape par étape
#
# A LANCER DANS LE CONTENEUR (iic-osic-tools), pas sur l'hôte.
#
# Usage :
#   ./scripts/run_flow.sh synth          # synthèse seule
#   ./scripts/run_flow.sh floorplan      # une sous-étape du backend
#   ./scripts/run_flow.sh placement      #   (idem : cts, routing, finishing)
#   ./scripts/run_flow.sh backend        # les 5 sous-étapes du backend
#   ./scripts/run_flow.sh all            # toutes les étapes implémentées
#
# Variable optionnelle : RUN_ID=nom ./scripts/run_flow.sh <étape>
#   Garder le même RUN_ID pour regrouper plusieurs étapes dans un seul dossier.
#
# Chaque run produit un dossier logs/<RUN_ID>/ contenant :
#   versions.txt  : versions des outils et commit du dépôt (traçabilité)
#   <étape>.log   : log complet de l'étape
#   timing.txt    : durée de chaque étape (métrique "temps de run", VAL-22)
#   checks.txt    : résultat des vérifications (VAL-01, VAL-05, ...)
#   checksums.txt : sommes SHA-256 des fichiers produits (reproductibilité)
#   openroad/     : copie de reports/, save/, out/, logs/ du backend
#
# Statuts de checks.txt : OK | ECART (à justifier) | ECHEC | MANUEL (à lire à la main)
#
# Etapes implémentées : synth, backend (floorplan, placement, cts, routing, finishing)
# A ajouter (une fois validées à la main) : klayout (GDS), drc
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

# Backend OpenROAD
PROJ="${PROJ_NAME:-croc}"      # nom de projet utilisé par les scripts Tcl
OR_DIR="$ROOT/openroad"

mkdir -p "$LOGDIR"

# --- Fonctions utilitaires ---------------------------------------------------

# log_check <ID> <statut> <message> : écrit une ligne dans checks.txt et à l'écran
log_check() {
  echo "[CHECK] $1 : $2 : $3" | tee -a "$LOGDIR/checks.txt"
}

# run_step <nom> <dossier> <commande...> : exécute une commande dans un dossier,
# enregistre son log (sans codes couleur ANSI) et sa durée.
# Une erreur arrête tout le flot (pipefail).
run_step() {
  local name=$1 dir=$2; shift 2
  local t0; t0=$(date +%s)
  echo "[FLOW] >>> $name"
  ( cd "$ROOT/$dir" && "$@" ) 2>&1 | sed -u 's/\x1b\[[0-9;]*m//g' | tee "$LOGDIR/$name.log"
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

  # 2) pas d'erreur dans le log (on exclut la ligne bénigne "0 Error, 0 Warning",
  #    dont les mots sont colorés en ANSI dans la sortie brute)
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
  # Rapports éventuels produits par le flot (nom exact à confirmer)
  find "$ROOT/yosys" -maxdepth 2 \( -name "*stat*" -o -name "*.rpt" \) -type f \
    -newer "$LOGDIR/versions.txt" -exec cp {} "$LOGDIR/" \; 2>/dev/null || true
  log_check VAL-02 MANUEL "rapports de stat copiés dans $LOGDIR : vérifier qu'ils existent"

  # --- Archivage : copie de la netlist + somme de contrôle ------------------
  cp "$ROOT/$SYNTH_NETLIST" "$LOGDIR/"
  ( cd "$ROOT" && sha256sum "$SYNTH_NETLIST" ) >> "$LOGDIR/checksums.txt"
}

# =============================================================================
# ETAPE 2 : BACKEND OpenROAD, 5 sous-étapes lancées séparément :
#   floorplan -> placement -> cts -> routing -> finishing
# Chaque sous-étape (run_backend.sh --<étape>) repart du checkpoint de la
# précédente (openroad/save/*.zip) : on peut donc en relancer une seule.
# Les scripts OpenROAD doivent être lancés depuis openroad/ (chemins relatifs).
# =============================================================================

# Checkpoint produit par chaque sous-étape (dans openroad/save/)
declare -A STAGE_CKPT=(
  [floorplan]="01_${PROJ}.floorplan.zip"
  [placement]="02_${PROJ}.placed.zip"
  [cts]="03_${PROJ}.cts.zip"
  [routing]="04_${PROJ}.routed.zip"
  [finishing]="05_${PROJ}.final.zip"
)
# Test du plan de validation correspondant
declare -A STAGE_VAL=(
  [floorplan]=VAL-05 [placement]=VAL-06 [cts]=VAL-07
  [routing]=VAL-08   [finishing]=FIN
)

# Copie rapports, checkpoints, sorties et logs OpenROAD dans le dossier du run.
# Appelée par un trap EXIT : elle s'exécute aussi si une étape échoue.
collect_backend() {
  mkdir -p "$LOGDIR/openroad"
  local d
  for d in reports save out logs; do
    [[ -d "$OR_DIR/$d" ]] && cp -ru "$OR_DIR/$d" "$LOGDIR/openroad/" || true
  done
}

# Lance une sous-étape du backend puis applique ses vérifications
step_backend_stage() {
  local stage=$1
  local val=${STAGE_VAL[$stage]} ckpt=${STAGE_CKPT[$stage]}
  local log="$LOGDIR/backend_$stage.log"
  trap collect_backend EXIT

  # Exécution (durée écrite dans timing.txt ; une erreur arrête le flot)
  run_step "backend_$stage" openroad ./run_backend.sh "--$stage"

  # --- Check commun : messages [ERROR ...] d'OpenROAD dans le log -----------
  local nerr
  nerr=$(sed 's/\x1b\[[0-9;]*m//g' "$log" | grep -c "\[ERROR" || true)
  if [[ "$nerr" -eq 0 ]]; then
    log_check "$val" OK "$stage : 0 message [ERROR] dans le log"
  else
    log_check "$val" ECHEC "$stage : $nerr message(s) [ERROR] (voir backend_$stage.log)"
    exit 1
  fi

  # --- Check commun : checkpoint produit pendant CE run ---------------------
  if [[ "$OR_DIR/save/$ckpt" -nt "$LOGDIR/versions.txt" ]]; then
    log_check "$val" OK "$stage : checkpoint $ckpt produit"
    ( cd "$ROOT" && sha256sum "openroad/save/$ckpt" ) >> "$LOGDIR/checksums.txt"
  else
    log_check "$val" ECHEC "$stage : checkpoint $ckpt absent ou ancien"
    exit 1
  fi

  # --- Checks spécifiques à l'étape -----------------------------------------
  case "$stage" in
    floorplan)
      # VAL-05 : macros dans le coeur, pads assignés, grille d'alim sans court-circuit
      # Rapport de check_setup (sdc) produit par 01_floorplan.tcl
      if [[ -s "$OR_DIR/reports/01-01_${PROJ}_checks.rpt" ]]; then
        local nw
        nw=$(grep -ci "warning" "$OR_DIR/reports/01-01_${PROJ}_checks.rpt" || true)
        log_check "$val" OK "rapport check_setup présent ($nw ligne(s) 'warning', à lire)"
      else
        log_check "$val" ECART "rapport 01-01_${PROJ}_checks.rpt absent ou vide"
      fi
      log_check "$val" MANUEL "placement des macros / pads / grille d'alim : voir les captures dans openroad/reports"
      ;;
    placement)
      # VAL-06 : le contrôle de recouvrement (check_placement) est fait en début de CTS
      log_check "$val" MANUEL "recouvrements : vérifiés par check_placement au début de l'étape cts ; densité/congestion : lire les report_metrics"
      ;;
    cts)
      # VAL-07 : skew, latence, tous les registres sur l'arbre
      if [[ -s "$OR_DIR/reports/03_${PROJ}.cts.rpt" ]]; then
        log_check "$val" OK "rapport CTS présent (03_${PROJ}.cts.rpt)"
      else
        log_check "$val" ECART "rapport CTS absent"
      fi
      log_check "$val" MANUEL "skew et couverture des registres : lire 03_${PROJ}.cts.rpt (seuil à fixer au protocole)"
      ;;
    routing)
      # VAL-08 : 0 violation de routage détaillé
      # Compteur final affiché par detailed_route dans le log (à confirmer au 1er run)
      local nviol
      nviol=$(grep -o "Number of violations = [0-9]*" "$log" | tail -1 | grep -o "[0-9]*$" || true)
      if [[ -z "$nviol" ]]; then
        log_check "$val" ECART "compteur de violations introuvable dans le log : vérifier à la main"
      elif [[ "$nviol" -eq 0 ]]; then
        log_check "$val" OK "0 violation de routage détaillé"
      else
        log_check "$val" ECHEC "$nviol violation(s) de routage (voir reports/04_${PROJ}_route_drc.rpt)"
      fi
      ;;
    finishing)
      # Sorties finales : présentes et non vides, avec somme de contrôle
      local f
      for f in "${PROJ}.def" "${PROJ}_lvs.v" "${PROJ}.v" "${PROJ}.odb" "${PROJ}.sdc"; do
        if [[ -s "$OR_DIR/out/$f" ]]; then
          log_check "$val" OK "sortie out/$f présente"
          ( cd "$ROOT" && sha256sum "openroad/out/$f" ) >> "$LOGDIR/checksums.txt"
        else
          log_check "$val" ECHEC "sortie out/$f absente ou vide"
        fi
      done
      ;;
  esac
}

# Enchaîne les 5 sous-étapes
step_backend() {
  local s
  for s in floorplan placement cts routing finishing; do
    step_backend_stage "$s"
  done
}

# --- (à venir) ---------------------------------------------------------------
# step_finish()  { run_step finish  klayout  ./run_finishing.sh --gds --seal ; ... }
# step_drc()     { run_step drc     klayout  ./run_drc.sh --minimal ; ... }

# =============================================================================
# Point d'entrée
# =============================================================================
STEP="${1:-all}"
record_versions
echo "[FLOW] run $RUN_ID -> $LOGDIR"

case "$STEP" in
  synth)   step_synth ;;
  floorplan|placement|cts|routing|finishing) step_backend_stage "$STEP" ;;
  backend) step_backend ;;
  all)     step_synth; step_backend ;;   # compléter au fur et à mesure
  *)       echo "Usage : $0 {synth|floorplan|placement|cts|routing|finishing|backend|all}"; exit 2 ;;
esac

echo "[FLOW] terminé : $LOGDIR"