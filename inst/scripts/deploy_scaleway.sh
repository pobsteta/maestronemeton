#!/bin/bash
# =============================================================================
# deploy_scaleway.sh
# Guide complet pour deployer l'entrainement MAESTRO sur une instance GPU Scaleway.
#
# Ce script est execute DEPUIS VOTRE MACHINE LOCALE. Il :
#   1. Cree une instance GPU Scaleway (via CLI scw)
#   2. Envoie le script d'entrainement sur l'instance
#   3. Lance l'entrainement en arriere-plan (tmux)
#   4. Donne les commandes pour suivre et recuperer le modele
#
# Pre-requis :
#   - CLI Scaleway installee et configuree (scw init)
#   - Cle SSH configuree dans Scaleway
#   - Projet/organisation Scaleway active
#
# Usage :
#   bash inst/scripts/deploy_scaleway.sh [OPTIONS]
#
# Options :
#   --instance-type TYPE   Type d'instance GPU (defaut: L4-1-24G)
#   --image IMAGE          Image OS (defaut: ubuntu_jammy_gpu_os_12)
#   --zone ZONE            Zone Scaleway (defaut: fr-par-2)
#   --epochs N             Nombre d'epochs (defaut: 30)
#   --batch-size N         Taille batch (defaut: 64)
#   --lr FLOAT             Learning rate (defaut: 1e-3)
#   --modalites MODS       Modalites (defaut: aerial)
#   --unfreeze             Degeler le backbone (fine-tuning complet)
#   --name NAME            Nom de l'instance (defaut: maestro-train)
#   --dry-run              Afficher les commandes sans executer
#
# Instances GPU Scaleway recommandees :
#   GPU-3070-S   : RTX 3070 (8 Go VRAM)  - ~0.76 EUR/h - suffisant pour aerial seul
#   L4-1-24G     : NVIDIA L4 (24 Go VRAM) - ~0.92 EUR/h - recommande multi-modal
#   H100-1-80G   : H100 (80 Go VRAM)     - ~3.50 EUR/h - entrainement rapide
#
# Cout estime pour 30 epochs (aerial, batch_size=64) :
#   GPU-3070-S : ~2-3h -> ~2 EUR
#   L4-1-24G   : ~1-2h -> ~1.50 EUR
# =============================================================================

set -euo pipefail

# --- Couleurs pour l'affichage ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERREUR]${NC} $*"; }

# --- Configuration par defaut ---
INSTANCE_TYPE="L4-1-24G"
IMAGE="ubuntu_jammy_gpu_os_12"
ZONE="fr-par-2"
INSTANCE_NAME="maestro-train"
DATA_VOLUME_GB=100
EPOCHS=30
BATCH_SIZE=64
LR="1e-3"
MODALITES="aerial"
UNFREEZE=""
DRY_RUN=false

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case $1 in
        --instance-type) INSTANCE_TYPE="$2"; shift 2 ;;
        --image)         IMAGE="$2"; shift 2 ;;
        --zone)          ZONE="$2"; shift 2 ;;
        --epochs)        EPOCHS="$2"; shift 2 ;;
        --batch-size)    BATCH_SIZE="$2"; shift 2 ;;
        --lr)            LR="$2"; shift 2 ;;
        --modalites)     MODALITES="$2"; shift 2 ;;
        --unfreeze)      UNFREEZE="--unfreeze"; shift ;;
        --name)          INSTANCE_NAME="$2"; shift 2 ;;
        --data-volume)   DATA_VOLUME_GB="$2"; shift 2 ;;
        --dry-run)       DRY_RUN=true; shift ;;
        -h|--help)
            head -45 "$0" | tail -40
            exit 0
            ;;
        *) log_error "Option inconnue: $1"; exit 1 ;;
    esac
done

echo ""
echo "========================================================"
echo " MAESTRO - Deploiement GPU sur Scaleway"
echo "========================================================"
echo ""
log_info "Configuration :"
echo "  Instance type : $INSTANCE_TYPE"
echo "  Image         : $IMAGE"
echo "  Zone          : $ZONE"
echo "  Nom           : $INSTANCE_NAME"
echo "  Volume data   : ${DATA_VOLUME_GB} Go"
echo "  Epochs        : $EPOCHS"
echo "  Batch size    : $BATCH_SIZE"
echo "  Learning rate : $LR"
echo "  Modalites     : $MODALITES"
echo "  Unfreeze      : ${UNFREEZE:-non}"
echo ""

# --- Verifier les pre-requis ---
log_info "Verification des pre-requis..."

