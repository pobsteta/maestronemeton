#!/bin/bash
# =============================================================================
# cloud_train_pureforest.sh
# Setup + entrainement MAESTRO sur PureForest (13 classes mono-label) sur
# une instance GPU Scaleway.
#
# A executer SUR l'instance GPU apres connexion SSH.
# Differences avec cloud_train.sh (legacy TreeSatAI 8 classes) :
#   - dataset = IGNF/PureForest (ALS + aerial RGBI 250x250 -> 256x256)
#   - 13 classes mono-label, balanced_accuracy comme metrique principale
#   - linear probe puis fine-tune complet (cf. DEV_PLAN.md sec. 6)
#
# Variables d'environnement (toutes optionnelles) :
#   PROBE_EPOCHS=10        Epochs linear probe
#   FINETUNE_EPOCHS=50     Epochs fine-tune complet
#   BATCH_SIZE=24          Taille batch (24 sur L4-1-24G, 64 sur H100)
#   LR_HEAD=1e-3           LR head pendant le probe
#   LR_FT_HEAD=1e-4        LR head pendant le fine-tune
#   LR_ENCODER=1e-5        LR encodeur pendant le fine-tune
#   PATIENCE=5             Early stopping
#   MODALITIES=aerial      Modalites (aerial / aerial,dem / aerial,dem,s2,s1_asc,s1_des)
#   BRANCH=main            Branche git
#   NOTIFY_EMAIL=...       Email pour notifications
#   NOTIFY_WEBHOOK=...     URL webhook (ntfy.sh, Slack, etc.)
# =============================================================================

set -euo pipefail

# --- Notifications ---
NOTIFY_EMAIL="${NOTIFY_EMAIL:-}"
NOTIFY_WEBHOOK="${NOTIFY_WEBHOOK:-}"

