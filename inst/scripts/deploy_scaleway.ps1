# =============================================================================
# deploy_scaleway.ps1
# Deploie le fine-tuning MAESTRO sur PureForest (13 classes) sur une instance
# GPU Scaleway depuis Windows. Cible cloud_train_pureforest.sh (P1 + P2).
#
# Ce script est execute DEPUIS VOTRE PC WINDOWS. Il :
#   1. Cree une instance GPU Scaleway (via CLI scw)
#   2. Monte le volume data sur /data
#   3. Envoie cloud_train_pureforest.sh, le lance dans tmux avec les
#      env vars adaptees (BRANCH, MODALITIES, PROBE_EPOCHS, ...)
#   4. Donne les commandes pour suivre et recuperer le modele
#
# Le script distant est self-contained : il clone la branche choisie,
# installe les deps Python pinnees (TR-03), pre-traite PureForest aerial
# + dem (si MODALITIES contient dem), et lance pureforest_finetune.py.
#
# Pre-requis :
#   - CLI Scaleway installee (scw init)
#   - Client SSH (OpenSSH integre a Windows 10+)
#   - Git installe (pour detecter la branche locale courante)
#   - Le code a deployer doit etre **pousse sur le remote**
#
# Usage :
#   .\inst\scripts\deploy_scaleway.ps1
#   .\inst\scripts\deploy_scaleway.ps1 -Modalities "aerial,dem"
#   .\inst\scripts\deploy_scaleway.ps1 -InstanceType L4-1-24G -ProbeEpochs 5 -FinetuneEpochs 30
#   .\inst\scripts\deploy_scaleway.ps1 -NotifyEmail mon@email.fr
#   .\inst\scripts\deploy_scaleway.ps1 -NotifyWebhook https://ntfy.sh/maestro-train
#   .\inst\scripts\deploy_scaleway.ps1 -DryRun
#
# Instances GPU Scaleway recommandees :
#   GPU-3070-S : RTX 3070 (8 Go VRAM)   - aerial seul, batch 16
#   L4-1-24G   : NVIDIA L4 (24 Go VRAM) - aerial+dem, batch 24
#   H100-1-80G : H100 (80 Go VRAM)      - entrainement rapide
#
# Cout estime aerial+dem (probe 10 + finetune 50, L4-1-24G) : ~14-18h, 13-17 EUR
# =============================================================================

[CmdletBinding()]
param(
    [string]$InstanceType = "L4-1-24G",
    [string]$Image = "ubuntu_jammy_gpu_os_12",
    [string]$Zone = "fr-par-2",
    [string]$InstanceName = "maestro-train",
    [string]$Branch = "",
    [string]$Modalities = "aerial",
    [int]$ProbeEpochs = 10,
    [int]$FinetuneEpochs = 50,
    [int]$BatchSize = 24,
    [int]$Patience = 5,
    [int]$DataVolumeGB = 500,
    [string]$NotifyEmail = "",
    [string]$NotifyWebhook = "",
    [string]$NtfyTopic = "maestro-train",
    [switch]$DryRun
)

# Resolution du webhook ntfy : si NotifyWebhook non passe, construire depuis NtfyTopic.
if (-not $NotifyWebhook -and $NtfyTopic) {
    $NotifyWebhook = "https://ntfy.sh/$NtfyTopic"
}

# Detection automatique de la branche locale courante si non fournie.
if (-not $Branch) {
    try {
        $Branch = (git rev-parse --abbrev-ref HEAD 2>$null).Trim()
        if (-not $Branch) { $Branch = "main" }
    } catch {
        $Branch = "main"
    }
}

$ErrorActionPreference = "Stop"

