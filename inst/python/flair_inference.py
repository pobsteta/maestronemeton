"""
flair_inference.py
Module Python d'inference pour les modeles FLAIR-HUB de l'IGNF.
Appele depuis R via reticulate.

Supporte la segmentation semantique pixel-a-pixel avec les architectures :
  - ResNet34 + UNet (FLAIR-INC)
  - ConvNeXTV2 + UPerNet (FLAIR-HUB)

Les modeles produisent des cartes de classification par patch (512x512 pixels).
"""

import torch
import torch.nn as nn
import torch.nn.functional as F
import numpy as np
from pathlib import Path


# ---------------------------------------------------------------------------
# Classes d'occupation du sol CoSIA (19 classes)
# ---------------------------------------------------------------------------

COSIA_CLASSES = [
    "Batiment",              # 1
    "Zone permeable",        # 2
    "Zone impermeable",      # 3
    "Sol nu",                # 4
    "Eau",                   # 5
    "Conifere",              # 6
    "Feuillu",               # 7
    "Broussaille / lande",   # 8
    "Vigne",                 # 9
    "Pelouse / prairie",     # 10
    "Culture",               # 11
    "Terre labouree",        # 12
    "Serre / bache",         # 13
    "Piscine",               # 14
    "Neige",                 # 15
    "Coupe forestiere",      # 16
    "Mixte conifere+feuillu",# 17
    "Ligneux",               # 18
    "Verger",                # 19
]

# Statistiques de normalisation FLAIR (valeurs brutes 0-255, dataset FLAIR)
# R, G, B, NIR, Elevation
FLAIR_MEAN = [105.08, 110.87, 101.82, 106.38, 53.26]
FLAIR_STD = [52.17, 45.38, 44.0, 39.69, 79.3]

# Remapping FLAIR-1 (19 classes, 0-indexed argmax) -> CoSIA (15 classes, 1-indexed)
# Classes FLAIR 14 (coupe), 15 (mixte), 16 (ligneux), 18 (autre) -> 0 (non classifie)
FLAIR_TO_COSIA = np.array([
    1,   # FLAIR 0  (batiment)      -> CoSIA 1  (Batiment)
    5,   # FLAIR 1  (permeable)     -> CoSIA 5  (Zone permeable)
    4,   # FLAIR 2  (impermeable)   -> CoSIA 4  (Zone impermeable)
    6,   # FLAIR 3  (sol nu)        -> CoSIA 6  (Sol nu)
    7,   # FLAIR 4  (eau)           -> CoSIA 7  (Eau)
    14,  # FLAIR 5  (conifere)      -> CoSIA 14 (Conifere)
    13,  # FLAIR 6  (feuillu)       -> CoSIA 13 (Feuillu)
    15,  # FLAIR 7  (broussaille)   -> CoSIA 15 (Lande)
    12,  # FLAIR 8  (vigne)         -> CoSIA 12 (Vigne)
    9,   # FLAIR 9  (herbace)       -> CoSIA 9  (Herbace)
    10,  # FLAIR 10 (agricole)      -> CoSIA 10 (Agricole)
    11,  # FLAIR 11 (laboure)       -> CoSIA 11 (Laboure)
    3,   # FLAIR 12 (piscine)       -> CoSIA 3  (Piscine)
    8,   # FLAIR 13 (neige)         -> CoSIA 8  (Neige)
    0,   # FLAIR 14 (coupe)         -> 0 (desactive)
    0,   # FLAIR 15 (mixte)         -> 0 (desactive)
    0,   # FLAIR 16 (ligneux)       -> 0 (desactive)
    2,   # FLAIR 17 (serre)         -> CoSIA 2  (Serre)
    0,   # FLAIR 18 (autre)         -> 0 (desactive)
], dtype=np.int32)


# ---------------------------------------------------------------------------
# Modele de segmentation simplifie (UNet-like)
# ---------------------------------------------------------------------------

class ConvBlock(nn.Module):
    """Double convolution avec BatchNorm et ReLU."""

    def __init__(self, in_ch, out_ch):
        super().__init__()
        self.block = nn.Sequential(
            nn.Conv2d(in_ch, out_ch, 3, padding=1, bias=False),
            nn.BatchNorm2d(out_ch),
            nn.ReLU(inplace=True),
            nn.Conv2d(out_ch, out_ch, 3, padding=1, bias=False),
            nn.BatchNorm2d(out_ch),
            nn.ReLU(inplace=True),
        )

    def forward(self, x):
        return self.block(x)


