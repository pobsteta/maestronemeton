#!/bin/bash
# =============================================================================
# deploy_scaleway.sh
# Deploie le fine-tuning MAESTRO sur PureForest (13 classes) sur une instance
# GPU Scaleway. Cible `cloud_train_pureforest.sh` (P1 + P2 du DEV_PLAN).
#
# Ce script est execute DEPUIS VOTRE MACHINE LOCALE. Il :
#   1. Cree une instance GPU Scaleway (via CLI scw)
#   2. Monte le volume data sur /data
#   3. Envoie cloud_train_pureforest.sh, le lance dans tmux avec les env
#      vars adaptees (BRANCH, MODALITIES, PROBE_EPOCHS, ...)
#   4. Donne les commandes pour suivre et recuperer le modele
#
# Le script distant est self-contained : il clone la branche choisie,
# installe les deps Python pinnees (TR-03), pre-traite PureForest aerial
# + dem (si MODALITIES contient dem), et lance pureforest_finetune.py.
#
# Pre-requis :
#   - CLI Scaleway installee et configuree (scw init)
#   - Cle SSH configuree dans Scaleway
#   - Projet/organisation Scaleway active
#   - Le code a deployer doit etre **pousse sur le remote** (la branche
#     est clonee depuis github.com/pobsteta/maestronemeton)
#
# Usage :
#   bash inst/scripts/deploy_scaleway.sh [OPTIONS]
#
# Options :
#   --instance-type TYPE   Type d'instance GPU (defaut: L4-1-24G)
#   --image IMAGE          Image OS (defaut: ubuntu_jammy_gpu_os_12)
#   --zone ZONE            Zone Scaleway (defaut: fr-par-2)
#   --branch NAME          Branche git a cloner (defaut: branche locale courante)
#   --modalities MODS      Modalites virgule-separees (defaut: aerial)
#                          Ex: aerial,dem (active prepare_pureforest_dem.py)
#   --probe-epochs N       Epochs linear probe (defaut: 10)
#   --finetune-epochs N    Epochs fine-tune complet (defaut: 50)
#   --batch-size N         Taille batch (defaut: 16 sur L4 fp32 / aerial+dem,
#                          monter a 24-32 avec --no-amp inactif sur L4, 64+ sur H100)
#   --patience N           Early stopping patience (defaut: 5)
#   --resume PATH          Chemin LOCAL d'un checkpoint .pt a uploader sur
#                          l'instance et a charger avant l'entrainement.
#                          Combine avec --skip-probe pour reprendre apres
#                          un crash en phase B (economise ~50h GPU).
#   --skip-probe           Sauter la phase A (linear probe). Utile avec
#                          --resume.
#   --no-amp               Desactive le mixed precision bf16 (active par
#                          defaut, speedup 1.5-2x). A utiliser si NaN observes.
#   --hf-token TOKEN       Token HuggingFace (override). Par defaut, lit
#                          .Renviron du projet (HUGGING_FACE_HUB_TOKEN,
#                          HUGGINGFACE_HUB_TOKEN ou HF_TOKEN), puis $HF_TOKEN
#                          de l'environnement. Sans token, requetes HF
#                          anonymes -> rate-limit ~1000 req/h, downloads
#                          plus lents et warning HF affiche.
#   --notify-email EMAIL   Email pour notifications debut/fin (necessite un MTA
#                          local sur l'instance, generalement absent : preferer
#                          le webhook ntfy ci-dessous).
#   --notify-webhook URL   URL webhook complete (override). Defaut construit
#                          depuis --ntfy-topic.
#   --ntfy-topic NAME      Topic ntfy.sh (defaut: maestro-train). L'URL
#                          finale devient https://ntfy.sh/NAME. Topic public,
#                          choisir un nom non-trivial pour eviter l'ecoute.
#   --name NAME            Nom de l'instance (defaut: maestro-train)
#   --data-volume GB       Volume data en Go (defaut: 500, dimensionne pour
#                          le pic disque aerial+dem : ~150 Go patches aerial
#                          (LZW) + ~120 Go cache HF dem en pointe + DEM
#                          patches + tmp xet + checkpoint + marges)
#   --dry-run              Afficher les commandes sans executer
#
# Instances GPU Scaleway recommandees :
#   GPU-3070-S   : RTX 3070 (8 Go VRAM)  - ~0.76 EUR/h - aerial seul, batch 16
#   L4-1-24G     : NVIDIA L4 (24 Go VRAM) - ~0.92 EUR/h - aerial+dem, batch 24
#   H100-1-80G   : H100 (80 Go VRAM)     - ~3.50 EUR/h - entrainement rapide
#
# Cout estime pour le run complet aerial+dem (probe 10 + finetune 50) :
#   L4-1-24G   : ~14-18h -> ~13-17 EUR (incluant ~1h de pre-traitement)
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
DATA_VOLUME_GB=500
# Branche par defaut : la branche locale courante. Permet `bash deploy_scaleway.sh`
# directement depuis n'importe quelle branche de travail sans avoir a la nommer.
DEFAULT_BRANCH=$(git -C "$(dirname "$0")/../.." rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)
BRANCH="$DEFAULT_BRANCH"
MODALITIES="aerial"
PROBE_EPOCHS=10
FINETUNE_EPOCHS=50
BATCH_SIZE=16
PATIENCE=5
RESUME=""
SKIP_PROBE=""
USE_AMP="1"
HF_TOKEN_OVERRIDE=""
NOTIFY_EMAIL=""
# Topic ntfy.sh par defaut. Public, donc devinable : on peut l'override avec
# --ntfy-topic ou en passant directement --notify-webhook une URL custom.
NTFY_TOPIC="maestro-train"
NOTIFY_WEBHOOK=""
DRY_RUN=false

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case $1 in
        --instance-type)   INSTANCE_TYPE="$2"; shift 2 ;;
        --image)           IMAGE="$2"; shift 2 ;;
        --zone)            ZONE="$2"; shift 2 ;;
        --branch)          BRANCH="$2"; shift 2 ;;
        --modalities|--modalites) MODALITIES="$2"; shift 2 ;;
        --probe-epochs)    PROBE_EPOCHS="$2"; shift 2 ;;
        --finetune-epochs) FINETUNE_EPOCHS="$2"; shift 2 ;;
        --batch-size)      BATCH_SIZE="$2"; shift 2 ;;
        --resume)          RESUME="$2"; shift 2 ;;
        --skip-probe)      SKIP_PROBE=1; shift ;;
        --no-amp)          USE_AMP=""; shift ;;
        --hf-token)        HF_TOKEN_OVERRIDE="$2"; shift 2 ;;
        --patience)        PATIENCE="$2"; shift 2 ;;
        --notify-email)    NOTIFY_EMAIL="$2"; shift 2 ;;
        --notify-webhook)  NOTIFY_WEBHOOK="$2"; shift 2 ;;
        --ntfy-topic)      NTFY_TOPIC="$2"; shift 2 ;;
        --name)            INSTANCE_NAME="$2"; shift 2 ;;
        --data-volume)     DATA_VOLUME_GB="$2"; shift 2 ;;
        --dry-run)         DRY_RUN=true; shift ;;
        -h|--help)
            head -55 "$0" | tail -50
            exit 0
            ;;
        *) log_error "Option inconnue: $1"; exit 1 ;;
    esac
