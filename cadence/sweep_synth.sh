#!/bin/bash
# =============================================================================
# CRACK - Flot licence (Cadence) : balayage en fréquence de la synthèse
#
# Lance run_implem.sh pour chaque fréquence cible (l'un après l'autre : une
# seule licence Genus à la fois), puis rassemble les métriques de tous les runs
# dans un tableau commun (VAL-23 : au moins 3 points par flot).
#
#   ./sweep_synth.sh                          # profil iso, fréquences par défaut
#   ./sweep_synth.sh -p max                   # même balayage, efforts max
#   ./sweep_synth.sh -f "80 100 125 150"      # fréquences en MHz
#
# Sorties : runs/sweep_<profil>_<techno>_<date>/
#   sweep.log            log du balayage (chaque run garde aussi ses propres logs)
#   runs.txt             liste des répertoires de run
#   sweep_synth.txt/csv  tableau : WNS/TNS, surface, cellules, puissance, temps
# =============================================================================
set -u
set -o pipefail

CRACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROFILE="iso"
TECH="ihp130_sg13cmos5l"
FREQS="50 80 100 125 150 200"
EXTRA=()

show_help() {
    cat << EOF
Balayage en fréquence de la synthèse (flot licence CRACK)

Usage : ./sweep_synth.sh [OPTIONS] [-- options passées à run_implem.sh]

  -p, --profile <p>    iso | max                           [$PROFILE]
  -t, --tech <nom>     techno                              [$TECH]
  -f, --freqs "<MHz>"  fréquences cibles de clk_sys        [$FREQS]
  -h, --help           cette aide

Exemple : ./sweep_synth.sh -p max -f "100 125 150 175"
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--profile) PROFILE="$2"; shift 2 ;;
        -t|--tech)    TECH="$2"; shift 2 ;;
        -f|--freqs)   FREQS="$2"; shift 2 ;;
        -h|--help)    show_help; exit 0 ;;
        --)           shift; EXTRA=("$@"); break ;;
        *)            echo "[CRACK][ERROR] Option inconnue : $1" >&2; exit 1 ;;
    esac
done

STAMP=$(date +%Y%m%d-%H%M%S)
SWEEP_DIR="$CRACK_ROOT/runs/sweep_${PROFILE}_${TECH}_${STAMP}"
mkdir -p "$SWEEP_DIR"
SLOG="$SWEEP_DIR/sweep.log"
: > "$SWEEP_DIR/runs.txt"

say() { echo "$*"; echo "$*" >> "$SLOG"; }

read -r -a FLIST <<< "$FREQS"
N=${#FLIST[@]}
say "[CRACK][INFO] Balayage : profil $PROFILE, $TECH, $N point(s) : $FREQS MHz"
say "[CRACK][INFO] Dossier  : $SWEEP_DIR"
T0=$(date +%s)

i=0
for f in "${FLIST[@]}"; do
    i=$((i + 1))
    ns=$(awk -v f="$f" 'BEGIN { printf "%.4g", 1000.0 / f }')
    t1=$(date +%s)
    say "[CRACK][INFO] [$i/$N] $f MHz (période $ns ns)..."
    # La sortie de run_implem.sh va dans le log du balayage (terminal propre)
    if "$CRACK_ROOT/run_implem.sh" -t "$TECH" -p "$PROFILE" -c "$ns" \
            --tag "sweep${STAMP}" "${EXTRA[@]}" >> "$SLOG" 2>&1; then
        status="OK"
    else
        status="ECHEC"
    fi
    run_dir="$CRACK_ROOT/runs/$(readlink "$CRACK_ROOT/runs/latest")"
    echo "$run_dir" >> "$SWEEP_DIR/runs.txt"
    say "[CRACK][INFO] [$i/$N] $f MHz : $status en $(( $(date +%s) - t1 )) s -> $(basename "$run_dir")"
done

# --- Agrégation des métriques ---------------------------------------------------
PY=$(command -v python3 || command -v python || true)
if [[ -z "$PY" ]]; then
    say "[CRACK][WARNING] python introuvable : tableau non généré"
    exit 0
fi
JSONS=()
while read -r d; do
    [[ -f "$d/metrics/synth_genus.json" ]] && JSONS+=("$d/metrics/synth_genus.json")
done < "$SWEEP_DIR/runs.txt"
if [[ ${#JSONS[@]} -eq 0 ]]; then
    say "[CRACK][ERROR] aucun run n'a produit de métriques, voir $SLOG"
    exit 1
fi
"$PY" "$CRACK_ROOT/scripts/extract_metrics.py" sweep "${JSONS[@]}" \
    -o "$SWEEP_DIR/sweep_synth.txt" >> "$SLOG" 2>&1
say "[CRACK][INFO] Balayage terminé en $(( ($(date +%s) - T0) / 60 )) min"
echo
cat "$SWEEP_DIR/sweep_synth.txt"