class SimpleUNet(nn.Module):
    """UNet simplifie pour la segmentation semantique.

    Utilise comme fallback quand les architectures avancees
    (segmentation_models_pytorch) ne sont pas disponibles.
    """

    def __init__(self, in_channels=4, n_classes=19):
        super().__init__()
        # Encoder
        self.enc1 = ConvBlock(in_channels, 64)
        self.enc2 = ConvBlock(64, 128)
        self.enc3 = ConvBlock(128, 256)
        self.enc4 = ConvBlock(256, 512)
        self.pool = nn.MaxPool2d(2)

        # Bottleneck
        self.bottleneck = ConvBlock(512, 1024)

        # Decoder
        self.up4 = nn.ConvTranspose2d(1024, 512, 2, stride=2)
        self.dec4 = ConvBlock(1024, 512)
        self.up3 = nn.ConvTranspose2d(512, 256, 2, stride=2)
        self.dec3 = ConvBlock(512, 256)
        self.up2 = nn.ConvTranspose2d(256, 128, 2, stride=2)
        self.dec2 = ConvBlock(256, 128)
        self.up1 = nn.ConvTranspose2d(128, 64, 2, stride=2)
        self.dec1 = ConvBlock(128, 64)

        # Classification head
        self.head = nn.Conv2d(64, n_classes, 1)

    def forward(self, x):
        e1 = self.enc1(x)
        e2 = self.enc2(self.pool(e1))
        e3 = self.enc3(self.pool(e2))
        e4 = self.enc4(self.pool(e3))

        b = self.bottleneck(self.pool(e4))

        d4 = self.dec4(torch.cat([self.up4(b), e4], dim=1))
        d3 = self.dec3(torch.cat([self.up3(d4), e3], dim=1))
        d2 = self.dec2(torch.cat([self.up2(d3), e2], dim=1))
        d1 = self.dec1(torch.cat([self.up1(d2), e1], dim=1))

        return self.head(d1)


# ---------------------------------------------------------------------------
# Chargement du modele FLAIR
# ---------------------------------------------------------------------------

def _try_load_smp_model(encoder_name, decoder_type, in_channels, n_classes):
    """Tente de charger un modele segmentation_models_pytorch."""
    try:
        import segmentation_models_pytorch as smp
    except ImportError:
        return None

    if decoder_type == "unet":
        model = smp.Unet(
            encoder_name=encoder_name,
            in_channels=in_channels,
            classes=n_classes,
            encoder_weights=None,
        )
    elif decoder_type == "upernet":
        model = smp.UPerNet(
            encoder_name=encoder_name,
            in_channels=in_channels,
            classes=n_classes,
            encoder_weights=None,
        )
    else:
        return None

    return model


