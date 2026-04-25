#!/bin/bash
# =============================================================================
# run_p1_07.sh — orchestration ticket P1-07 (DEV_PLAN.md)
#
# Run baseline aerial seul, fine-tune MAESTRO sur PureForest 13 classes
# sur une instance GPU Scaleway. Creation de l'instance + copie des
# scripts + lancement dans tmux + sauvegarde des coordonnees.
#
# Pre-requis :
#   - CLI Scaleway installee et configuree (scw init)
#   - Cle SSH configuree dans Scaleway
#   - HuggingFace token disponible (export HF_TOKEN=hf_...) si limites
#
# Usage :
#   bash inst/scripts/run_p1_07.sh                # L4-1-24G, defauts
#   bash inst/scripts/run_p1_07.sh --instance-type H100-1-80G --batch-size 64
#   bash inst/scripts/run_p1_07.sh --dry-run      # affiche sans executer
#
# Apres execution, suivre :
#   ssh -t root@<IP> 'tmux attach -t maestro'
#
# Recuperer le modele (apres training termine) :
#   bash inst/scripts/recover_model.sh                 # legacy, TreeSatAI
#   scp root@<IP>:/data/outputs/training/maestro_pureforest_best.pt .
#   scp root@<IP>:/data/outputs/training/maestro_pureforest_best.report.json .
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERREUR]${NC} $*"; }

# --- Defauts ---
INSTANCE_TYPE="L4-1-24G"
IMAGE="ubuntu_jammy_gpu_os_12"
ZONE="fr-par-2"
INSTANCE_NAME="maestro-pureforest"
DATA_VOLUME_GB=200    # PureForest pretraite ~50 Go + venv + cache HF + checkpoint
PROBE_EPOCHS=10
FINETUNE_EPOCHS=50
BATCH_SIZE=24
LR_HEAD="1e-3"
LR_FT_HEAD="1e-4"
LR_ENCODER="1e-5"
PATIENCE=5
MODALITIES="aerial"
NOTIFY_EMAIL="${NOTIFY_EMAIL:-}"
NOTIFY_WEBHOOK="${NOTIFY_WEBHOOK:-}"
HF_TOKEN="${HF_TOKEN:-}"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --instance-type)   INSTANCE_TYPE="$2"; shift 2 ;;
        --image)           IMAGE="$2"; shift 2 ;;
        --zone)            ZONE="$2"; shift 2 ;;
        --name)            INSTANCE_NAME="$2"; shift 2 ;;
        --data-volume)     DATA_VOLUME_GB="$2"; shift 2 ;;
        --probe-epochs)    PROBE_EPOCHS="$2"; shift 2 ;;
        --finetune-epochs) FINETUNE_EPOCHS="$2"; shift 2 ;;
        --batch-size)      BATCH_SIZE="$2"; shift 2 ;;
        --lr-head)         LR_HEAD="$2"; shift 2 ;;
        --lr-ft-head)      LR_FT_HEAD="$2"; shift 2 ;;
        --lr-encoder)      LR_ENCODER="$2"; shift 2 ;;
        --patience)        PATIENCE="$2"; shift 2 ;;
        --modalities)      MODALITIES="$2"; shift 2 ;;
        --notify-email)    NOTIFY_EMAIL="$2"; shift 2 ;;
        --notify-webhook)  NOTIFY_WEBHOOK="$2"; shift 2 ;;
        --hf-token)        HF_TOKEN="$2"; shift 2 ;;
        --dry-run)         DRY_RUN=true; shift ;;
        -h|--help)
            head -32 "$0" | tail -28
            exit 0 ;;
        *) log_error "Option inconnue: $1"; exit 1 ;;
    esac
done

echo
echo "========================================================"
echo " P1-07 : Fine-tune MAESTRO sur PureForest 13 classes"
echo "========================================================"
log_info "Instance type    : $INSTANCE_TYPE (zone $ZONE)"
log_info "Volume data      : ${DATA_VOLUME_GB} Go"
log_info "Probe epochs     : $PROBE_EPOCHS"
log_info "Fine-tune epochs : $FINETUNE_EPOCHS"
log_info "Batch size       : $BATCH_SIZE"
log_info "Modalites        : $MODALITIES"
log_info "Notifications    : ${NOTIFY_EMAIL:+email=$NOTIFY_EMAIL} ${NOTIFY_WEBHOOK:+webhook=set}"
echo

# --- Pre-requis CLI ---
log_info "Verification des pre-requis..."
command -v scw >/dev/null || { log_error "CLI Scaleway non installee"; exit 1; }
scw account project get >/dev/null 2>&1 || { log_error "scw non configure (lancer scw init)"; exit 1; }
log_ok "CLI Scaleway configuree"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# --- Construction de la commande de creation ---
CREATE_CMD="scw instance server create \
    type=$INSTANCE_TYPE \
    image=$IMAGE \
    zone=$ZONE \
    name=$INSTANCE_NAME \
    ip=new \
    additional-volumes.0=block:${DATA_VOLUME_GB}GB \
    --output json"

