#!/bin/bash
# =============================================================================
# CRACK - Flot licence (Cadence) : script racine
#
# Enchaîne les étapes du flot licence de Croc pour une techno donnée.
# Chaque exécution crée un répertoire de run archivable :
#   cadence/runs/licence_<techno>_<freq>MHz_<date>[_<tag>]/
#     run_implem.log    log complet de ce script (env, commandes, erreurs)
#     run_info.txt      commit, options, variables (traçabilité VAL-19)
#     config/           copie de la config utilisée
#     constraints/      SDC + MMMC générés
#     genus/logs/       genus.log (log Genus), genus.cmd, genus.stdout
#     genus/reports/    rapports
#     genus/out/        netlist, sdc, base innovus
#
# Terminal : uniquement les messages [CRACK] (avancement, warnings, erreurs).
# Tout le détail est dans les fichiers de log du run.
#
# Etapes disponibles : synth (Genus). pnr / signoff : à venir.
# =============================================================================
set -e
set -u
set -o pipefail

CRACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CROC_ROOT="$(cd "$CRACK_ROOT/.." && pwd)"

# ----------------------------------------------------------------------------
# Valeurs par défaut (mêmes défauts que le flot open : sg13cmos5l, 100 MHz)
# ----------------------------------------------------------------------------
TECH="ihp130_sg13cmos5l"
STEPS="synth"
CLK_NS="10.0"
TAG=""
ENV_FILE="${CRACK_CADENCE_ENV:-}"
DRYRUN=0
VERBOSE=0
STOP_AFTER=""
HIER=""
EFFORT=""
INTERCO=""

show_help() {
    cat << EOF
Flot licence CRACK (Cadence) - Croc

Usage : ./run_implem.sh [OPTIONS]

Options :
  -t, --tech <nom>        techno (config/tech/<nom>.tcl)       [$TECH]
  -s, --steps <liste>     étapes séparées par des virgules     [$STEPS]
                          synth | pnr | signoff | all
  -c, --clk <ns>          période de clk_sys en ns             [$CLK_NS]
      --tag <texte>       suffixe ajouté au nom du run
      --env <fichier>     environnement outils à sourcer        [env_cime.sh]
      --hier <mode>       yosys_like | keep_all | auto         [yosys_like]
      --effort <niv>      effort Genus generic/map/opt          [medium]
      --interconnect <m>  ple | none                            [ple]
      --stop-after <étp>  arrêt Genus après 01_init|02_elaborate|03_synthesis
  -v, --verbose           affiche aussi toute la sortie des outils au terminal
  -n, --dry-run           affiche les commandes sans les lancer
  -l, --list-techs        liste les technos disponibles
  -h, --help              cette aide

Exemples :
  ./run_implem.sh --tech ihp130_sg13cmos5l --steps synth
  ./run_implem.sh -t ihp130_sg13g2 -c 8.0 --tag sweep
  ./run_implem.sh --stop-after 02_elaborate      # vérifier la lecture du RTL
EOF
}

# ----------------------------------------------------------------------------
# Messages : fd 3 = terminal. Une fois le run créé, stdout/stderr du script
# partent dans run_implem.log ; log/warn/die écrivent aux DEUX endroits.
# ----------------------------------------------------------------------------
exec 3>&1
_msg() { echo "$*"; if [[ "${LOG_TO_FILE:-0}" -eq 1 ]]; then echo "$*" >&3; fi; }
log()  { _msg "[CRACK][INFO] $*"; }
warn() { _msg "[CRACK][WARNING] $*"; }
die()  {
    _msg "[CRACK][ERROR] $*"
    [[ -n "${RUN_LOG:-}" ]] && echo "[CRACK][ERROR] Log complet : $RUN_LOG" >&3
    exit 1
}
# Erreur inattendue (set -e) : on dit où, au lieu de quitter en silence
trap 'die "échec inattendu ligne $LINENO : $BASH_COMMAND"' ERR

run_cmd() {
    if [[ "$DRYRUN" -eq 1 ]]; then
        echo "  > $*"
    else
        echo "+ $*"
        eval "$@"
    fi
}