def charger_modele_flair(chemin_poids, n_classes=19, in_channels=4,
                          encoder="resnet34", decoder="unet", device="cpu"):
    """
    Charge un modele FLAIR pour la segmentation.

    Args:
        chemin_poids: Chemin vers le fichier de poids
        n_classes: Nombre de classes (19 pour CoSIA, 23 pour LPIS)
        in_channels: Nombre de canaux d'entree (4 = RGBI, 5 = RGBI+DEM)
        encoder: Architecture de l'encodeur (resnet34, convnextv2_nano, etc.)
        decoder: Architecture du decodeur (unet, upernet)
        device: 'cpu' ou 'cuda'

    Returns:
        Modele PyTorch en mode evaluation
    """
    chemin = Path(chemin_poids)
    device = torch.device(device)

    print("  Chargement modele FLAIR: %s + %s" % (encoder, decoder))
    print("  Entrees: %d canaux, Sorties: %d classes" % (in_channels, n_classes))

    # Essayer d'abord avec segmentation_models_pytorch
    model = _try_load_smp_model(encoder, decoder, in_channels, n_classes)

    if model is None:
        raise ImportError(
            "segmentation_models_pytorch est requis pour les modeles FLAIR. "
            "Installez-le dans l'env conda maestro:\n"
            "  conda activate maestro\n"
            "  pip install segmentation-models-pytorch"
        )

    # Charger les poids
    if chemin.suffix == ".safetensors":
        from safetensors.torch import load_file
        state_dict = load_file(str(chemin), device=str(device))
    else:
        checkpoint = torch.load(str(chemin), map_location=device,
                                weights_only=False)
        if isinstance(checkpoint, dict):
            if "state_dict" in checkpoint:
                state_dict = checkpoint["state_dict"]
            elif "model_state_dict" in checkpoint:
                state_dict = checkpoint["model_state_dict"]
            elif "model" in checkpoint:
                state_dict = checkpoint["model"]
            else:
                state_dict = checkpoint
        else:
            state_dict = checkpoint

    # Auto-detection du meilleur prefixe
    # Tester plusieurs candidats et garder celui qui matche le plus de cles
    candidate_prefixes = [
        "", "model.", "net.", "module.", "backbone.",
        "model.model.", "network.", "seg_model.",
    ]
    model_keys = set(model.state_dict().keys())
    best_prefix = ""
    best_match = 0

    for prefix in candidate_prefixes:
        n_match = sum(
            1 for k in state_dict.keys()
            if k[len(prefix):] in model_keys and k.startswith(prefix)
        ) if prefix else sum(1 for k in state_dict.keys() if k in model_keys)
        if n_match > best_match:
            best_match = n_match
            best_prefix = prefix

    if best_prefix:
        print("  Prefixe detecte: '%s' (%d cles)" % (best_prefix, best_match))

    cleaned = {}
    for k, v in state_dict.items():
        clean_k = k[len(best_prefix):] if best_prefix and k.startswith(best_prefix) else k
        cleaned[clean_k] = v

    missing, unexpected = model.load_state_dict(cleaned, strict=False)
    if missing:
        print("  [INFO] Cles manquantes: %d" % len(missing))
    if unexpected:
        print("  [INFO] Cles inattendues: %d" % len(unexpected))

    model = model.to(device)
    model.eval()

    n_params = sum(p.numel() for p in model.parameters())
    print("  Modele charge sur %s (%s parametres)" % (
        device, format(n_params, ",")))

    return model


# ---------------------------------------------------------------------------
# Normalisation
# ---------------------------------------------------------------------------

def _normaliser_flair(img, mean=None, std=None):
    """Normalise un batch avec les statistiques FLAIR (valeurs brutes 0-255).

    Args:
        img: Tensor (B, C, H, W), valeurs brutes 0-255
        mean: Liste de moyennes par canal (defaut: FLAIR_MEAN)
        std: Liste d'ecarts-types par canal (defaut: FLAIR_STD)

    Returns:
        Tensor normalise (centre-reduit)
    """
    n_ch = img.shape[1]
    if mean is None:
        mean = FLAIR_MEAN[:n_ch]
        std = FLAIR_STD[:n_ch]

    # img: (B, C, H, W) - valeurs brutes 0-255, PAS de division par 255
    mean_t = torch.tensor(mean, dtype=img.dtype, device=img.device)
    std_t = torch.tensor(std, dtype=img.dtype, device=img.device)
    mean_t = mean_t.view(1, -1, 1, 1)
    std_t = std_t.view(1, -1, 1, 1)

    return (img - mean_t) / (std_t + 1e-8)


# ---------------------------------------------------------------------------
# Fenetre de Hann 2D pour le blending des patches
# ---------------------------------------------------------------------------

def creer_fenetre_hann(taille, device="cpu"):
    """
    Cree une fenetre de Hann 2D pour le blending sans couture des patches.

    Args:
        taille: Taille du patch (int ou tuple)
        device: 'cpu' ou 'cuda'

    Returns:
        Tensor (1, 1, H, W) avec les poids de la fenetre de Hann
    """
    if isinstance(taille, int):
        taille = (taille, taille)

    h_win = torch.hann_window(taille[0], periodic=False, device=device)
    w_win = torch.hann_window(taille[1], periodic=False, device=device)
    window = h_win.unsqueeze(1) * w_win.unsqueeze(0)  # (H, W)

    # Eviter les zeros aux bords
    window = window.clamp(min=1e-6)

    return window.unsqueeze(0).unsqueeze(0)  # (1, 1, H, W)


# ---------------------------------------------------------------------------
# Inference par patch
# ---------------------------------------------------------------------------