if $DRY_RUN; then
    log_warn "[DRY-RUN] Commandes qui seraient executees :"
    echo "  $CREATE_CMD"
    echo "  scp inst/scripts/cloud_train_pureforest.sh root@<IP>:~/"
    echo "  scp inst/scripts/mount_data.sh root@<IP>:~/"
    echo "  scp inst/python/{maestro_inference,pureforest_dataset,pureforest_finetune,prepare_pureforest_aerial}.py root@<IP>:/root/local_python/"
    echo "  ssh root@<IP> 'tmux new-session -d -s maestro \"bash /root/run_train.sh\"'"
    exit 0
fi

# --- Reutilisation eventuelle d'une instance ---
log_info "Recherche d'instance existante '$INSTANCE_NAME'..."
EXISTING_JSON=$(scw instance server list zone="$ZONE" name="$INSTANCE_NAME" -o json 2>/dev/null || echo "[]")
EXISTING_COUNT=$(echo "$EXISTING_JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")

SERVER_ID=""
if [ "$EXISTING_COUNT" -gt 0 ]; then
    SERVER_ID=$(echo "$EXISTING_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")
    STATE=$(echo "$EXISTING_JSON"   | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['state'])")
    log_warn "Instance existante : $SERVER_ID (etat: $STATE)"
    if [ "$STATE" = "stopped" ] || [ "$STATE" = "stopped in place" ]; then
        log_info "Demarrage..."
        scw instance server action run "$SERVER_ID" zone="$ZONE" >/dev/null
    elif [ "$STATE" != "running" ]; then
        log_error "Etat inattendu : $STATE — supprime ou reessaie plus tard"
        exit 1
    fi
fi