# --- Couleurs ---
function Log-Info  { param($msg) Write-Host "[INFO] $msg" -ForegroundColor Blue }
function Log-Ok    { param($msg) Write-Host "[OK] $msg" -ForegroundColor Green }
function Log-Warn  { param($msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Log-Error { param($msg) Write-Host "[ERREUR] $msg" -ForegroundColor Red }

Write-Host ""
Write-Host "========================================================"
Write-Host " MAESTRO - Deploiement GPU sur Scaleway (Windows)"
Write-Host "========================================================"
Write-Host ""
Log-Info "Configuration :"
Write-Host "  Instance type   : $InstanceType"
Write-Host "  Image           : $Image"
Write-Host "  Zone            : $Zone"
Write-Host "  Nom             : $InstanceName"
Write-Host "  Volume data     : ${DataVolumeGB} Go"
Write-Host "  Branche git     : $Branch"
Write-Host "  Modalites       : $Modalities"
Write-Host "  Probe epochs    : $ProbeEpochs"
Write-Host "  Fine-tune epochs: $FinetuneEpochs"
Write-Host "  Batch size      : $BatchSize"
Write-Host "  Patience        : $Patience"
if ($NotifyEmail -ne "")   { Write-Host "  Notify email    : $NotifyEmail" }
if ($NotifyWebhook -ne "") { Write-Host "  Notify webhook  : $NotifyWebhook" }
Write-Host ""

# --- Verifier les pre-requis ---
Log-Info "Verification des pre-requis..."

# Verifier scw
if (-not (Get-Command scw -ErrorAction SilentlyContinue)) {
    Log-Error "CLI Scaleway (scw) non trouvee."
    Write-Host ""
    Write-Host "Installation :"
    Write-Host "  # Via winget"
    Write-Host "  winget install scaleway-cli"
    Write-Host ""
    Write-Host "  # Ou via scoop"
    Write-Host "  scoop bucket add scaleway https://github.com/scaleway/scoop-scaleway"
    Write-Host "  scoop install scaleway-cli"
    Write-Host ""
    Write-Host "  # Puis configurer :"
    Write-Host "  scw init"
    exit 1
}

# Verifier SSH
if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    Log-Error "Client SSH non trouve."
    Write-Host ""
    Write-Host "OpenSSH est integre a Windows 10+."
    Write-Host "Activez-le dans : Parametres > Applications > Fonctionnalites facultatives > Client OpenSSH"
    exit 1
}

# Verifier que scw est configure
$scwOutput = scw info 2>&1
if ($LASTEXITCODE -ne 0) {
    Log-Error "CLI Scaleway non configuree. Executez : scw init"
    exit 1
}
Log-Ok "CLI Scaleway configuree"

# --- Mode dry-run ---
if ($DryRun) {
    Write-Host ""
    Log-Warn "[DRY-RUN] Commandes qui seraient executees :"
    Write-Host ""
    Write-Host "# 1. Creer l'instance"
    Write-Host "scw instance server create type=$InstanceType image=$Image zone=$Zone name=$InstanceName ip=new additional-volumes.0=block:${DataVolumeGB}GB -o json"
    Write-Host ""
    Write-Host "# 2. Attendre que l'instance soit prete"
    Write-Host "scw instance server wait <SERVER_ID> zone=$Zone"
    Write-Host ""
    Write-Host "# 3. Recuperer l'IP"
    Write-Host "scw instance server get <SERVER_ID> zone=$Zone -o json"
    Write-Host ""
    Write-Host "# 4. Monter le volume data sur /data"
    Write-Host "scp inst\scripts\mount_data.sh root@<IP>:~/"
    Write-Host "ssh root@<IP> 'bash ~/mount_data.sh'"
    Write-Host ""
    Write-Host "# 5. Copier et lancer le script d'entrainement (cloud_train_pureforest.sh)"
    Write-Host "scp inst\scripts\cloud_train_pureforest.sh root@<IP>:~/"
    Write-Host "ssh root@<IP> 'BRANCH=$Branch MODALITIES=$Modalities ``"
    Write-Host "    PROBE_EPOCHS=$ProbeEpochs FINETUNE_EPOCHS=$FinetuneEpochs ``"
    Write-Host "    BATCH_SIZE=$BatchSize PATIENCE=$Patience ``"
    Write-Host "    bash ~/cloud_train_pureforest.sh'"
    Write-Host ""
    Write-Host "# 6. Recuperer le modele"
    Write-Host "scp root@<IP>:/data/outputs/training/maestro_pureforest_best.pt ."
    Write-Host ""
    Write-Host "# 7. Supprimer l'instance"
    Write-Host "scw instance server terminate <SERVER_ID> zone=$Zone with-ip=true"
    exit 0
}

# --- Etape 1 : Verifier les instances existantes et creer ---
Write-Host ""
Log-Info "=== Etape 1 : Creation de l'instance GPU ==="

# Verifier si une instance avec le meme nom existe deja
Log-Info "Verification des instances existantes..."
$existingRaw = scw instance server list zone=$Zone name=$InstanceName -o json 2>&1
$existingServers = $null
try {
    $existingServers = $existingRaw | ConvertFrom-Json
} catch { }

if ($existingServers -and $existingServers.Count -gt 0) {
    $existing = $existingServers[0]
    Log-Warn "Instance '$InstanceName' deja existante : $($existing.id) (etat: $($existing.state))"

    # Si l'instance est en cours de suppression, attendre qu'elle disparaisse
    if ($existing.state -match "stopping|stopped_in_place|locked") {
        Log-Info "Instance en cours de suppression, attente..."
        $waitMax = 120
        $waitElapsed = 0
        while ($waitElapsed -lt $waitMax) {
            Start-Sleep -Seconds 10
            $waitElapsed += 10
            $checkRaw = scw instance server list zone=$Zone name=$InstanceName -o json 2>&1
            $checkServers = $null
            try { $checkServers = $checkRaw | ConvertFrom-Json } catch { }
            if (-not $checkServers -or $checkServers.Count -eq 0) {
                Log-Ok "Instance supprimee apres ${waitElapsed}s"
                break
            }
            Log-Info "  Attente... (${waitElapsed}s / ${waitMax}s, etat: $($checkServers[0].state))"
        }
        # Re-verifier
        $existingRaw = scw instance server list zone=$Zone name=$InstanceName -o json 2>&1
        $existingServers = $null
        try { $existingServers = $existingRaw | ConvertFrom-Json } catch { }
    }
}

if ($existingServers -and $existingServers.Count -gt 0) {
    $existing = $existingServers[0]

    if ($existing.state -eq "running") {
        Log-Warn "Reutilisation de l'instance en cours d'execution."
        $ServerId = $existing.id
    } elseif ($existing.state -eq "stopped") {
        Log-Info "Demarrage de l'instance arretee..."
        $ServerId = $existing.id
        scw instance server action run $ServerId zone=$Zone 2>&1 | Out-Null
    } else {
        Log-Error "Instance dans un etat inattendu : $($existing.state)"
        Log-Info "Supprimez-la manuellement : scw instance server terminate $($existing.id) zone=$Zone with-ip=true"
        exit 1
    }
} else {
    Log-Info "Creation de l'instance $InstanceType avec volume data ${DataVolumeGB}Go..."
    $rawJson = scw instance server create `
        type=$InstanceType `
        image=$Image `
        zone=$Zone `
        name=$InstanceName `
        ip=new `
        additional-volumes.0=block:${DataVolumeGB}GB `
        -o json 2>&1

    # Verifier si la creation a echoue
    $ServerJson = $null
    try {
        $ServerJson = $rawJson | ConvertFrom-Json
    } catch {
        Log-Error "Echec de la creation de l'instance :"
        Write-Host $rawJson
        Write-Host ""
        Log-Info "Verifiez vos quotas : une instance du meme type existe peut-etre deja."
        Log-Info "  scw instance server list zone=$Zone"
        Log-Info "Listez les types GPU disponibles avec :"
        Write-Host "  scw instance server-type list zone=$Zone"
        exit 1
    }

    if ($ServerJson.error -or -not $ServerJson.id) {
        Log-Error "Echec de la creation de l'instance :"
        Write-Host $rawJson
        Write-Host ""
        Log-Info "Verifiez vos quotas : une instance du meme type existe peut-etre deja."
        Log-Info "  scw instance server list zone=$Zone"
        Log-Info "Listez les types GPU disponibles avec :"
        Write-Host "  scw instance server-type list zone=$Zone"
        exit 1
    }

    $ServerId = $ServerJson.id
    Log-Ok "Instance creee: $ServerId"
}

# --- Etape 2 : Attendre que l'instance soit prete ---
Write-Host ""
Log-Info "=== Etape 2 : Demarrage de l'instance ==="
Log-Info "Attente du demarrage (peut prendre 2-5 minutes)..."

scw instance server wait $ServerId zone=$Zone timeout=600s

# Recuperer l'IP publique
$ServerInfo = scw instance server get $ServerId zone=$Zone -o json | ConvertFrom-Json

# Extraire l'IP publique (gerer les differents formats de reponse)
$PublicIP = $null
if ($ServerInfo.public_ip -and $ServerInfo.public_ip.address) {
    $PublicIP = $ServerInfo.public_ip.address
} elseif ($ServerInfo.public_ips -and $ServerInfo.public_ips.Count -gt 0) {
    $PublicIP = $ServerInfo.public_ips[0].address
}

if (-not $PublicIP) {
    Log-Error "Impossible de recuperer l'IP publique de l'instance."
    Log-Info "Verifiez manuellement :"
    Write-Host "  scw instance server get $ServerId zone=$Zone"
    Log-Info "Pour supprimer : scw instance server terminate $ServerId zone=$Zone with-ip=true"
    exit 1
}
Log-Ok "Instance prete: $PublicIP"

# --- Etape 3 : Attendre que SSH soit disponible ---
Write-Host ""
Log-Info "=== Etape 3 : Connexion SSH ==="

# Supprimer l'ancienne cle SSH pour cette IP (evite l'erreur "host key changed")
Log-Info "Nettoyage des anciennes cles SSH pour $PublicIP..."
try {
    $sshKeygenOutput = ssh-keygen -R $PublicIP 2>&1
} catch {
    # Ignorer : l'hote n'est peut-etre pas dans known_hosts
}

# Etape 3a : Attendre que le port 22 soit ouvert (TCP)
$sshReady = $false
$sshTimeout = 600      # 10 minutes
$sshInterval = 10      # secondes entre chaque tentative
$sshElapsed = 0

Log-Info "Attente du port SSH 22 sur $PublicIP (timeout: ${sshTimeout}s)..."

while ($sshElapsed -lt $sshTimeout) {
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $connect = $tcp.BeginConnect($PublicIP, 22, $null, $null)
        $wait = $connect.AsyncWaitHandle.WaitOne(5000, $false)
        if ($wait -and $tcp.Connected) {
            $tcp.Close()
            Log-Ok "Port SSH 22 ouvert apres ${sshElapsed}s"
            $sshReady = $true
            break
        }
        $tcp.Close()
    } catch {
        # Port pas encore ouvert
    }
    $sshElapsed += $sshInterval
    if ($sshElapsed -lt $sshTimeout) {
        Log-Info "  Toujours en attente du SSH... (${sshElapsed}s/${sshTimeout}s)"
    }
    Start-Sleep -Seconds $sshInterval
}

if (-not $sshReady) {
    Log-Error "Timeout SSH apres ${sshTimeout}s - le port 22 n'a jamais repondu."
    Log-Info "Essayez manuellement : ssh root@$PublicIP"
    Log-Info "Pour supprimer : scw instance server terminate $ServerId zone=$Zone with-ip=true"
    exit 1
}

# Etape 3b : Petite pause pour laisser sshd finir son initialisation
Log-Info "Attente de 10s supplementaires pour l'initialisation de sshd..."
Start-Sleep -Seconds 10

# Etape 3c : Verifier la connexion SSH reelle
Log-Info "Test de connexion SSH..."
$sshTestOk = $false
for ($i = 1; $i -le 5; $i++) {
    try {
        # Utiliser les memes options que la connexion manuelle (qui fonctionne)
        # -o StrictHostKeyChecking=accept-new : accepter les nouvelles cles sans prompt
        $result = (ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "root@$PublicIP" "echo maestro_ready" 2>&1) | Out-String
        Log-Info "  SSH tentative $i - reponse: $($result.Trim())"
        if ($result -match "maestro_ready") {
            Log-Ok "Connexion SSH verifiee"
            $sshTestOk = $true
            break
        }
    } catch {
        Log-Info "  SSH tentative $i - exception: $_"
    }
    Log-Info "  Tentative SSH $i/5 echouee, nouvel essai dans 10s..."
    Start-Sleep -Seconds 10
}

if (-not $sshTestOk) {
    Log-Warn "Le test SSH a echoue mais le port est ouvert."
    Log-Warn "Le script continue - si l'etape 4 echoue, connectez-vous manuellement :"
    Log-Warn "  ssh root@$PublicIP"
}

# Detecter le repertoire du script (necessaire pour les etapes suivantes)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)

# --- Etape 3b : Monter le volume data ---
Write-Host ""
Log-Info "=== Etape 3b : Montage du volume data ==="
Log-Info "Formatage et montage du volume data sur /data..."
# Envoyer le script de montage (fichier separe pour eviter les problemes d'echappement PowerShell)
scp -o StrictHostKeyChecking=accept-new "$RepoRoot\inst\scripts\mount_data.sh" "root@${PublicIP}:~/"
ssh -o StrictHostKeyChecking=accept-new "root@$PublicIP" "sed -i 's/\r$//' ~/mount_data.sh && bash ~/mount_data.sh"

# --- Etape 4 : Deployer et lancer l'entrainement ---
Write-Host ""
Log-Info "=== Etape 4 : Deploiement de cloud_train_pureforest.sh ==="

# Copier le script d'entrainement (cloud_train_pureforest.sh est self-contained :
# clone branche, pip install pinne, prepare aerial[+dem], finetune)
Log-Info "Envoi du script d'entrainement PureForest..."
scp -o StrictHostKeyChecking=accept-new "$RepoRoot\inst\scripts\cloud_train_pureforest.sh" "root@${PublicIP}:~/"

# Convertir CRLF -> LF (le fichier vient de Windows ; bash plante sinon)
Log-Info "Conversion des fins de ligne CRLF -> LF..."
ssh -o StrictHostKeyChecking=accept-new "root@$PublicIP" "sed -i 's/\r$//' ~/cloud_train_pureforest.sh"

# Installer tmux + msmtp si notif email demandee
$PkgList = "tmux"
if ($NotifyEmail -ne "") {
    $PkgList = "tmux msmtp msmtp-mta"
    Log-Info "Installation de msmtp pour notification email vers $NotifyEmail"
}
Log-Info "Installation de $PkgList sur l'instance..."
ssh -o StrictHostKeyChecking=accept-new "root@$PublicIP" "apt-get update -qq && apt-get install -y -qq $PkgList > /dev/`$null 2>&1"

# Construire la commande tmux : env vars adaptees au cloud_train_pureforest.sh
Log-Info "Lancement de l'entrainement dans tmux..."
$NotifyExport = ""
if ($NotifyEmail -ne "") {
    $NotifyExport += "export NOTIFY_EMAIL=$NotifyEmail; "
}
if ($NotifyWebhook -ne "") {
    $NotifyExport += "export NOTIFY_WEBHOOK=$NotifyWebhook; "
}
$TmuxCmd = "export BRANCH=$Branch; export MODALITIES=$Modalities; export PROBE_EPOCHS=$ProbeEpochs; export FINETUNE_EPOCHS=$FinetuneEpochs; export BATCH_SIZE=$BatchSize; export PATIENCE=$Patience; ${NotifyExport}bash ~/cloud_train_pureforest.sh 2>&1 | tee ~/train.log"
ssh -o StrictHostKeyChecking=accept-new "root@$PublicIP" "tmux new-session -d -s maestro '$TmuxCmd'"

# Verifier que la session tmux existe
Start-Sleep -Seconds 2
$tmuxCheck = ssh -o StrictHostKeyChecking=accept-new "root@$PublicIP" "tmux has-session -t maestro 2>&1 && echo tmux_ok || echo tmux_fail"
if ($tmuxCheck -notmatch "tmux_ok") {
    Log-Error "La session tmux n'a pas demarre. Diagnostic :"
    ssh -o StrictHostKeyChecking=accept-new "root@$PublicIP" "which tmux; tmux list-sessions 2>&1; cat ~/train.log 2>/dev/null | head -20"
    Log-Warn "Tentative de lancement direct (sans tmux)..."
    ssh -o StrictHostKeyChecking=accept-new "root@$PublicIP" "nohup bash -c '$TmuxCmd' > ~/train.log 2>&1 &"
}

Log-Ok "Entrainement lance en arriere-plan (tmux session: maestro)"

# --- Etape 5 : Instructions de suivi ---
Write-Host ""
Write-Host "========================================================"
Write-Host " Deploiement reussi !" -ForegroundColor Green
Write-Host "========================================================"
Write-Host ""
Write-Host "  Instance  : $InstanceName ($InstanceType)"
Write-Host "  Server ID : $ServerId"
Write-Host "  IP        : $PublicIP"
Write-Host "  Zone      : $Zone"
if ($NotifyEmail -ne "") {
    Write-Host "  Email     : $NotifyEmail" -ForegroundColor Cyan
}
if ($NotifyWebhook -ne "") {
    Write-Host "  Webhook   : $NotifyWebhook" -ForegroundColor Cyan
}
Write-Host ""
Write-Host "--- Commandes utiles ---"
Write-Host ""
Write-Host "  # Verifier si l'entrainement est termine :"
Write-Host "  ssh root@$PublicIP 'grep -q ""Entrainement termine"" ~/train.log && echo TERMINE || echo EN COURS'"
Write-Host ""
Write-Host "  # Suivre l'entrainement en temps reel :"
Write-Host "  ssh -t root@$PublicIP 'tmux attach -t maestro'"
Write-Host ""
Write-Host "  # Voir les logs :"
Write-Host "  ssh root@$PublicIP 'tail -f ~/train.log'"
Write-Host ""
Write-Host "  # Voir les dernieres lignes du log :"
Write-Host "  ssh root@$PublicIP 'tail -20 ~/train.log'"
Write-Host ""
Write-Host "  # Verifier la GPU :"
Write-Host "  ssh root@$PublicIP 'nvidia-smi'"
Write-Host ""
Write-Host "  # Verifier l'espace disque :"
Write-Host "  ssh root@$PublicIP 'df -h /data'"
Write-Host ""
Write-Host "  # Recuperer le modele entraine + le rapport :"
Write-Host "  scp root@${PublicIP}:/data/outputs/training/maestro_pureforest_best.pt ."
Write-Host "  scp root@${PublicIP}:/data/outputs/training/maestro_pureforest_best.report.json ."
Write-Host ""
Write-Host "  # Ou utiliser le script de recuperation :"
Write-Host "  .\inst\scripts\recover_model.ps1"
Write-Host ""
Write-Host "  # IMPORTANT : Supprimer l'instance apres recuperation du modele !"
Write-Host "  scw instance server terminate $ServerId zone=$Zone with-ip=true"
Write-Host ""

# Sauvegarder les infos de l'instance
$InfoFile = Join-Path $RepoRoot ".scaleway_instance"
@"
# Instance Scaleway creee le $(Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
SERVER_ID=$ServerId
PUBLIC_IP=$PublicIP
ZONE=$Zone
INSTANCE_NAME=$InstanceName
INSTANCE_TYPE=$InstanceType
"@ | Out-File -FilePath $InfoFile -Encoding UTF8

Log-Info "Infos instance sauvegardees dans .scaleway_instance"