def predire_patch_segmentation(modele, image_np, device="cpu"):
    """
    Predit la carte de segmentation pour un patch.

    Args:
        modele: Modele de segmentation
        image_np: Array numpy (H, W, C) ou (C, H, W) ou (B, C, H, W)
        device: 'cpu' ou 'cuda'

    Returns:
        dict avec 'classes' (H, W array), 'probabilites' (C, H, W array)
    """
    device_t = torch.device(device)

    arr = np.array(image_np, dtype=np.float32)

    # Normaliser les dimensions
    if arr.ndim == 3:
        if arr.shape[-1] <= 10:  # (H, W, C) -> (C, H, W)
            arr = np.transpose(arr, (2, 0, 1))
        arr = arr[np.newaxis]  # (1, C, H, W)

    n_ch = arr.shape[1]
    t = torch.from_numpy(arr).float()

    # Normalisation centre-reduit avec stats FLAIR
    t = _normaliser_flair(t)

    t = t.to(device_t)

    with torch.no_grad():
        logits = modele(t)  # (B, C, H, W)
        probs = F.softmax(logits, dim=1)
        classes = torch.argmax(probs, dim=1)  # (B, H, W)

    classes_np = classes.squeeze(0).cpu().numpy()
    n_cls = logits.shape[1]

    # Remapper vers CoSIA
    if n_cls == 19 and len(FLAIR_TO_COSIA) == 19:
        classes_np = FLAIR_TO_COSIA[classes_np]
    elif n_cls == 15:
        classes_np = classes_np + 1

    return {
        "classes": classes_np,
        "probabilites": probs.squeeze(0).cpu().numpy(),
    }


def predire_batch_segmentation(modele, batch_np, device="cpu"):
    """
    Predit la segmentation pour un batch de patches.

    Args:
        modele: Modele de segmentation
        batch_np: Array numpy (B, C, H, W), valeurs 0-255
        device: 'cpu' ou 'cuda'

    Returns:
        dict avec 'classes' (B, H, W array), 'logits' (B, C, H, W array)
    """
    device_t = torch.device(device)
    arr = np.array(batch_np, dtype=np.float32)
    n_ch = arr.shape[1]

    t = torch.from_numpy(arr).float()

    # Normalisation centre-reduit avec stats FLAIR
    t = _normaliser_flair(t)

    t = t.to(device_t)

    with torch.no_grad():
        logits = modele(t)
        classes = torch.argmax(logits, dim=1)

    return {
        "classes": classes.cpu().numpy(),
        "logits": logits.cpu().numpy(),
    }


# ---------------------------------------------------------------------------
# Inference avec blending (fenetre de Hann)
# ---------------------------------------------------------------------------