# ----------------------------------------------------------------------------
# Arguments
# ----------------------------------------------------------------------------
ORIG_ARGS="$*"
# Sans argument : flot par défaut (synth, ihp130_sg13cmos5l, 100 MHz). Aide : -h
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t|--tech)         TECH="$2"; shift 2 ;;
        -s|--steps)        STEPS="$2"; shift 2 ;;
        -c|--clk)          CLK_NS="$2"; shift 2 ;;
        --tag)             TAG="$2"; shift 2 ;;
        --env)             ENV_FILE="$2"; shift 2 ;;
        --hier)            HIER="$2"; shift 2 ;;
        --effort)          EFFORT="$2"; shift 2 ;;
        --interconnect)    INTERCO="$2"; shift 2 ;;
        --stop-after)      STOP_AFTER="$2"; shift 2 ;;
        -v|--verbose)      VERBOSE=1; shift ;;
        -n|--dry-run)      DRYRUN=1; shift ;;
        -l|--list-techs)   ls "$CRACK_ROOT/config/tech" | grep -v common | sed 's/\.tcl$//'; exit 0 ;;
        -h|--help)         show_help; exit 0 ;;
        *)                 die "Option inconnue : $1 (voir --help)" ;;
    esac
done

[[ -f "$CRACK_ROOT/config/tech/$TECH.tcl" ]] || die "Techno inconnue : $TECH (voir --list-techs)"
[[ "$CLK_NS" =~ ^[0-9]+([.][0-9]+)?$ ]]     || die "Période invalide : $CLK_NS"
[[ "$STEPS" == "all" ]] && STEPS="synth,pnr,signoff"
[[ -z "$ENV_FILE" ]] && ENV_FILE="$CRACK_ROOT/env_cime.sh"
[[ -f "$ENV_FILE" ]] || die "Fichier d'environnement introuvable : $ENV_FILE"

# ----------------------------------------------------------------------------
# Répertoire de run : [flot][techno][fréquence]_[date] (plan de validation §5)
# ----------------------------------------------------------------------------
FREQ_MHZ=$(awk -v p="$CLK_NS" 'BEGIN { printf "%g", 1000.0 / p }')
STAMP=$(date +%Y%m%d-%H%M%S)
RUN_NAME="licence_${TECH}_${FREQ_MHZ}MHz_${STAMP}${TAG:+_$TAG}"
RUN_DIR="$CRACK_ROOT/runs/$RUN_NAME"

log "Run    : $RUN_NAME"
log "Techno : $TECH   clk_sys : $CLK_NS ns ($FREQ_MHZ MHz)   étapes : $STEPS"

if [[ "$DRYRUN" -eq 0 ]]; then
    mkdir -p "$RUN_DIR"/{constraints,genus/logs,genus/reports,genus/out}
    RUN_LOG="$RUN_DIR/run_implem.log"
    # A partir d'ici : tout stdout/stderr -> run_implem.log, terminal via fd 3
    exec >>"$RUN_LOG" 2>&1
    LOG_TO_FILE=1
    echo "=== run_implem.sh $ORIG_ARGS  ($(date -Iseconds)) ==="
    ln -sfn "$RUN_NAME" "$CRACK_ROOT/runs/latest"
    log "Log    : $RUN_LOG"
fi

# ----------------------------------------------------------------------------
# Environnement outils (sortie dans le log, résumé au terminal)
# ----------------------------------------------------------------------------
echo "=== source $ENV_FILE ==="
set +u
# shellcheck disable=SC1090
source "$ENV_FILE" || warn "le fichier d'environnement a renvoyé une erreur (voir log)"
set -u
log "Env    : $ENV_FILE"
for t in genus innovus; do
    log "         $t -> $(command -v $t || echo 'ABSENT')"
done

if [[ ",$STEPS," == *",synth,"* && "$DRYRUN" -eq 0 ]]; then
    command -v genus >/dev/null 2>&1 \
        || die "genus introuvable dans le PATH après $ENV_FILE"
fi

# ----------------------------------------------------------------------------
# Variables lues par les scripts Tcl (common/utils.tcl : crack_env)
# ----------------------------------------------------------------------------
export CROC_ROOT CRACK_ROOT
export CRACK_RUN_DIR="$RUN_DIR"
export CRACK_TECH="$TECH"
export CRACK_CLK_SYS_NS="$CLK_NS"
if [[ -n "$HIER" ]];       then export CRACK_HIER_MODE="$HIER"; fi
if [[ -n "$EFFORT" ]];     then export CRACK_SYN_EFFORT="$EFFORT" CRACK_MAP_EFFORT="$EFFORT" CRACK_OPT_EFFORT="$EFFORT"; fi
if [[ -n "$INTERCO" ]];    then export CRACK_INTERCONNECT="$INTERCO"; fi
if [[ -n "$STOP_AFTER" ]]; then export CRACK_GENUS_STOP="$STOP_AFTER"; fi