if [ -z "$SERVER_ID" ]; then
    log_info "Creation de l'instance..."
    SERVER_JSON=$(eval "$CREATE_CMD")
    SERVER_ID=$(echo "$SERVER_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
    log_ok "Instance creee : $SERVER_ID"
fi

# --- Attendre que l'instance soit prete ---
log_info "Attente du demarrage..."
scw instance server wait "$SERVER_ID" zone="$ZONE" timeout=600s

SERVER_INFO=$(scw instance server get "$SERVER_ID" zone="$ZONE" -o json)
PUBLIC_IP=$(echo "$SERVER_INFO" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if 'public_ip' in data and data['public_ip']:
    print(data['public_ip']['address'])
elif 'public_ips' in data and data['public_ips']:
    print(data['public_ips'][0]['address'])
else:
    sys.exit('Aucune IP publique')
")
log_ok "Instance prete : $PUBLIC_IP"

# --- Attendre SSH (jusqu'a 10 min sur GPU images Scaleway) ---
log_info "Attente du serveur SSH (jusqu'a 600 s)..."
ssh-keygen -R "$PUBLIC_IP" >/dev/null 2>&1 || true
SSH_TIMEOUT=600
SSH_ELAPSED=0
SSH_INTERVAL=15
while [ "$SSH_ELAPSED" -lt "$SSH_TIMEOUT" ]; do
    if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o BatchMode=yes \
            "root@$PUBLIC_IP" "echo ok" >/dev/null 2>&1; then
        log_ok "SSH disponible apres ${SSH_ELAPSED}s"
        break
    fi
    SSH_ELAPSED=$((SSH_ELAPSED + SSH_INTERVAL))
    log_info "  ${SSH_ELAPSED}/${SSH_TIMEOUT}s..."
    sleep "$SSH_INTERVAL"
done

if [ "$SSH_ELAPSED" -ge "$SSH_TIMEOUT" ]; then
    log_error "Timeout SSH"
    exit 1
fi

# --- Monter le volume data ---
log_info "Montage volume /data..."
scp -o StrictHostKeyChecking=no "$REPO_ROOT/inst/scripts/mount_data.sh" "root@$PUBLIC_IP:~/"
ssh -o StrictHostKeyChecking=no "root@$PUBLIC_IP" "bash ~/mount_data.sh"
log_ok "Volume monte"

# --- Copier les scripts PureForest ---
log_info "Copie des scripts PureForest..."
ssh -o StrictHostKeyChecking=no "root@$PUBLIC_IP" "mkdir -p /root/local_python /root/local_conf"
scp -o StrictHostKeyChecking=no \
    "$REPO_ROOT/inst/python/maestro_inference.py" \
    "$REPO_ROOT/inst/python/pureforest_dataset.py" \
    "$REPO_ROOT/inst/python/pureforest_finetune.py" \
    "$REPO_ROOT/inst/python/prepare_pureforest_aerial.py" \
    "root@$PUBLIC_IP:/root/local_python/"
scp -o StrictHostKeyChecking=no \
    "$REPO_ROOT/inst/python/conf/pureforest.yaml" \
    "root@$PUBLIC_IP:/root/local_conf/" 2>/dev/null || true
scp -o StrictHostKeyChecking=no \
    "$REPO_ROOT/inst/scripts/cloud_train_pureforest.sh" \
    "root@$PUBLIC_IP:~/"
log_ok "Scripts copies"

# --- Construire le runner cote serveur (overlay des fichiers Python locaux) ---
log_info "Configuration du runner remote..."
ssh -o StrictHostKeyChecking=no "root@$PUBLIC_IP" bash <<REMOTE_EOF
    apt-get update -qq && apt-get install -y -qq tmux git >/dev/null 2>&1

    # Cloner le depot pour avoir une arbo coherente
    if [ ! -d /root/maestro_nemeton ]; then
        git clone https://github.com/pobsteta/maestro_nemeton.git /root/maestro_nemeton
    fi

    # Overlay des fichiers Python locaux (utiles si la branche distante est en retard)
    cp -v /root/local_python/*.py /root/maestro_nemeton/inst/python/
    mkdir -p /root/maestro_nemeton/inst/python/conf
    cp -v /root/local_conf/*.yaml /root/maestro_nemeton/inst/python/conf/ 2>/dev/null || true

    # Override le cloud_train_pureforest.sh local (au cas ou la branche est en retard)
    cp -v /root/cloud_train_pureforest.sh /root/maestro_nemeton/inst/scripts/

    cat > /root/run_train.sh <<TRAIN_EOF
#!/bin/bash
set -euo pipefail
export PROBE_EPOCHS=$PROBE_EPOCHS
export FINETUNE_EPOCHS=$FINETUNE_EPOCHS
export BATCH_SIZE=$BATCH_SIZE
export LR_HEAD=$LR_HEAD
export LR_FT_HEAD=$LR_FT_HEAD
export LR_ENCODER=$LR_ENCODER
export PATIENCE=$PATIENCE
export MODALITIES=$MODALITIES
export NOTIFY_EMAIL='${NOTIFY_EMAIL}'
export NOTIFY_WEBHOOK='${NOTIFY_WEBHOOK}'
export HUGGING_FACE_HUB_TOKEN='${HF_TOKEN}'
cd /root/maestro_nemeton
bash inst/scripts/cloud_train_pureforest.sh 2>&1 | tee ~/train.log
TRAIN_EOF
    chmod +x /root/run_train.sh

    tmux new-session -d -s maestro "bash /root/run_train.sh"
REMOTE_EOF

log_ok "Entrainement lance dans tmux (session 'maestro')"

# --- Sauvegarder les coordonnees ---
INFO_FILE="$REPO_ROOT/.scaleway_pureforest"
cat > "$INFO_FILE" <<INFOEOF
# P1-07 PureForest fine-tune lance le $(date -Iseconds)
SERVER_ID=$SERVER_ID
PUBLIC_IP=$PUBLIC_IP
ZONE=$ZONE
INSTANCE_NAME=$INSTANCE_NAME
INSTANCE_TYPE=$INSTANCE_TYPE
INFOEOF
log_info "Coordonnees : $INFO_FILE"

# --- Suite ---
echo
echo "========================================================"
echo -e " ${GREEN}Job P1-07 lance${NC}"
echo "========================================================"
echo
echo "  Instance  : $INSTANCE_NAME ($INSTANCE_TYPE)"
echo "  Server ID : $SERVER_ID"
echo "  IP        : $PUBLIC_IP"
echo
echo "Suivre l'entrainement (probe ~2 h, fine-tune ~10-15 h sur L4) :"
echo "  ssh -t root@$PUBLIC_IP 'tmux attach -t maestro'"
echo
echo "Verifier la GPU :"
echo "  ssh root@$PUBLIC_IP 'nvidia-smi'"
echo
echo "Voir les logs :"
echo "  ssh root@$PUBLIC_IP 'tail -f ~/train.log'"
echo
echo "Recuperer le modele (apres training termine) :"
echo "  scp root@$PUBLIC_IP:/data/outputs/training/maestro_pureforest_best.pt ."
echo "  scp root@$PUBLIC_IP:/data/outputs/training/maestro_pureforest_best.report.json ."
echo
echo "Predire sur une AOI :"
echo "  Rscript inst/scripts/predict_from_checkpoint.R \\"
echo "      --aoi data/aoi.gpkg --checkpoint maestro_pureforest_best.pt"
echo
echo "IMPORTANT : supprimer l'instance apres recuperation !"
echo "  scw instance server terminate $SERVER_ID zone=$ZONE with-ip=true"
echo
