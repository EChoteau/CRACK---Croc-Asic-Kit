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
#   ./scripts/run_flow.sh gds            # DEF -> GDS + seal ring (KLayout)
#   ./scripts/run_flow.sh drc            # DRC complet (KLayout, avec antenna)
#   ./scripts/run_flow.sh drc_minimal    # DRC minimal (itération rapide, pas un signoff)
#   ./scripts/run_flow.sh drc_report     # ré-analyse les résultats DRC existants (full|minimal)
#   ./scripts/run_flow.sh lvs            # LVS (Verilog -> SPICE, puis KLayout) sur le GDS non scellé
#   ./scripts/run_flow.sh all            # synth + backend + gds + drc complet + lvs
#
# Variables optionnelles :
#   RUN_ID=nom    : garder le même RUN_ID pour regrouper plusieurs étapes
#   DRC_JOBS=N    : nombre de tables DRC lancées en parallèle (défaut : nproc)
#
# Chaque run produit un dossier logs/<RUN_ID>/ contenant :
#   versions.txt  : versions des outils et commit du dépôt (traçabilité)
#   <étape>.log   : log complet de l'étape
#   timing.txt    : durée de chaque étape (métrique "temps de run", VAL-22)
#   checks.txt    : résultat des vérifications (VAL-01, VAL-05, ...)
#   checksums.txt : sommes SHA-256 des fichiers produits (reproductibilité)
#   openroad/     : copie de reports/, save/, out/, logs/ du backend
#   klayout/      : logs KLayout (def2stream, seal) et rapports DRC
#
# Statuts de checks.txt : OK | ECART (à justifier) | ECHEC | MANUEL (à lire à la main)
#
# Etapes implémentées : synth, backend, gds, drc, lvs
# A ajouter : STA multi-coins (VAL-10, après extraction SPEF)
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

# Finition KLayout
KL_DIR="$ROOT/klayout"
TOP="${TOP_DESIGN:-croc_chip}" # module top (défaut de env.sh)
SEALED_GDS="$KL_DIR/out/${PROJ}.sealed.gds.gz"
DRC_JOBS="${DRC_JOBS:-$(nproc)}"

mkdir -p "$LOGDIR"

# --- Fonctions utilitaires ---------------------------------------------------

# log_check <ID> <statut> <message> : écrit une ligne dans checks.txt et à l'écran
log_check() {
  echo "[CHECK] $1 : $2 : $3" | tee -a "$LOGDIR/checks.txt"
}