if ! command -v scw &>/dev/null; then
    log_error "CLI Scaleway (scw) non trouvee."
    echo ""
    echo "Installation :"
    echo "  # Linux"
    echo "  curl -s https://raw.githubusercontent.com/scaleway/scaleway-cli/master/scripts/get.sh | sh"
    echo ""
    echo "  # macOS"
    echo "  brew install scw"
    echo ""
    echo "  # Puis configurer :"
    echo "  scw init"
    exit 1
fi

# Verifier que scw est configure
if ! scw account project get &>/dev/null 2>&1; then
    log_error "CLI Scaleway non configuree. Executez : scw init"
    exit 1
fi

log_ok "CLI Scaleway configuree"

# --- Etape 1 : Creer l'instance GPU ---
echo ""
log_info "=== Etape 1 : Creation de l'instance GPU ==="

CREATE_CMD="scw instance server create \
    type=$INSTANCE_TYPE \
    image=$IMAGE \
    zone=$ZONE \
    name=$INSTANCE_NAME \
    ip=new \
    additional-volumes.0=block:${DATA_VOLUME_GB}GB \
    --output json"

if $DRY_RUN; then
    log_warn "[DRY-RUN] Commande :"
    echo "  $CREATE_CMD"
    echo ""
    echo "Suite du deploiement en mode dry-run..."
    echo ""
    log_info "=== Commandes a executer manuellement ==="
    echo ""
    echo "# 1. Creer l'instance"
    echo "$CREATE_CMD"
    echo ""
    echo "# 2. Attendre que l'instance soit prete"
    echo "scw instance server wait <SERVER_ID> zone=$ZONE"
    echo ""
    echo "# 3. Recuperer l'IP"
    echo "IP=\$(scw instance server get <SERVER_ID> zone=$ZONE -o json | jq -r '.public_ip.address')"
    echo ""
    echo "# 4. Copier et lancer le script d'entrainement"
    echo "scp inst/scripts/cloud_train.sh root@\$IP:~/"
    echo "ssh root@\$IP 'EPOCHS=$EPOCHS BATCH_SIZE=$BATCH_SIZE bash ~/cloud_train.sh'"
    echo ""
    echo "# 5. Recuperer le modele"
    echo "scp root@\$IP:~/maestro_nemeton/outputs/training/maestro_treesatai_best.pt ."
    echo ""
    echo "# 6. Supprimer l'instance"
    echo "scw instance server terminate <SERVER_ID> zone=$ZONE with-ip=true"
    exit 0
fi

# Verifier si une instance avec le meme nom existe deja
log_info "Verification des instances existantes..."
EXISTING_JSON=$(scw instance server list zone="$ZONE" name="$INSTANCE_NAME" -o json 2>/dev/null || echo "[]")
EXISTING_COUNT=$(echo "$EXISTING_JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")

if [ "$EXISTING_COUNT" -gt 0 ]; then
    EXISTING_ID=$(echo "$EXISTING_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")
    EXISTING_STATE=$(echo "$EXISTING_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['state'])")
    log_warn "Instance '$INSTANCE_NAME' deja existante: $EXISTING_ID (etat: $EXISTING_STATE)"

    if [ "$EXISTING_STATE" = "running" ]; then
        log_warn "Reutilisation de l'instance en cours d'execution."
        SERVER_ID="$EXISTING_ID"
    elif [ "$EXISTING_STATE" = "stopped" ] || [ "$EXISTING_STATE" = "stopped in place" ]; then
        log_info "Demarrage de l'instance arretee..."
        SERVER_ID="$EXISTING_ID"
        scw instance server action run "$SERVER_ID" zone="$ZONE" >/dev/null 2>&1
    elif echo "$EXISTING_STATE" | grep -qE "stopping|locked"; then
        log_info "Instance en cours de suppression, attente..."
        WAIT_MAX=120
        WAIT_ELAPSED=0
        while [ "$WAIT_ELAPSED" -lt "$WAIT_MAX" ]; do
            sleep 10
            WAIT_ELAPSED=$((WAIT_ELAPSED + 10))
            CHECK_JSON=$(scw instance server list zone="$ZONE" name="$INSTANCE_NAME" -o json 2>/dev/null || echo "[]")
            CHECK_COUNT=$(echo "$CHECK_JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")
            if [ "$CHECK_COUNT" -eq 0 ]; then
                log_ok "Instance supprimee apres ${WAIT_ELAPSED}s"
                EXISTING_COUNT=0
                break
            fi
            log_info "  Attente... (${WAIT_ELAPSED}s/${WAIT_MAX}s)"
        done
        if [ "$EXISTING_COUNT" -gt 0 ]; then
            log_error "Instance toujours presente apres ${WAIT_MAX}s"
            log_info "Supprimez-la manuellement : scw instance server terminate $EXISTING_ID zone=$ZONE with-ip=true"
            exit 1
        fi
    else
        log_error "Instance dans un etat inattendu : $EXISTING_STATE"
        log_info "Supprimez-la manuellement : scw instance server terminate $EXISTING_ID zone=$ZONE with-ip=true"
        exit 1
    fi
