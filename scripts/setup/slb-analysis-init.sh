#!/usr/bin/env bash
set -euo pipefail

# slb-analysis-init.sh
# --------------------
# Initialize a user's SLB analysis workspace up to thin-clone BIDS creation.

FORCE=0
SKIP_COPY=0
SKIP_VENV_INSTALL=0

usage() {
  cat <<EOF
Usage:
  $(basename "$0") [options]

Options:
  --force              Remove existing user BIDS/configs/models/venv and rebuild them
  --skip-copy          Do not copy fitlins_configs and fitlins_models
  --skip-venv-install  Create venv but do not install requirements.txt
  -h, --help           Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    --skip-copy) SKIP_COPY=1; shift ;;
    --skip-venv-install) SKIP_VENV_INSTALL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

GLOBAL_ENV="/data/sld/homes/collab/slb/.slb_global_env"
USER_ENV="/data/sld/homes/${USER}/.slb_user_env"

[[ -f "$GLOBAL_ENV" ]] || { echo "ERROR: global env not found: $GLOBAL_ENV" >&2; exit 1; }

# ✅ --- CREATE USER ENV IF MISSING ---
if [[ ! -f "$USER_ENV" || "$FORCE" == "1" ]]; then
  echo "[env] Creating user env: $USER_ENV"

  cat > "$USER_ENV" <<EOF
# SLB user environment

export SLB_USER_ROOT="/data/sld/homes/$USER/slb_work"

export SLB_USER_BIDS_DIR="\$SLB_USER_ROOT/slb_bids_runs"
export SLB_USER_EVENTS_DIR="\$SLB_USER_ROOT/slb_events"
export SLB_USER_CONFIGS="\$SLB_USER_ROOT/fitlins_configs"
export SLB_USER_MODELS="\$SLB_USER_ROOT/fitlins_models"
export SLB_USER_OUT="\$SLB_USER_ROOT/fitlins_derivatives"
export SLB_USER_WORK="\$SLB_USER_ROOT/work_fitlins"
export SLB_USER_REPORTS="\$SLB_USER_ROOT/reports"
export SLB_USER_FIGURES="\$SLB_USER_ROOT/figures"
EOF

  echo "[env] Created."
else
  echo "[env] Using existing user env: $USER_ENV"
fi

# --- LOAD ENVS ---
# shellcheck disable=SC1090
source "$GLOBAL_ENV"
# shellcheck disable=SC1090
source "$USER_ENV"

: "${SLB_ANALYSIS_ROOT:?ERROR: SLB_ANALYSIS_ROOT not set}"
: "${SLB_SOURCE_BIDS_DIR:?ERROR: SLB_SOURCE_BIDS_DIR not set}"
: "${SLB_USER_ROOT:?ERROR: SLB_USER_ROOT not set}"
: "${SLB_USER_BIDS_DIR:?ERROR: SLB_USER_BIDS_DIR not set}"
: "${SLB_USER_CONFIGS:?ERROR: SLB_USER_CONFIGS not set}"
: "${SLB_USER_MODELS:?ERROR: SLB_USER_MODELS not set}"
: "${SLB_USER_OUT:?ERROR: SLB_USER_OUT not set}"
: "${SLB_USER_WORK:?ERROR: SLB_USER_WORK not set}"
: "${SLB_USER_REPORTS:?ERROR: SLB_USER_REPORTS not set}"
: "${SLB_USER_FIGURES:?ERROR: SLB_USER_FIGURES not set}"

REBUILD_SCRIPT="$SLB_ANALYSIS_ROOT/scripts/build/rebuild_bids_runs_thinclone.py"
SHARED_CONFIGS="$SLB_ANALYSIS_ROOT/fitlins_configs"
SHARED_MODELS="$SLB_ANALYSIS_ROOT/fitlins_models"
REQUIREMENTS_TXT="$SLB_ANALYSIS_ROOT/requirements.txt"
SLB_USER_VENV="$SLB_USER_ROOT/venv"

[[ -f "$REBUILD_SCRIPT" ]] || { echo "ERROR: rebuild script not found: $REBUILD_SCRIPT" >&2; exit 1; }
[[ -d "$SHARED_CONFIGS" ]] || { echo "ERROR: shared configs dir not found: $SHARED_CONFIGS" >&2; exit 1; }
[[ -d "$SHARED_MODELS"  ]] || { echo "ERROR: shared models dir not found: $SHARED_MODELS" >&2; exit 1; }
[[ -d "$SLB_SOURCE_BIDS_DIR" ]] || { echo "ERROR: source BIDS dir not found: $SLB_SOURCE_BIDS_DIR" >&2; exit 1; }

echo "== SLB analysis init =="
echo "User:               $USER"
echo "SLB_USER_ROOT:      $SLB_USER_ROOT"
echo "SLB_USER_BIDS_DIR:  $SLB_USER_BIDS_DIR"
echo "SLB_USER_CONFIGS:   $SLB_USER_CONFIGS"
echo "SLB_USER_MODELS:    $SLB_USER_MODELS"
echo "SLB_USER_VENV:      $SLB_USER_VENV"
echo "Force:              $FORCE"
echo

echo "[module] Loading Python..."
module use /software/sld/modulefiles
module load python/3.12.8

python3 --version

if [[ "$FORCE" == "1" ]]; then
  echo "[force] Removing existing user setup targets..."
  rm -rf \
    "$SLB_USER_BIDS_DIR" \
    "$SLB_USER_CONFIGS" \
    "$SLB_USER_MODELS" \
    "$SLB_USER_VENV"
fi

echo "[dirs] Creating directories..."
mkdir -p \
  "$SLB_USER_ROOT" \
  "$SLB_USER_CONFIGS" \
  "$SLB_USER_MODELS" \
  "$SLB_USER_OUT" \
  "$SLB_USER_WORK" \
  "$SLB_USER_REPORTS" \
  "$SLB_USER_FIGURES"

if [[ ! -d "$SLB_USER_VENV" ]]; then
  echo "[venv] Creating virtual environment..."
  python3 -m venv "$SLB_USER_VENV"
fi

# shellcheck disable=SC1090
source "$SLB_USER_VENV/bin/activate"

if [[ "$SKIP_VENV_INSTALL" == "0" && -f "$REQUIREMENTS_TXT" ]]; then
  echo "[venv] Installing requirements..."
  python -m pip install --upgrade pip
  python -m pip install -r "$REQUIREMENTS_TXT"
fi

if [[ "$SKIP_COPY" == "0" ]]; then
  echo "[copy] Copying configs/models..."
  rm -rf "$SLB_USER_CONFIGS" "$SLB_USER_MODELS"
  mkdir -p "$SLB_USER_CONFIGS" "$SLB_USER_MODELS"
  cp -R "$SHARED_CONFIGS/." "$SLB_USER_CONFIGS/"
  cp -R "$SHARED_MODELS/."  "$SLB_USER_MODELS/"
fi

if [[ -e "$SLB_USER_BIDS_DIR" ]]; then
  echo "[bids] Exists: $SLB_USER_BIDS_DIR (use --force to rebuild)"
else
  echo "[bids] Building thin clone..."
  python3 "$REBUILD_SCRIPT" \
    --src "$SLB_SOURCE_BIDS_DIR" \
    --dst "$SLB_USER_BIDS_DIR"
fi

echo
echo "== Setup complete =="
echo "Next steps:"
echo "  source $GLOBAL_ENV"
echo "  source /data/sld/homes/$USER/.slb_user_env"
echo "  module load python/3.12.8"
echo "  source $SLB_USER_VENV/bin/activate"