done

# --- Resolution du webhook ntfy ---
# Si --notify-webhook n'a pas ete passe explicitement, on construit l'URL
# ntfy.sh a partir de NTFY_TOPIC. Pour desactiver toute notif webhook,
# passer --notify-webhook "".
if [ -z "$NOTIFY_WEBHOOK" ] && [ -n "$NTFY_TOPIC" ]; then
    NOTIFY_WEBHOOK="https://ntfy.sh/${NTFY_TOPIC}"
fi

# --- Resolution du token HuggingFace ---
# Priorite : --hf-token > $HF_TOKEN env > .Renviron du projet
# (HUGGING_FACE_HUB_TOKEN, HUGGINGFACE_HUB_TOKEN ou HF_TOKEN).
# Le token est propage en HF_TOKEN (nom canonique lu par huggingface_hub)
# sur l'instance distante. .Renviron est ignore par git, safe a lire.
DEPLOY_REPO_ROOT="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)"
HF_TOKEN_FINAL=""
if [ -n "$HF_TOKEN_OVERRIDE" ]; then
    HF_TOKEN_FINAL="$HF_TOKEN_OVERRIDE"
elif [ -n "${HF_TOKEN:-}" ]; then
    HF_TOKEN_FINAL="$HF_TOKEN"
else
    for RENV_CANDIDATE in "$DEPLOY_REPO_ROOT/.Renviron" ".Renviron"; do
        [ ! -f "$RENV_CANDIDATE" ] && continue
        for VAR in HUGGING_FACE_HUB_TOKEN HUGGINGFACE_HUB_TOKEN HF_TOKEN; do
            VAL=$(grep -E "^${VAR}=" "$RENV_CANDIDATE" 2>/dev/null \
                  | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'" | tr -d '\r' \
                  | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            if [ -n "$VAL" ]; then
                HF_TOKEN_FINAL="$VAL"
                break 2
            fi
        done
    done
fi

echo ""
echo "========================================================"
echo " MAESTRO - Deploiement GPU sur Scaleway"
echo "========================================================"
echo ""
log_info "Configuration :"
echo "  Instance type   : $INSTANCE_TYPE"
echo "  Image           : $IMAGE"
echo "  Zone            : $ZONE"
echo "  Nom             : $INSTANCE_NAME"
echo "  Volume data     : ${DATA_VOLUME_GB} Go"
echo "  Branche git     : $BRANCH"
echo "  Modalites       : $MODALITIES"
echo "  Probe epochs    : $PROBE_EPOCHS"
echo "  Fine-tune epochs: $FINETUNE_EPOCHS"
echo "  Batch size      : $BATCH_SIZE"
echo "  Patience        : $PATIENCE"
[ -n "$RESUME" ]         && echo "  Resume          : $RESUME"
[ -n "$SKIP_PROBE" ]     && echo "  Skip probe      : oui"
[ "$USE_AMP" = "1" ]     && echo "  AMP (bf16)      : actif" || echo "  AMP (bf16)      : desactive"
[ -n "$HF_TOKEN_FINAL" ] && echo "  HF token        : (defini, $(echo $HF_TOKEN_FINAL | wc -c) car)" || echo "  HF token        : (absent — rate-limite anonyme)"
[ -n "$NOTIFY_EMAIL" ]   && echo "  Notify email    : $NOTIFY_EMAIL"
[ -n "$NOTIFY_WEBHOOK" ] && echo "  Notify webhook  : $NOTIFY_WEBHOOK"
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
    echo "# 4. Monter le volume data sur /data"
    echo "scp inst/scripts/mount_data.sh root@\$IP:~/"
    echo "ssh root@\$IP 'bash ~/mount_data.sh'"
    echo ""
    echo "# 5. Copier et lancer le script d'entrainement (cloud_train_pureforest.sh)"
    echo "scp inst/scripts/cloud_train_pureforest.sh root@\$IP:~/"
    echo "ssh root@\$IP 'BRANCH=$BRANCH MODALITIES=$MODALITIES \\"
    echo "    PROBE_EPOCHS=$PROBE_EPOCHS FINETUNE_EPOCHS=$FINETUNE_EPOCHS \\"
    echo "    BATCH_SIZE=$BATCH_SIZE PATIENCE=$PATIENCE \\"
    echo "    bash ~/cloud_train_pureforest.sh'"
    echo ""
    echo "# 6. Recuperer le modele"
    echo "scp root@\$IP:/data/outputs/training/maestro_pureforest_best.pt ."
    echo ""
    echo "# 7. Supprimer l'instance"
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
log_info "=== Etape 4 : Deploiement de cloud_train_pureforest.sh ==="

log_info "Envoi du script d'entrainement PureForest..."
scp -o StrictHostKeyChecking=no \
    "$REPO_ROOT/inst/scripts/cloud_train_pureforest.sh" \
    "root@$PUBLIC_IP:~/"

# Si --resume est passe : envoyer le checkpoint sur l'instance et reecrire
# RESUME pour pointer le chemin distant. La taille typique est 500-600 Mo
# (modele MAESTRO base 13 classes), comptez 1-3 min de transfer.
if [ -n "$RESUME" ]; then
    if [ ! -f "$RESUME" ]; then
        log_error "--resume : fichier introuvable : $RESUME"
        exit 1
    fi
    REMOTE_RESUME="/data/resume_checkpoint.pt"
    log_info "Envoi du checkpoint resume ($(du -h "$RESUME" | cut -f1)) -> $REMOTE_RESUME"
    scp -o StrictHostKeyChecking=no "$RESUME" "root@$PUBLIC_IP:$REMOTE_RESUME"
    RESUME="$REMOTE_RESUME"
    log_ok "Checkpoint envoye"
fi

# Installer tmux pour la persistance, puis lancer le pipeline complet
# (clone branche -> pip install pinne -> prepare aerial[+dem] -> finetune).
log_info "Installation tmux + lancement de l'entrainement..."
ssh -o StrictHostKeyChecking=no "root@$PUBLIC_IP" bash <<REMOTE_EOF
    set -e
    apt-get update -qq && apt-get install -y -qq tmux > /dev/null 2>&1

    cat > /root/run_train.sh <<'TRAIN_EOF'
#!/bin/bash
export BRANCH="${BRANCH}"
export MODALITIES="${MODALITIES}"
export PROBE_EPOCHS="${PROBE_EPOCHS}"
export FINETUNE_EPOCHS="${FINETUNE_EPOCHS}"
export BATCH_SIZE="${BATCH_SIZE}"
export PATIENCE="${PATIENCE}"
export NOTIFY_EMAIL="${NOTIFY_EMAIL}"
export NOTIFY_WEBHOOK="${NOTIFY_WEBHOOK}"
export RESUME="${RESUME}"
export SKIP_PROBE="${SKIP_PROBE}"
export USE_AMP="${USE_AMP}"
export HF_TOKEN="${HF_TOKEN_FINAL}"
bash /root/cloud_train_pureforest.sh 2>&1 | tee /root/train.log
TRAIN_EOF
    chmod +x /root/run_train.sh

    # Lancer dans tmux (persistant meme si SSH deconnecte)
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
echo "  # Recuperer le modele entraine + le rapport :"
echo "  scp root@$PUBLIC_IP:/data/outputs/training/maestro_pureforest_best.pt ."
echo "  scp root@$PUBLIC_IP:/data/outputs/training/maestro_pureforest_best.report.json ."
echo ""
echo "  # Predire sur votre AOI (apres recuperation du modele) :"
echo "  Rscript inst/scripts/predict_from_checkpoint.R \\"
echo "      --aoi data/aoi.gpkg \\"
echo "      --checkpoint maestro_pureforest_best.pt \\"
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
