#!/usr/bin/env bash
# =============================================================================
# run_detached.sh : lance run_flow.sh dans le conteneur, détaché du terminal.
# Le run continue si la session SSH se coupe (pas besoin de tmux).
#
# A LANCER SUR L'HOTE (là où `docker ps` répond), PAS dans le conteneur.
#
# Usage :
#   ./scripts/run_detached.sh <étape> [arguments]   # lance en arrière-plan
#   ./scripts/run_detached.sh status                # runs en cours + derniers checks
#   ./scripts/run_detached.sh log [RUN_ID]          # suit la sortie (Ctrl+C quitte le suivi, pas le run)
#   ./scripts/run_detached.sh stop [RUN_ID]         # arrête le run
#
# <étape> et [arguments] sont ceux de run_flow.sh (synth, backend, gds, drc,
# drc_report full, lvs, all...). Exemples :
#   RUN_ID=baseline_open_ihp130 ./scripts/run_detached.sh all
#   RUN_ID=drc_analyse_1        ./scripts/run_detached.sh drc_report full
#   DRC_JOBS=8 RUN_ID=essai     ./scripts/run_detached.sh drc
#
# Variables transmises au conteneur : RUN_ID, DRC_JOBS, CROC_PDK (si définies).
# Sans RUN_ID, un nom est généré (open_ihp130_AAAAMMJJ_HHMM).
#
# Fichiers :
#   logs/<RUN_ID>.out    sortie complète du run (ce que tu verrais à l'écran)
#   logs/<RUN_ID>/       dossier de run habituel (checks.txt, timing.txt...)
# Conteneur nommé croc_<RUN_ID> : un seul run à la fois (les runs partagent
# openroad/save, klayout/out... et s'écraseraient). FORCE=1 pour passer outre.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"                                  # docker-compose.yml est à la racine
PREFIX="croc_"                              # préfixe des noms de conteneur

usage() { sed -n '2,/^# ====/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; }

if ! command -v docker >/dev/null 2>&1; then
  echo "[ERREUR] docker introuvable : ce script se lance sur l'hôte, pas dans le conteneur." >&2
  exit 1
fi

# Noms des conteneurs de run en cours (un par ligne)
running() { docker ps --filter "name=${PREFIX}" --format '{{.Names}}' 2>/dev/null || true; }

# Dernier fichier de sortie (RUN_ID sans extension)
latest_run() { ls -t logs/*.out 2>/dev/null | head -1 | sed 's#^logs/##; s#\.out$##' || true; }

# RUN_ID visé par status/log/stop : argument, sinon le run en cours, sinon le dernier
pick_run() {
  local id="${1:-}"
  if [[ -z "$id" ]]; then
    id="$(running | head -1 | sed "s/^${PREFIX}//")"
    [[ -n "$id" ]] || id="$(latest_run)"
  fi
  echo "$id"
}

case "${1:-}" in
  ""|-h|--help|help)
    usage
    ;;

  status)
    names="$(running)"
    if [[ -z "$names" ]]; then
      echo "Aucun run en cours."
      last="$(latest_run)"
      [[ -n "$last" ]] && echo "Dernier run : $last (./scripts/run_detached.sh log $last)"
    fi
    for n in $names; do
      id="${n#$PREFIX}"
      echo "=== run en cours : $id ($(docker ps --filter "name=^${n}\$" --format '{{.Status}}'))"
    done
    id="$(pick_run "${2:-}")"
    if [[ -n "$id" ]]; then
      echo "--- 5 dernières lignes de logs/$id.out"
      tail -n 5 "logs/$id.out" 2>/dev/null || echo "(pas de fichier logs/$id.out)"
      if [[ -f "logs/$id/checks.txt" ]]; then
        echo "--- ECHEC / ECART / MANUEL dans logs/$id/checks.txt (10 dernières)"
        grep -E "ECHEC|ECART|MANUEL" "logs/$id/checks.txt" | tail -n 10 || true
      fi
      [[ -f "logs/$id/timing.txt" ]] && { echo "--- durées (logs/$id/timing.txt)"; tail -n 5 "logs/$id/timing.txt"; }
    fi
    ;;

  log)
    id="$(pick_run "${2:-}")"
    [[ -n "$id" && -f "logs/$id.out" ]] || { echo "[ERREUR] aucun fichier logs/<RUN_ID>.out trouvé." >&2; exit 1; }
    echo "[INFO] suivi de logs/$id.out (Ctrl+C quitte le suivi, le run continue)"
    tail -n 50 -f "logs/$id.out"
    ;;

  stop)
    id="$(pick_run "${2:-}")"
    [[ -n "$id" ]] || { echo "[ERREUR] aucun run à arrêter." >&2; exit 1; }
    if running | grep -qx "${PREFIX}${id}"; then
      echo "[INFO] arrêt de ${PREFIX}${id} (les résultats partiels restent dans logs/$id/)"
      docker stop "${PREFIX}${id}" >/dev/null
      echo "[INFO] arrêté."
    else
      echo "Le run $id n'est pas en cours."
    fi
    ;;

  *)
    # --- Lancement : tout ce qui suit est passé tel quel à run_flow.sh --------
    RUN_ID="${RUN_ID:-open_ihp130_$(date +%Y%m%d_%H%M)}"
    if [[ ! "$RUN_ID" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
      echo "[ERREUR] RUN_ID '$RUN_ID' invalide (lettres, chiffres, _ . - ; pas d'espace)." >&2
      exit 1
    fi
    NAME="${PREFIX}${RUN_ID}"

    if [[ -n "$(running)" && "${FORCE:-0}" != "1" ]]; then
      echo "[ERREUR] un run est déjà en cours :" >&2
      running | sed 's/^/  /' >&2
      echo "Les runs partagent openroad/save, klayout/out... : attends la fin, ou ./scripts/run_detached.sh stop. (FORCE=1 pour passer outre)" >&2
      exit 1
    fi

    mkdir -p logs
    OUT="logs/${RUN_ID}.out"
    env_args=(-e "RUN_ID=$RUN_ID")
    [[ -n "${DRC_JOBS:-}"  ]] && env_args+=(-e "DRC_JOBS=$DRC_JOBS")
    [[ -n "${CROC_PDK:-}"  ]] && env_args+=(-e "CROC_PDK=$CROC_PDK")
    inner="./scripts/run_flow.sh $(printf '%q ' "$@")"     # arguments protégés pour bash -c

    {
      echo "===== $(date '+%Y-%m-%d %H:%M:%S') : run_detached.sh : $inner (RUN_ID=$RUN_ID)"
    } >> "$OUT"

    nohup env UID="$(id -u)" GID="$(id -g)" \
      docker compose run --rm -T --name "$NAME" "${env_args[@]}" \
      pulp-docker --skip bash -c "$inner" \
      >> "$OUT" 2>&1 < /dev/null &
    pid=$!
    disown "$pid" 2>/dev/null || true

    # Le conteneur doit apparaître dans les secondes qui suivent
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      sleep 1
      running | grep -qx "$NAME" && break
    done
    if running | grep -qx "$NAME"; then
      echo "[OK] lancé : $NAME  (${inner})"
      echo "     suivre : ./scripts/run_detached.sh log $RUN_ID"
      echo "     état   : ./scripts/run_detached.sh status"
      echo "     arrêt  : ./scripts/run_detached.sh stop $RUN_ID"
    else
      echo "[ERREUR] le conteneur $NAME n'est pas apparu. Dernières lignes de $OUT :" >&2
      tail -n 15 "$OUT" >&2
      exit 1
    fi
    ;;
esac