send_notification() {
    local SUBJECT="$1"
    local SHORT_MSG="$2"
    local BODY="${3:-$SHORT_MSG}"

    if [ -n "$NOTIFY_EMAIL" ]; then
        echo "  -> Email : $NOTIFY_EMAIL"
        python3 -c "
import smtplib, socket
from email.mime.text import MIMEText
hostname = socket.gethostname()
msg = MIMEText('''$BODY''')
msg['Subject'] = '$SUBJECT'
msg['From'] = 'maestro@' + hostname
msg['To'] = '$NOTIFY_EMAIL'
try:
    with smtplib.SMTP('localhost', 25, timeout=10) as s:
        s.sendmail(msg['From'], ['$NOTIFY_EMAIL'], msg.as_string())
    print('    Email envoye')
except Exception as e:
    print(f'    SMTP local echoue: {e}')
    import subprocess
    try:
        p = subprocess.Popen(['/usr/sbin/sendmail', '-t'], stdin=subprocess.PIPE)
        p.communicate(msg.as_string().encode())
        print('    Email envoye via sendmail')
    except Exception as e2:
        print(f'    Echec sendmail: {e2}')
" 2>&1 || echo "  (notification email echouee)"
    fi

    if [ -n "$NOTIFY_WEBHOOK" ]; then
        echo "  -> Webhook"
        case "$NOTIFY_WEBHOOK" in
            *ntfy.sh*|*ntfy/*)
                curl -s -H "Title: $SUBJECT" -d "$BODY" "$NOTIFY_WEBHOOK" 2>&1 || true
                ;;
            *hooks.slack.com*)
                curl -s -X POST -H 'Content-type: application/json' \
                    --data "{\"text\":\"*$SUBJECT*\n$SHORT_MSG\"}" "$NOTIFY_WEBHOOK" 2>&1 || true
                ;;
            *)
                curl -s -X POST -H 'Content-type: application/json' \
                    --data "{\"subject\":\"$SUBJECT\",\"text\":\"$SHORT_MSG\"}" \
                    "$NOTIFY_WEBHOOK" 2>&1 || true
                ;;
        esac
    fi
}

echo "========================================================"
echo " MAESTRO - Fine-tuning PureForest (13 classes)"
echo "========================================================"

# --- Config ---
REPO_URL="https://github.com/pobsteta/maestronemeton.git"
BRANCH="${BRANCH:-main}"
WORK_DIR="$HOME/maestronemeton"

if [ -d /data ] && mountpoint -q /data 2>/dev/null; then
    DATA_DIR="${DATA_DIR:-/data/pureforest_maestro}"
    OUTPUT_DIR="${OUTPUT_DIR:-/data/outputs/training}"
    export HF_HOME="/data/.cache/huggingface"
    mkdir -p "$HF_HOME"
else
    DATA_DIR="${DATA_DIR:-$WORK_DIR/data/pureforest_maestro}"
    OUTPUT_DIR="${OUTPUT_DIR:-$WORK_DIR/outputs/training}"
fi

PROBE_EPOCHS="${PROBE_EPOCHS:-10}"
FINETUNE_EPOCHS="${FINETUNE_EPOCHS:-50}"
BATCH_SIZE="${BATCH_SIZE:-24}"
LR_HEAD="${LR_HEAD:-1e-3}"
LR_FT_HEAD="${LR_FT_HEAD:-1e-4}"
LR_ENCODER="${LR_ENCODER:-1e-5}"
PATIENCE="${PATIENCE:-5}"
MODALITIES="${MODALITIES:-aerial}"

# --- Identite instance pour notifs (calcule tot pour que trap ERR soit informatif) ---
HOSTNAME_LOCAL=$(hostname)
PUBLIC_IP=$(curl -s --max-time 3 http://169.254.42.42/conf?format=json 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('public_ip',{}).get('address','<IP>'))" 2>/dev/null \
    || echo "<IP>")

# --- Trap d'erreur : notifier en cas de crash (avant ou pendant le training) ---
# set -e propage l'exit, on enrichit juste avec une notif + tail du log.
trap 'rc=$?; send_notification \
    "[MAESTRO] CRASH ligne $LINENO" \
    "Crash sur ${HOSTNAME_LOCAL} (${PUBLIC_IP}) - exit=$rc - voir ~/train.log" \
    "Crash dans cloud_train_pureforest.sh
Ligne   : $LINENO
Cmde    : $BASH_COMMAND
Exit    : $rc

Dernieres lignes du log :
$(tail -80 ~/train.log 2>/dev/null || echo "(log indisponible)")"' ERR

# --- Notif de demarrage : envoyee TOT, avant le pre-traitement (qui peut planter sur disque plein) ---
send_notification \
    "[MAESTRO] Instance demarree" \
    "Setup PureForest demarre sur ${HOSTNAME_LOCAL} (${PUBLIC_IP}) - branche=${BRANCH} modalites=${MODALITIES}" \
    "Instance MAESTRO demarree, setup en cours.

  Hostname    : ${HOSTNAME_LOCAL}
  IP publique : ${PUBLIC_IP}
  Branche     : ${BRANCH}
  Modalites   : ${MODALITIES}
  Probe ep.   : ${PROBE_EPOCHS}
  Finetune ep.: ${FINETUNE_EPOCHS}

Etapes a venir :
  1. clone + venv + deps Python (~3 min)
  2. pre-traitement aerial (~15 min)
  3. pre-traitement dem (~30 min)
  4. download checkpoint MAESTRO_FLAIR-HUB_base (~1 min)
  5. fine-tune (~14-18 h)

Vous recevrez une autre notif au lancement du fine-tune,
puis a la fin (ou en cas de crash)."

# --- Cloner le depot ---
if [ ! -d "$WORK_DIR" ]; then
    echo "=== Clonage du depot ==="
    git clone -b "$BRANCH" "$REPO_URL" "$WORK_DIR"
fi
cd "$WORK_DIR"

# --- venv Python ---
echo "=== Installation des dependances Python ==="
VENV_TEST="/tmp/_venv_test_$$"
if ! python3 -m venv "$VENV_TEST" 2>/dev/null; then
    apt-get update -qq
    PY_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    apt-get install -y -qq "python${PY_VERSION}-venv" python3-venv 2>/dev/null || \
        apt-get install -y -qq python3-venv
fi
rm -rf "$VENV_TEST"

if [ -d /data ] && mountpoint -q /data 2>/dev/null; then
    DEFAULT_VENV="/data/venv_maestro"
else
    DEFAULT_VENV="$HOME/venv_maestro"
fi
VENV_DIR="${VENV_DIR:-$DEFAULT_VENV}"
[ -d "$VENV_DIR" ] || python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
PYTHON="$VENV_DIR/bin/python"

$PYTHON -m pip install --quiet --upgrade pip
# Versions pinees au minor : reproductibilite tout en laissant les patchs de
# securite passer. Une version trop stricte (==X.Y.Z) casse des qu'une release
# est retiree de PyPI ; trop laxe (sans borne haute) laisse derive.
$PYTHON -m pip install --quiet \
    'torch>=2.5,<3' 'numpy>=1.26,<3' 'safetensors>=0.4,<1' \
    'rasterio>=1.3,<2' 'tifffile>=2023.1' 'pillow>=10,<13' \
    'huggingface_hub>=0.20,<2' 'tqdm>=4.65,<5' \
    'laspy>=2.5,<3' 'lazrs>=0.5,<1' 'scipy>=1.10,<2'

echo
echo "=== Verification GPU ==="
$PYTHON -c "
import torch
print(f'PyTorch {torch.__version__}')
print(f'CUDA: {torch.cuda.is_available()}')
if torch.cuda.is_available():
    print(f'GPU : {torch.cuda.get_device_name(0)}')
    print(f'VRAM: {torch.cuda.get_device_properties(0).total_memory/1e9:.1f} Go')
else:
    print('ATTENTION: pas de GPU')
"

# --- Preparation du dataset (idempotent par modalite) ---
# Le cache HF des zips PureForest (imagery-*.zip ~25 Go, lidar-*.zip ~120 Go)
# est purge entre etapes : une fois les patches extraits, les zips sources ne
# servent plus. Sans purge, 200 Go ne suffisent pas pour aerial+dem.
HF_PUREFOREST_BLOBS="$HF_HOME/datasets--IGNF--PureForest/blobs"

echo
echo "=== Pre-traitement PureForest aerial (~25 Go zip + ~50 Go patches) ==="
$PYTHON inst/python/prepare_pureforest_aerial.py \
    --output "$DATA_DIR" \
    --cache "$HF_HOME"

if [ -d "$HF_PUREFOREST_BLOBS" ]; then
    echo "  Purge cache HF aerial (zips imagery-*) ..."
    rm -rf "$HF_PUREFOREST_BLOBS"/*
fi

# La modalite dem est generee si elle est demandee dans MODALITIES.
# Le script est idempotent : reutilise les patches dem.tif deja presents.
if echo ",$MODALITIES," | grep -q ",dem,"; then
    echo
    echo "=== Pre-traitement PureForest dem (LAZ -> DSM/DTM, ~120 Go zip + ~3 Go patches) ==="
    $PYTHON inst/python/prepare_pureforest_dem.py \
        --output "$DATA_DIR" \
        --cache "$HF_HOME"

    if [ -d "$HF_PUREFOREST_BLOBS" ]; then
        echo "  Purge cache HF dem (zips lidar-*) ..."
        rm -rf "$HF_PUREFOREST_BLOBS"/*
    fi
fi

# --- Telechargement checkpoint pre-entraine ---
echo
echo "=== Telechargement checkpoint MAESTRO_FLAIR-HUB_base ==="
CHECKPOINT=$($PYTHON -c "
from huggingface_hub import hf_hub_download
path = hf_hub_download('IGNF/MAESTRO_FLAIR-HUB_base',
    'MAESTRO_FLAIR-HUB_base/checkpoints/pretrain-epoch=99.ckpt')
print(path)
")
echo "Checkpoint : $CHECKPOINT"

# --- Notification de demarrage ---
GPU_NAME=$($PYTHON -c "import torch; print(torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'CPU')" 2>/dev/null || echo "inconnu")
PUBLIC_IP=$(curl -s http://169.254.42.42/conf?format=json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('public_ip',{}).get('address','<IP>'))" 2>/dev/null || echo "<IP>")
HOSTNAME=$(hostname)
START_TIME=$(date '+%Y-%m-%d %H:%M:%S')

send_notification \
    "[MAESTRO] PureForest fine-tune demarre" \
    "MAESTRO PureForest 13 classes - $HOSTNAME ($PUBLIC_IP) GPU $GPU_NAME - probe $PROBE_EPOCHS / fine-tune $FINETUNE_EPOCHS - modalites $MODALITIES" \
    "Bonjour,

Fine-tuning MAESTRO sur PureForest (13 classes) demarre.

  Instance       : $HOSTNAME ($PUBLIC_IP)
  GPU            : $GPU_NAME
  Debut          : $START_TIME
  Probe epochs   : $PROBE_EPOCHS
  Fine-tune ep.  : $FINETUNE_EPOCHS
  Batch size     : $BATCH_SIZE
  Modalites      : $MODALITIES
  LR head        : $LR_HEAD (probe), $LR_FT_HEAD (ft)
  LR encodeur    : $LR_ENCODER
  Patience       : $PATIENCE

Suivi en temps reel :
  ssh -t root@${PUBLIC_IP} 'tmux attach -t maestro'

Vous recevrez une notification de fin."

# --- Lancer l'entrainement ---
echo
echo "=== Lancement du fine-tuning ==="
echo "  Probe epochs     : $PROBE_EPOCHS"
echo "  Fine-tune epochs : $FINETUNE_EPOCHS"
echo "  Batch size       : $BATCH_SIZE"
echo "  Modalites        : $MODALITIES"
echo

mkdir -p "$OUTPUT_DIR"
N_WORKERS=$(nproc --ignore=2 2>/dev/null || echo 4)
N_WORKERS=$((N_WORKERS > 8 ? 8 : N_WORKERS))

# Convertir "aerial,dem" en "aerial dem"
MODS_ARGS=$(echo "$MODALITIES" | tr ',' ' ')

$PYTHON inst/python/pureforest_finetune.py \
    --checkpoint "$CHECKPOINT" \
    --data-dir "$DATA_DIR" \
    --output "$OUTPUT_DIR/maestro_pureforest_best.pt" \
    --modalities $MODS_ARGS \
    --probe-epochs "$PROBE_EPOCHS" \
    --finetune-epochs "$FINETUNE_EPOCHS" \
    --batch-size "$BATCH_SIZE" \
    --lr-head "$LR_HEAD" \
    --lr-finetune-head "$LR_FT_HEAD" \
    --lr-encoder "$LR_ENCODER" \
    --patience "$PATIENCE" \
    --workers "$N_WORKERS" \
    --gpu

# --- Resultats ---
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
echo
echo "========================================================"
echo " Fine-tuning termine ($TIMESTAMP)"
echo "========================================================"
echo
echo "Modeles sauvegardes :"
ls -lh "$OUTPUT_DIR"/*.pt 2>/dev/null || echo "  (aucun .pt trouve)"
echo
echo "Recuperation locale :"
echo "  scp root@${PUBLIC_IP}:$OUTPUT_DIR/maestro_pureforest_best.pt ."
echo "  scp root@${PUBLIC_IP}:$OUTPUT_DIR/maestro_pureforest_best.report.json ."
echo
echo "Prediction sur AOI :"
echo "  Rscript inst/scripts/predict_from_checkpoint.R \\"
echo "      --aoi data/aoi.gpkg \\"
echo "      --checkpoint maestro_pureforest_best.pt"
echo
echo "IMPORTANT : supprimer l'instance Scaleway apres recuperation !"

touch ~/TRAINING_DONE

END_TIME=$(date '+%Y-%m-%d %H:%M:%S')
DUREE=$((SECONDS / 60))
BEST=$(ls -1 "$OUTPUT_DIR"/maestro_pureforest_best.pt 2>/dev/null && echo oui || echo non)
BACC=$(python3 -c "import json; print(json.load(open('$OUTPUT_DIR/maestro_pureforest_best.report.json')).get('test_bacc', 'NA'))" 2>/dev/null || echo "NA")

send_notification \
    "[MAESTRO] PureForest fine-tune termine" \
    "Termine sur $HOSTNAME ($PUBLIC_IP) en ${DUREE}min - test_bacc=$BACC - modele: $BEST" \
    "Bonjour,

Fine-tuning MAESTRO PureForest termine.

  Instance     : $HOSTNAME ($PUBLIC_IP)
  Debut        : $START_TIME
  Fin          : $END_TIME
  Duree        : ${DUREE} minutes
  test_bacc    : $BACC
  Modele       : $BEST
  Sortie       : $OUTPUT_DIR

Recuperation :
  scp root@${PUBLIC_IP}:$OUTPUT_DIR/maestro_pureforest_best.pt .

IMPORTANT : supprimer l'instance Scaleway !
  scw instance server terminate <SERVER_ID>"