def predire_raster_complet(modele, image_np, patch_size=512, overlap=128,
                            n_classes=19, device="cpu", batch_size=4):
    """
    Predit la carte de segmentation pour un raster complet avec blending.

    Decoupe l'image en patches avec overlap, applique une fenetre de Hann
    pour le blending, et reassemble la carte complete.

    Args:
        modele: Modele de segmentation
        image_np: Array numpy (C, H, W) ou (H, W, C)
        patch_size: Taille des patches (defaut: 512)
        overlap: Recouvrement entre patches (defaut: 128)
        n_classes: Nombre de classes (defaut: 19)
        device: 'cpu' ou 'cuda'
        batch_size: Taille des batchs (defaut: 4)

    Returns:
        Array numpy (H, W) avec les classes predites
    """
    device_t = torch.device(device)
    arr = np.array(image_np, dtype=np.float32)

    # Normaliser les dimensions -> (C, H, W)
    if arr.ndim == 3 and arr.shape[-1] <= 10:
        arr = np.transpose(arr, (2, 0, 1))

    C, H, W = arr.shape
    stride = patch_size - overlap

    # Creer les buffers de sortie
    output_sum = np.zeros((n_classes, H, W), dtype=np.float32)
    weight_sum = np.zeros((1, H, W), dtype=np.float32)

    # Fenetre de Hann
    hann = creer_fenetre_hann(patch_size, device=str(device_t))
    hann_np = hann.squeeze().cpu().numpy()

    # Generer les positions des patches
    positions = []
    for y in range(0, H - patch_size + 1, stride):
        for x in range(0, W - patch_size + 1, stride):
            positions.append((y, x))

    # Ajouter les bords si necessaire
    if H > patch_size and (H - patch_size) % stride != 0:
        for x in range(0, W - patch_size + 1, stride):
            positions.append((H - patch_size, x))
    if W > patch_size and (W - patch_size) % stride != 0:
        for y in range(0, H - patch_size + 1, stride):
            positions.append((y, W - patch_size))
    if H > patch_size and W > patch_size:
        if (H - patch_size) % stride != 0 and (W - patch_size) % stride != 0:
            positions.append((H - patch_size, W - patch_size))

    # Dedupliquer
    positions = list(set(positions))

    n_patches = len(positions)
    print("  Inference: %d patches (%dx%d, overlap %d)" % (
        n_patches, patch_size, patch_size, overlap))

    # Traiter par batch
    for i in range(0, n_patches, batch_size):
        batch_pos = positions[i:i + batch_size]
        batch = np.stack([
            arr[:, y:y + patch_size, x:x + patch_size]
            for y, x in batch_pos
        ])

        t = torch.from_numpy(batch).float()

        # Normalisation centre-reduit avec stats FLAIR
        t = _normaliser_flair(t)

        t = t.to(device_t)

        with torch.no_grad():
            logits = modele(t)
            probs = F.softmax(logits, dim=1).cpu().numpy()

        for j, (y, x) in enumerate(batch_pos):
            output_sum[:, y:y + patch_size, x:x + patch_size] += \
                probs[j] * hann_np
            weight_sum[:, y:y + patch_size, x:x + patch_size] += hann_np

        if (i // batch_size) % 10 == 0:
            print("  Batch %d / %d" % (i // batch_size + 1,
                                        (n_patches + batch_size - 1) // batch_size))

    # Normaliser par les poids
    weight_sum = np.maximum(weight_sum, 1e-8)
    output_norm = output_sum / weight_sum

    # Classe finale (argmax 0-indexed)
    classes = np.argmax(output_norm, axis=0)  # (H, W)

    # Remapper FLAIR-1 (0-18) vers CoSIA (1-15) si le modele a 19 classes
    if n_classes == 19 and len(FLAIR_TO_COSIA) == 19:
        classes = FLAIR_TO_COSIA[classes]
    elif n_classes == 15:
        # Modeles FLAIR-INC 15 classes : argmax 0-14 -> CoSIA 1-15
        classes = classes + 1

    return classes


# ---------------------------------------------------------------------------
# Classification spectrale de fallback
# ---------------------------------------------------------------------------

def classification_spectrale(image_np, n_classes=19):
    """
    Classification simple basee sur les indices spectraux.
    Utilisee comme fallback quand le modele ne charge pas.

    Args:
        image_np: Array numpy (C, H, W) avec bandes RGBI
        n_classes: Nombre de classes

    Returns:
        Array numpy (H, W) avec les classes predites
    """
    arr = np.array(image_np, dtype=np.float32)
    if arr.ndim == 3 and arr.shape[-1] <= 10:
        arr = np.transpose(arr, (2, 0, 1))

    C, H, W = arr.shape

    result = np.zeros((H, W), dtype=np.int64)

    if C >= 4:
        rouge = arr[0].astype(np.float64)
        vert = arr[1].astype(np.float64)
        bleu = arr[2].astype(np.float64)
        pir = arr[3].astype(np.float64)

        ndvi = (pir - rouge) / (pir + rouge + 1e-8)
        brightness = (rouge + vert + bleu) / 3.0

        # Classification basique par seuillage (codes CoSIA 1-indexed)
        result[ndvi > 0.6] = 13   # Feuillu (CoSIA 13)
        result[ndvi > 0.3] = 9    # Herbace/pelouse (CoSIA 9)
        result[ndvi > 0.1] = 10   # Agricole (CoSIA 10)
        result[(ndvi <= 0.1) & (brightness > 180)] = 1   # Batiment (CoSIA 1)
        result[(ndvi <= 0.1) & (brightness > 100)] = 4   # Impermeable (CoSIA 4)
        result[(ndvi <= 0.1) & (brightness <= 100)] = 6   # Sol nu (CoSIA 6)
        result[(ndvi < -0.1)] = 7  # Eau (CoSIA 7)
    else:
        rouge = arr[0].astype(np.float64)
        vert = arr[1].astype(np.float64)
        bleu = arr[2].astype(np.float64)
        brightness = (rouge + vert + bleu) / 3.0
        result[brightness > 180] = 1   # Batiment
        result[(brightness > 100) & (brightness <= 180)] = 9  # Herbace
        result[brightness <= 100] = 6   # Sol nu

    return result