# run_step <nom> <dossier> <commande...> : exécute une commande dans un dossier,
# enregistre son log (sans codes couleur ANSI) et sa durée.
# La durée est écrite même si la commande échoue ; le code retour de la
# commande est ensuite renvoyé, donc une erreur arrête le flot (set -e),
# sauf si l'appelant l'intercepte avec "|| rc=$?" (cas du DRC).
run_step() {
  local name=$1 dir=$2; shift 2
  local t0 rc=0; t0=$(date +%s)
  echo "[FLOW] >>> $name"
  ( cd "$ROOT/$dir" && "$@" ) 2>&1 | sed -u 's/\x1b\[[0-9;]*m//g' | tee "$LOGDIR/$name.log" || rc=$?
  echo "$name : $(( $(date +%s) - t0 )) s" | tee -a "$LOGDIR/timing.txt"
  [[ "$rc" -eq 0 ]] || echo "[FLOW] $name : code retour $rc"
  return "$rc"
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
        if [[ -s "$OR_DIR/out/$f" && "$OR_DIR/out/$f" -nt "$LOGDIR/versions.txt" ]]; then
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

# =============================================================================
# ETAPE 3 : GDS (KLayout)
#   run_finishing.sh --gds --seal :
#     --gds  : DEF (openroad/out/croc.def) + LEF/GDS du PDK -> klayout/out/croc.gds.gz
#     --seal : génère le seal ring (die + 2 x 42 µm) et le fusionne
#              -> klayout/out/croc.sealed.gds.gz, top cell <TOP>_sealed
#   Le fill (--fill) n'est PAS fait ici : très long, à ajouter pour le signoff
#   densité (VAL-16). Attention : le DRC de run_drc.sh lit le GDS scellé,
#   donc SANS fill.
# =============================================================================

# Copie les logs KLayout et les rapports DRC (pas les GDS, trop lourds)
collect_klayout() {
  mkdir -p "$LOGDIR/klayout"
  [[ -d "$KL_DIR/out" ]] && cp -u "$KL_DIR"/out/*.log "$LOGDIR/klayout/" 2>/dev/null || true
  local d
  for d in drc-full drc-minimal; do
    [[ -d "$KL_DIR/$d" ]] && cp -ru "$KL_DIR/$d" "$LOGDIR/klayout/" || true
  done
  # LVS : on garde les logs et le schéma SPICE, pas la base .lvsdb (lourde)
  if [[ -d "$KL_DIR/lvs" ]]; then
    mkdir -p "$LOGDIR/klayout/lvs"
    cp -u "$KL_DIR"/lvs/*.log "$KL_DIR"/lvs/*.cir "$LOGDIR/klayout/lvs/" 2>/dev/null || true
  fi
}

step_gds() {
  trap 'collect_backend; collect_klayout' EXIT
  run_step gds klayout ./run_finishing.sh --gds --seal

  # GDS scellé produit pendant CE run
  if [[ "$SEALED_GDS" -nt "$LOGDIR/versions.txt" && -s "$SEALED_GDS" ]]; then
    log_check GDS OK "GDS scellé produit ($(du -h "$SEALED_GDS" | cut -f1))"
    ( cd "$ROOT" && sha256sum "klayout/out/${PROJ}.gds.gz" "klayout/out/${PROJ}.sealed.gds.gz" ) \
      >> "$LOGDIR/checksums.txt"
  else
    log_check GDS ECHEC "GDS scellé absent ou ancien : $SEALED_GDS"
    exit 1
  fi

  # Erreurs dans les logs KLayout (redirigés dans klayout/out/ par run_finishing.sh)
  local f nerr
  for f in def2stream.log gen_seal.log merge_seal.log; do
    [[ -f "$KL_DIR/out/$f" ]] || { log_check GDS ECART "log $f absent"; continue; }
    nerr=$(grep -ciE "error|exception|traceback" "$KL_DIR/out/$f" || true)
    if [[ "$nerr" -eq 0 ]]; then
      log_check GDS OK "$f : aucune erreur"
    else
      log_check GDS ECHEC "$f : $nerr ligne(s) d'erreur"
      exit 1
    fi
  done

  # VAL-17 (partiel) : cellules manquantes lors de la conversion DEF -> GDS
  # (def2stream signale les cellules sans GDS ; formulation à confirmer au 1er run)
  local nmiss
  nmiss=$(grep -iE "missing|not found|no gds" "$KL_DIR/out/def2stream.log" | grep -vic "checking for missing" || true)
  if [[ "$nmiss" -eq 0 ]]; then
    log_check VAL-17 OK "def2stream : aucune cellule signalée manquante"
  else
    log_check VAL-17 ECART "def2stream : $nmiss ligne(s) 'missing/not found' (voir klayout/def2stream.log)"
  fi
}

# =============================================================================
# ETAPE 4 : DRC (KLayout, deck IHP sg13cmos5l)
#   run_drc.sh --full    : toutes les règles + antenna (signoff, VAL-13/VAL-15)
#   run_drc.sh --minimal : interconnexions seulement (itération, PAS un signoff)
#   Entrée : klayout/out/croc.sealed.gds.gz ; sortie : klayout/drc-<mode>/
#   Les violations sont écrites dans des bases de résultats KLayout (*.lyrdb),
#   une par table de règles ; chaque violation est un élément <item>.
#
#   ATTENTION : run_drc.py renvoie un code d'erreur dès qu'il y a des
#   violations ("KLayout DRC Check Failed"). Ce n'est pas un plantage :
#   seuls l'absence de résultats ou une exception d'un worker sont des échecs.
#
#   Durée mesurée (ocaepc69, 20 coeurs) : ~43 min, fixée par la table
#   sg13cmos5l_maximal (les autres tables finissent en ~18 min).
# =============================================================================

# Lance le DRC puis l'analyse (drc_report)
step_drc() {
  local mode=${1:-full}
  local rundir="$KL_DIR/drc-$mode"
  local label="VAL-13"; [[ "$mode" == "minimal" ]] && label="VAL-13(min)"
  trap 'collect_backend; collect_klayout' EXIT

  # Le GDS doit exister (étape gds faite avant, dans ce run ou un précédent)
  if [[ ! -s "$SEALED_GDS" ]]; then
    log_check "$label" ECHEC "GDS scellé absent : lancer d'abord l'étape gds"
    exit 1
  fi

  # Vider les résultats précédents pour ne pas compter d'anciennes violations
  rm -rf "$rundir"

  # Code retour intercepté : non nul dès qu'il y a des violations (voir plus haut)
  local rc=0
  run_step "drc_$mode" klayout ./run_drc.sh "--$mode" --jobs "$DRC_JOBS" || rc=$?

  # Vrai échec : un worker a planté
  if grep -Fq " generated an exception:" "$rundir/drc-coordinator.log" 2>/dev/null; then
    log_check "$label" ECHEC "DRC $mode : exception d'un worker (voir drc-coordinator.log)"
    exit 1
  fi
  [[ "$rc" -ne 0 ]] && echo "[FLOW] DRC : code retour $rc = violations détectées (attendu), analyse..."

  drc_report "$mode"
}

# Analyse des résultats DRC déjà présents dans klayout/drc-<mode>/ (sans relancer)
#   - vérifie que chaque table lancée a produit son .lyrdb (run complet)
#   - écrit drc_<mode>_summary.txt : violations par table et par règle
#   - sépare règles obligatoires et recommandées (suffixe R, ex. Pad.fR_M2, Pad.d1R)
drc_report() {
  local mode=${1:-full}
  local rundir="$KL_DIR/drc-$mode"
  local label="VAL-13"; [[ "$mode" == "minimal" ]] && label="VAL-13(min)"
  trap 'collect_backend; collect_klayout' EXIT

  local dbs
  mapfile -t dbs < <(find "$rundir" -name "*.lyrdb" -type f 2>/dev/null | sort)
  if [[ ${#dbs[@]} -eq 0 ]]; then
    log_check "$label" ECHEC "DRC $mode : aucun fichier .lyrdb dans $rundir"
    exit 1
  fi

  # Run complet ? run_drc.py fusionne les .lyrdb partiels en <layout>_<top>_full.lyrdb
  # puis supprime les partiels : si ce fichier existe, la fusion a eu lieu (= toutes les
  # tables ont produit un résultat). Sinon, une table avec un .log mais sans .lyrdb
  # n'a pas terminé.
  local merged="" lg incomplete=""
  merged=$(find "$rundir" -name "*_full.lyrdb" -type f 2>/dev/null | head -1)
  if [[ -n "$merged" ]]; then
    local ntab; ntab=$(find "$rundir" -name "*_sealed_*.log" -type f 2>/dev/null | wc -l)
    log_check "$label" OK "DRC $mode : résultats fusionnés ($(basename "$merged")), $ntab table(s) lancée(s)"
  else
    for lg in "$rundir"/*_sealed_*.log; do
      [[ -f "$lg" ]] || continue
      [[ -f "${lg%.log}.lyrdb" ]] || incomplete+=" $(basename "$lg" .log | sed 's/.*_sealed_//')"
    done
    if [[ -n "$incomplete" ]]; then
      log_check "$label" ECART "DRC $mode : table(s) sans résultat (run interrompu ?) :$incomplete"
    else
      log_check "$label" OK "DRC $mode : ${#dbs[@]} table(s), toutes terminées"
    fi
  fi

  # Résumé : par table, puis par règle
  local summary="$LOGDIR/drc_${mode}_summary.txt"
  local rules
  rules=$(grep -ho "<category>'[^<]*" "${dbs[@]}" | sed "s/<category>//; s/'//g" \
          | sort | uniq -c | sort -rn || true)
  {
    local db
    if [[ -z "$merged" ]]; then
      echo "# Violations par table (nombre, table)"
      for db in "${dbs[@]}"; do
        printf "%7d %s\n" "$(grep -c '<item>' "$db" || true)" "$(basename "$db" .lyrdb | sed 's/.*_sealed_//')"
      done | sort -rn
      echo
    else
      echo "# (résultats fusionnés par run_drc.py : pas de ventilation par table, voir par règle)"
      echo
    fi
    echo "# Violations par règle (nombre, règle), toutes tables confondues"
    echo "${rules:-  (aucune)}"
  } > "$summary"

  # Obligatoires vs recommandées (convention IHP : nom de règle terminé par R)
  local is_rec='\.[A-Za-z0-9]*R(_|$)'
  local n_mand n_rec list_mand list_rec
  n_mand=$(echo "$rules" | awk 'NF' | grep -vE "$is_rec" | awk '{s+=$1} END{print s+0}')
  n_rec=$(echo "$rules"  | awk 'NF' | grep -E  "$is_rec" | awk '{s+=$1} END{print s+0}')
  list_mand=$(echo "$rules" | awk 'NF' | grep -vE "$is_rec" | awk '{printf " %s=%s", $2, $1}')
  list_rec=$(echo "$rules"  | awk 'NF' | grep -E  "$is_rec" | awk '{printf " %s=%s", $2, $1}')

  if [[ "$n_mand" -eq 0 ]]; then
    log_check "$label" OK "DRC $mode : 0 violation de règle obligatoire"
  else
    # Pas d'arrêt : chaque violation doit être corrigée ou justifiée (journal des écarts)
    log_check "$label" ECART "DRC $mode : $n_mand violation(s) de règles obligatoires :$list_mand"
  fi
  if [[ "$n_rec" -gt 0 ]]; then
    log_check "$label" MANUEL "DRC $mode : $n_rec violation(s) de règles recommandées (non bloquantes) :$list_rec"
  fi
  echo "[FLOW] détail : $summary"

  # VAL-15 / VAL-16 : en mode full, antenna et densité font partie du deck
  if [[ "$mode" == "full" ]]; then
    log_check VAL-15 MANUEL "antenna incluse dans le DRC full : voir la ligne 'antenna' de drc_full_summary.txt"
    log_check VAL-16 MANUEL "densité vérifiée sur le GDS SANS fill : règles *Fil.* attendues tant que --fill n'est pas fait"
  fi
}

# =============================================================================
# ETAPE 5 : LVS (KLayout, deck IHP du PDK choisi par CROC_PDK) -- VAL-14
#   1) scripts/verilog2spice.py : openroad/out/<proj>_lvs.v -> klayout/lvs/<top>_schematic.cir
#      run_lvs.py n'accepte que du SPICE/CDL ; l'ordre des broches de chaque cellule
#      est lu dans les CDL du PDK (cellules standard, IO, SRAM).
#   2) run_lvs.py (dans le PDK) : extrait la netlist du GDS et la compare au schéma.
#
#   Le LVS tourne sur le GDS NON scellé (klayout/out/<proj>.gds.gz, top cell = $TOP) :
#   le deck cherche dans le schéma un circuit du même nom que le top cell du layout,
#   et le seal ring ne contient aucun dispositif.
#   Les SRAM ne sont fournies qu'en CDL du PDK sg13g2 (cellules partagées avec cmos5l).
# =============================================================================
step_lvs() {
  trap 'collect_backend; collect_klayout' EXIT
  local pdk="${CROC_PDK:-sg13cmos5l}"
  local lvs_v="$OR_DIR/out/${PROJ}_lvs.v"
  local gds="$KL_DIR/out/${PROJ}.gds.gz"
  local rundir="$KL_DIR/lvs"
  local sch="$rundir/${TOP}_schematic.cir"
  local g2="$ROOT/ihp13/sg13g2/ihp-sg13g2"
  local kl_path std_cdl io_cdl
  case "$pdk" in
    sg13cmos5l)
      kl_path="$ROOT/ihp13/sg13cmos5l/libs.tech/klayout"
      std_cdl="$ROOT/ihp13/sg13cmos5l/libs.ref/sg13cmos5l_stdcell/cdl/sg13cmos5l_stdcell.cdl"
      io_cdl="$ROOT/ihp13/sg13cmos5l/libs.ref/sg13cmos5l_io/cdl/sg13cmos5l_io.cdl" ;;
    sg13g2)
      kl_path="$g2/libs.tech/klayout"
      std_cdl="$g2/libs.ref/sg13g2_stdcell/cdl/sg13g2_stdcell.cdl"
      io_cdl="$g2/libs.ref/sg13g2_io/cdl/sg13g2_io.cdl" ;;
    *) log_check VAL-14 ECHEC "CROC_PDK inconnu : $pdk"; exit 1 ;;
  esac
  local runner="$kl_path/tech/lvs/run_lvs.py"

  # Entrées nécessaires (le backend et l'étape gds doivent avoir tourné avant)
  local f
  for f in "$lvs_v" "$gds" "$runner" "$std_cdl" "$io_cdl"; do
    if [[ ! -s "$f" ]]; then
      log_check VAL-14 ECHEC "entrée absente : ${f#$ROOT/} (étapes backend et gds faites ?)"
      exit 1
    fi
  done

  # Liste des CDL : cellules standard, IO, et toutes les SRAM (seules celles utilisées sont gardées)
  local cdl_args=(--cdl "$std_cdl" --cdl "$io_cdl")
  for f in "$g2"/libs.ref/sg13g2_sram/cdl/RM_*.cdl; do cdl_args+=(--cdl "$f"); done

  rm -rf "$rundir"; mkdir -p "$rundir"

  # 1) Verilog -> SPICE
  run_step lvs_netlist . python3 "$ROOT/scripts/verilog2spice.py" \
      --verilog "$lvs_v" --top "$TOP" --out "$sch" "${cdl_args[@]}"
  if [[ ! -s "$sch" ]]; then
    log_check VAL-14 ECHEC "schéma SPICE non produit (voir lvs_netlist.log)"
    exit 1
  fi
  # Cellules du Verilog sans sous-circuit CDL : bondpads et remplissage IO attendus, le reste est suspect
  local unk
  unk=$(grep -o "cellule inconnue (ignorée) : .*" "$LOGDIR/lvs_netlist.log" | sed 's/.*: //' | tr '\n' ' ' || true)
  if [[ -z "$unk" ]]; then
    log_check VAL-14a OK "toutes les cellules du Verilog ont un sous-circuit CDL"
  else
    log_check VAL-14a ECART "cellules sans CDL (ignorées dans le schéma) : $unk"
  fi
  ( cd "$ROOT" && sha256sum "${lvs_v#$ROOT/}" ) >> "$LOGDIR/checksums.txt"

  # 2) Extraction du layout + comparaison. Un code retour non nul est possible en cas
  #    de mismatch : le verdict est lu dans les logs, pas dans le code retour.
  run_step lvs klayout python3 "$runner" \
      --layout "$gds" --netlist "$sch" --topcell "$TOP" --run_dir "$rundir" || true

  if grep -rqs "Congratulations! Netlists match" "$LOGDIR/lvs.log" "$rundir"; then
    log_check VAL-14 OK "LVS : les netlists correspondent (top cell $TOP, PDK $pdk)"
  elif grep -rqs "Netlists don't match" "$LOGDIR/lvs.log" "$rundir"; then
    log_check VAL-14 ECART "LVS : mismatch, ouvrir le .lvsdb de klayout/lvs dans KLayout et justifier chaque écart"
  else
    log_check VAL-14 ECHEC "LVS : aucun verdict dans les logs (voir lvs.log)"
  fi
  log_check VAL-14 MANUEL "vérifier dans lvs.log : top-level pins/alimentations, dispositifs extraits vs schéma, cellules ignorées (VAL-14a)"
}

# --- (à venir) ---------------------------------------------------------------
# step_sta() : STA multi-coins avec SPEF (VAL-10), après activation de l'extraction RC

# =============================================================================
# Point d'entrée
# =============================================================================
STEP="${1:-all}"
record_versions
echo "[FLOW] run $RUN_ID -> $LOGDIR"
# Séparateur daté : distingue plusieurs lancements dans un même dossier de run
echo "===== $(date '+%Y-%m-%d %H:%M') : étape '$STEP' =====" | tee -a "$LOGDIR/checks.txt" >> "$LOGDIR/timing.txt"

case "$STEP" in
  synth)       step_synth ;;
  floorplan|placement|cts|routing|finishing) step_backend_stage "$STEP" ;;
  backend)     step_backend ;;
  gds)         step_gds ;;
  drc)         step_drc full ;;
  drc_minimal) step_drc minimal ;;
  drc_report)  drc_report "${2:-full}" ;;   # analyse seule : drc_report [full|minimal]
  lvs)         step_lvs ;;
  all)         step_synth; step_backend; step_gds; step_drc full; step_lvs ;;
  *)           echo "Usage : $0 {synth|floorplan|placement|cts|routing|finishing|backend|gds|drc|drc_minimal|drc_report [full|minimal]|lvs|all}"; exit 2 ;;
esac

echo "[FLOW] terminé : $LOGDIR"