# ----------------------------------------------------------------------------
# Traçabilité du run
# ----------------------------------------------------------------------------
write_run_info() {
    local git_hash git_dirty
    # (cd au lieu de git -C : le git du CIME est trop ancien pour -C)
    git_hash=$(cd "$CROC_ROOT" && git rev-parse HEAD 2>/dev/null) || git_hash="inconnu"
    git_dirty=$( (cd "$CROC_ROOT" && git status --porcelain 2>/dev/null) | wc -l) || git_dirty="?"
    {
        echo "run_name     $RUN_NAME"
        echo "date         $(date -Iseconds)"
        echo "user@host    $(whoami)@$(hostname)"
        echo "git_commit   $git_hash"
        echo "git_dirty    $git_dirty fichier(s) modifié(s)"
        echo "tech         $TECH"
        echo "clk_sys_ns   $CLK_NS"
        echo "steps        $STEPS"
        echo "command      $0 $ORIG_ARGS"
        echo "env_file     $ENV_FILE"
        echo "genus_bin    $(command -v genus || echo absent)"
        echo "innovus_bin  $(command -v innovus || echo absent)"
        echo "--- variables CRACK_* ---"
        env | grep '^CRACK_' | sort || true
    } > "$RUN_DIR/run_info.txt"
}

if [[ "$DRYRUN" -eq 0 ]]; then
    cp -r "$CRACK_ROOT/config" "$CRACK_ROOT/constraints" "$RUN_DIR/"
    write_run_info
fi

# ----------------------------------------------------------------------------
# Lance un outil : sortie complète dans <fichier>, seuls les messages [CRACK]
# et les erreurs de l'outil au terminal (tout au terminal avec --verbose).
#   run_tool <fichier_stdout> <commande...>
# ----------------------------------------------------------------------------
run_tool() {
    local out="$1"; shift
    if [[ "$DRYRUN" -eq 1 ]]; then
        echo "  > $*  > $out"
        return 0
    fi
    echo "+ $*  (sortie : $out)"
    local rc
    set +e
    if [[ "$VERBOSE" -eq 1 ]]; then
        eval "$@" 2>&1 | tee "$out" >&3
    else
        eval "$@" 2>&1 | tee "$out" \
            | grep --line-buffered -E '^\[CRACK\]\[|^\[CRACK\] Genus|^Error|^ERROR|\*\*ERROR' >&3
    fi
    rc=${PIPESTATUS[0]}
    set -e
    return "$rc"
}

# ----------------------------------------------------------------------------
# Etapes
# ----------------------------------------------------------------------------
step_synth() {
    local gdir="$RUN_DIR/genus"
    log "Synthèse Genus... (log : $gdir/logs/genus.log)"
    [[ "$DRYRUN" -eq 0 ]] && cd "$gdir"
    run_tool "$gdir/logs/genus.stdout" \
        genus -batch -overwrite \
            -files "$CRACK_ROOT/genus/scripts/genus_main.tcl" \
            -log "$gdir/logs/genus" \
        || die "Genus a échoué, voir $gdir/logs/genus.log"
    [[ "$DRYRUN" -eq 1 ]] && return 0

    if [[ -z "$STOP_AFTER" ]]; then
        local nl="$gdir/out/${PROJ_NAME:-croc}_genus.v"
        [[ -f "$nl" ]] || die "Pas de netlist produite, voir $gdir/logs/genus.log"
        log "Netlist : $nl"
    fi
    local nwarn
    nwarn=$(grep -c "\[CRACK\]\[WARNING\]" "$gdir/logs/genus.stdout" 2>/dev/null) || nwarn=0
    log "Genus terminé : $nwarn warning(s) CRACK, rapports dans $gdir/reports"
}

step_pnr()     { die "Etape pnr (Innovus) pas encore implémentée"; }
step_signoff() { die "Etape signoff pas encore implémentée"; }

IFS=',' read -r -a STEP_LIST <<< "$STEPS"
for s in "${STEP_LIST[@]}"; do
    case "$s" in
        synth)   step_synth ;;
        pnr)     step_pnr ;;
        signoff) step_signoff ;;
        *)       die "Etape inconnue : $s" ;;
    esac
done

log "Terminé : $RUN_DIR"