fi

# Creer une nouvelle instance si aucune existante reutilisable
if [ -z "${SERVER_ID:-}" ]; then
    log_info "Creation de l'instance $INSTANCE_TYPE..."
    SERVER_JSON=$(eval "$CREATE_CMD")
    SERVER_ID=$(echo "$SERVER_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
    log_ok "Instance creee: $SERVER_ID"
fi

# --- Etape 2 : Attendre que l'instance soit prete ---
echo ""
log_info "=== Etape 2 : Demarrage de l'instance ==="
log_info "Attente du demarrage (peut prendre 2-5 minutes)..."

scw instance server wait "$SERVER_ID" zone="$ZONE" timeout=600s

# Recuperer l'IP publique
SERVER_INFO=$(scw instance server get "$SERVER_ID" zone="$ZONE" -o json)
PUBLIC_IP=$(echo "$SERVER_INFO" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if 'public_ip' in data and data['public_ip']:
    print(data['public_ip']['address'])
elif 'public_ips' in data and data['public_ips']:
    print(data['public_ips'][0]['address'])
else:
    sys.exit('Aucune IP publique trouvee')
")
log_ok "Instance prete: $PUBLIC_IP"

# --- Etape 3 : Attendre que SSH soit disponible ---
echo ""
log_info "=== Etape 3 : Connexion SSH ==="

# Nettoyer les anciennes cles SSH pour cette IP
ssh-keygen -R "$PUBLIC_IP" &>/dev/null 2>&1 || true
log_info "Nettoyage des anciennes cles SSH pour $PUBLIC_IP..."

# Les instances GPU Scaleway peuvent mettre 5-10 min pour initialiser SSH
# (drivers NVIDIA, cloud-init, configuration reseau)
SSH_TIMEOUT=600
SSH_INTERVAL=15
SSH_ELAPSED=0

log_info "Attente du serveur SSH (timeout: ${SSH_TIMEOUT}s)..."

while [ "$SSH_ELAPSED" -lt "$SSH_TIMEOUT" ]; do
    if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o BatchMode=yes "root@$PUBLIC_IP" "echo ok" &>/dev/null; then
        log_ok "SSH disponible apres ${SSH_ELAPSED}s"
        break
    fi
    SSH_ELAPSED=$((SSH_ELAPSED + SSH_INTERVAL))
    if [ "$SSH_ELAPSED" -ge "$SSH_TIMEOUT" ]; then
        log_error "Timeout SSH apres ${SSH_TIMEOUT}s"
        log_info "L'instance est peut-etre encore en cours de demarrage."
        log_info "Essayez manuellement : ssh root@$PUBLIC_IP"
        log_info "Pour supprimer : scw instance server terminate $SERVER_ID zone=$ZONE with-ip=true"
        exit 1
    fi
    log_info "  Toujours en attente du SSH... (${SSH_ELAPSED}s/${SSH_TIMEOUT}s)"
    sleep "$SSH_INTERVAL"
done

# --- Etape 3b : Monter le volume data ---
echo ""
log_info "=== Etape 3b : Montage du volume data ==="

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

log_info "Formatage et montage du volume data sur /data..."
scp -o StrictHostKeyChecking=no "$REPO_ROOT/inst/scripts/mount_data.sh" "root@$PUBLIC_IP:~/"
ssh -o StrictHostKeyChecking=no "root@$PUBLIC_IP" "bash ~/mount_data.sh"
log_ok "Volume data monte sur /data"

# --- Etape 4 : Deployer et lancer l'entrainement ---
echo ""
log_info "=== Etape 4 : Deploiement de l'entrainement ==="

log_info "Envoi du script d'entrainement..."
scp -o StrictHostKeyChecking=no "$REPO_ROOT/inst/scripts/cloud_train.sh" "root@$PUBLIC_IP:~/"

# Lancer l'entrainement dans tmux (persistent meme si SSH deconnecte)
log_info "Lancement de l'entrainement dans tmux..."
ssh -o StrictHostKeyChecking=no "root@$PUBLIC_IP" bash <<REMOTE_EOF
    # Installer tmux si absent
    apt-get update -qq && apt-get install -y -qq tmux > /dev/null 2>&1
REMOTE_EOF

# Envoyer les fichiers Python locaux (corrige le code apres le clone)
log_info "Envoi des fichiers Python locaux..."
ssh -o StrictHostKeyChecking=no "root@$PUBLIC_IP" "mkdir -p /root/local_python"
scp -o StrictHostKeyChecking=no "$REPO_ROOT/inst/legacy/train_treesatai.py" "root@$PUBLIC_IP:/root/local_python/"
scp -o StrictHostKeyChecking=no "$REPO_ROOT/inst/python/maestro_inference.py" "root@$PUBLIC_IP:/root/local_python/"

# Creer le script wrapper
log_info "Creation du script d'entrainement..."
ssh -o StrictHostKeyChecking=no "root@$PUBLIC_IP" bash <<REMOTE_EOF
    cat > /root/run_train.sh <<TRAIN_EOF
#!/bin/bash
export EPOCHS=$EPOCHS
export BATCH_SIZE=$BATCH_SIZE
export VENV_DIR=/data/venv_maestro
export DATA_DIR=/data/treesatai
export OUTPUT_DIR=/data/outputs/training
export HF_HOME=/data/hf_cache
bash ~/cloud_train.sh 2>&1 | tee ~/train.log.setup
# Appliquer les fichiers Python locaux par-dessus le clone
cp -v /root/local_python/maestro_inference.py /root/maestro_nemeton/inst/python/ 2>/dev/null
cp -v /root/local_python/train_treesatai.py /root/maestro_nemeton/inst/legacy/ 2>/dev/null
# Relancer seulement l'entrainement (deps + data deja prets)
cd /root/maestro_nemeton
CKPT=\$(find /data/.cache/huggingface -name "pretrain-epoch=99.ckpt" 2>/dev/null | head -1)
HF_HOME=/data/hf_cache /data/venv_maestro/bin/python inst/legacy/train_treesatai.py \
    --checkpoint "\$CKPT" \
    --data-dir /data/treesatai \
    --output-dir /data/outputs/training \
    --modalites aerial \
    --epochs \$EPOCHS \
    --batch-size \$BATCH_SIZE \
    --lr 1e-3 \
    --gpu \
    --workers 4 2>&1 | tee ~/train.log
echo ""
echo "========================================="
echo " ENTRAINEMENT TERMINE"
echo " Modele: /data/outputs/training/maestro_treesatai_best.pt"
echo "========================================="
TRAIN_EOF
    chmod +x /root/run_train.sh

    # Lancer dans tmux
    tmux new-session -d -s maestro "bash /root/run_train.sh"
REMOTE_EOF

log_ok "Entrainement lance en arriere-plan (tmux session: maestro)"

# --- Etape 5 : Instructions de suivi ---
echo ""
echo "========================================================"
echo -e " ${GREEN}Deploiement reussi !${NC}"
echo "========================================================"
echo ""
echo "  Instance  : $INSTANCE_NAME ($INSTANCE_TYPE)"
echo "  Server ID : $SERVER_ID"
echo "  IP        : $PUBLIC_IP"
echo "  Zone      : $ZONE"
echo ""
echo "--- Commandes utiles ---"
echo ""
echo "  # Suivre l'entrainement en temps reel :"
echo "  ssh -t root@$PUBLIC_IP 'tmux attach -t maestro'"
echo ""
echo "  # Voir les logs :"
echo "  ssh root@$PUBLIC_IP 'tail -f ~/train.log'"
echo ""
echo "  # Verifier la GPU :"
echo "  ssh root@$PUBLIC_IP 'nvidia-smi'"
echo ""
echo "  # Recuperer le modele entraine :"
echo "  scp root@$PUBLIC_IP:/data/outputs/training/maestro_treesatai_best.pt ."
echo ""
echo "  # Predire sur votre AOI (apres recuperation du modele) :"
echo "  Rscript inst/scripts/predict_from_checkpoint.R \\"
echo "      --aoi data/aoi.gpkg \\"
echo "      --checkpoint maestro_treesatai_best.pt \\"
echo "      --output outputs/"
echo ""
echo "  # IMPORTANT : Supprimer l'instance apres recuperation du modele !"
echo "  scw instance server terminate $SERVER_ID zone=$ZONE with-ip=true"
echo ""

# Sauvegarder les infos de l'instance pour les scripts de recuperation
INFO_FILE="$REPO_ROOT/.scaleway_instance"
cat > "$INFO_FILE" <<INFOEOF
# Instance Scaleway creee le $(date -Iseconds)
SERVER_ID=$SERVER_ID
PUBLIC_IP=$PUBLIC_IP
ZONE=$ZONE
INSTANCE_NAME=$INSTANCE_NAME
INSTANCE_TYPE=$INSTANCE_TYPE
INFOEOF
log_info "Infos instance sauvegardees dans .scaleway_instance"
