"""
pureforest_dataset.py
=====================

`PureForestDataset` : DataLoader PyTorch pour le fine-tuning de MAESTRO
sur le dataset PureForest (mono-label, 13 classes d'essences forestieres).

Lit la structure produite par `prepare_pureforest_aerial.py` :

    data/pureforest_maestro/
        patches/<patch_id>/aerial.tif   (4, 256, 256) float32 [0, 1]
        patches/<patch_id>/dem.tif      (2, 256, 256) float32   (phase 2)
        patches/<patch_id>/s2.tif       (10, 6, 6) float32      (phase 3)
        patches/<patch_id>/s1_asc.tif   (2, 6, 6) float32 dB    (phase 3)
        patches/<patch_id>/s1_des.tif   (2, 6, 6) float32 dB    (phase 3)
        splits/{train,val,test}.txt
        labels.parquet ou labels.csv
        normalization.json

Contrat MAESTRO (cf. fiche modele HF `IGNF/MAESTRO_FLAIR-HUB_base`) :

  - `__getitem__(i)` retourne `(inputs, target)`
  - `inputs` = dict[str, Tensor (C, H, W)] keys ⊆ {aerial, dem, s2, s1_asc, s1_des}
  - `target` = int (mono-label, 0..12)

Ce fichier est destine a etre depose dans un fork de IGNF/MAESTRO sous
`maestro/datasets/pureforest.py`. Il est conserve ici pour iteration
locale et reproductibilite.

Voir aussi `conf/pureforest.yaml` (config Hydra).
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Iterable

import numpy as np
import torch
from torch.utils.data import Dataset


# ---------------------------------------------------------------------------
# Classes PureForest (cf. fiche dataset HF + DEV_PLAN.md sec. 7.3)
# ---------------------------------------------------------------------------

PUREFOREST_CLASSES = [
    "Chene decidu",          # 0  Quercus robur, Q. petraea, Q. pubescens
    "Chene vert",            # 1  Quercus ilex
    "Hetre",                 # 2  Fagus sylvatica
    "Chataignier",           # 3  Castanea sativa
    "Robinier",              # 4  Robinia pseudoacacia
    "Pin maritime",          # 5  Pinus pinaster
    "Pin sylvestre",         # 6  Pinus sylvestris
    "Pin noir",              # 7  Pinus nigra
    "Pin d'Alep",            # 8  Pinus halepensis
    "Sapin",                 # 9  Abies alba
    "Epicea",                # 10 Picea abies
    "Meleze",                # 11 Larix decidua, L. kaempferi
    "Douglas",               # 12 Pseudotsuga menziesii
]

N_CLASSES = len(PUREFOREST_CLASSES)


# ---------------------------------------------------------------------------
# Lecture I/O — wrappers tolerants a l'absence de rasterio
# ---------------------------------------------------------------------------

def _read_tif_chw(path: Path) -> np.ndarray:
    """Lit un GeoTIFF en (C, H, W) float32. Fallback tifffile si rasterio absent."""
    try:
        import rasterio
        with rasterio.open(str(path)) as src:
            return src.read().astype(np.float32)  # (C, H, W)
    except ImportError:
        import tifffile
        arr = tifffile.imread(str(path))
        if arr.ndim == 2:
            arr = arr[np.newaxis, ...]
        elif arr.ndim == 3 and arr.shape[-1] <= 16:
            # (H, W, C) -> (C, H, W)
            arr = np.transpose(arr, (2, 0, 1))
        return arr.astype(np.float32)


def _load_labels(root: Path) -> list[dict]:
    parquet = root / "labels.parquet"
    csv = root / "labels.csv"
    if parquet.exists():
        try:
            import pandas as pd
            return pd.read_parquet(parquet).to_dict("records")
        except ImportError:
            pass
    if csv.exists():
        rows = []
        with csv.open() as f:
            header = f.readline().strip().split(",")
            for line in f:
                vals = line.strip().split(",")
                rows.append(dict(zip(header, vals)))
        return rows
    raise FileNotFoundError(
        f"Ni {parquet} ni {csv} trouve. Lancer prepare_pureforest_aerial.py"
    )


def _load_normalization(root: Path) -> dict:
    norm_path = root / "normalization.json"
    if norm_path.exists():
        return json.loads(norm_path.read_text())
    return {}


# ---------------------------------------------------------------------------
# Dataset
# ---------------------------------------------------------------------------

class PureForestDataset(Dataset):
    """
    Dataset PureForest mono-label pour fine-tuning MAESTRO.

    Parameters
    ----------
    root_dir : Path | str
        Racine du dataset pre-traite (sortie de `prepare_pureforest_aerial.py`).
    split : str
        "train", "validation" ou "test".
    modalities : list[str]
        Sous-ensemble de {aerial, dem, s2, s1_asc, s1_des}.
    normalize : bool
        Applique mean/std de `normalization.json` si disponible.
    """

    SUPPORTED_MODS = ("aerial", "dem", "s2", "s1_asc", "s1_des")

    def __init__(self,
                 root_dir,
                 split: str = "train",
                 modalities: Iterable[str] = ("aerial",),
                 normalize: bool = True,
                 strict_modalities: bool = False):
        self.root = Path(root_dir)
        self.split = split
        self.modalities = list(modalities)
        for m in self.modalities:
            if m not in self.SUPPORTED_MODS:
                raise ValueError(
                    f"Modalite '{m}' non supportee. "
                    f"Choix: {self.SUPPORTED_MODS}")
        self.normalize = normalize
        self.strict_modalities = strict_modalities

        # Charger les labels et filtrer par split
        all_rows = _load_labels(self.root)
        rows = [r for r in all_rows if str(r.get("split")) == split]
        if not rows:
            raise RuntimeError(
                f"Aucune ligne pour split={split} dans {self.root}/labels."
                " Verifier prepare_pureforest_aerial.py.")

        self.samples = [(str(r["patch_id"]), int(r["label"])) for r in rows]

        # Charger les stats de normalisation si dispo
        self.norm_stats = _load_normalization(self.root)

        print(f"  PureForest[{split}] : {len(self.samples)} patches, "
              f"modalites={self.modalities}, normalize={self.normalize}")

    def __len__(self) -> int:
        return len(self.samples)

    @property
    def n_classes(self) -> int:
        return N_CLASSES

    @property
    def class_names(self) -> list[str]:
        return list(PUREFOREST_CLASSES)

    def _load_modality(self, patch_id: str, mod: str) -> np.ndarray | None:
        path = self.root / "patches" / patch_id / f"{mod}.tif"
        if not path.exists():
            return None
        return _read_tif_chw(path)

    def _normalize(self, arr: np.ndarray, mod: str) -> np.ndarray:
        if not self.normalize:
            return arr
        stats = self.norm_stats.get(mod)
        if stats is None:
            return arr
        mean = np.asarray(stats["mean"], dtype=np.float32).reshape(-1, 1, 1)
        std  = np.asarray(stats["std"],  dtype=np.float32).reshape(-1, 1, 1)
        if mean.shape[0] != arr.shape[0]:
            return arr
        return (arr - mean) / np.maximum(std, 1e-6)

    def __getitem__(self, idx: int):
        patch_id, label = self.samples[idx]

        inputs: dict[str, torch.Tensor] = {}
        for mod in self.modalities:
            arr = self._load_modality(patch_id, mod)
            if arr is None:
                if self.strict_modalities:
                    raise FileNotFoundError(
                        f"Modalite {mod} manquante pour {patch_id}")
                continue
            arr = self._normalize(arr, mod)
            inputs[mod] = torch.from_numpy(arr.astype(np.float32, copy=False))

        if not inputs:
            raise RuntimeError(
                f"Aucune modalite chargee pour {patch_id}. "
                f"Modalites demandees : {self.modalities}.")

        return inputs, int(label)


# ---------------------------------------------------------------------------
# Collate function multi-modale
# ---------------------------------------------------------------------------

def collate_multimodal(batch):
    """
    Empile un batch heterogene par modalite.
    Garde uniquement les modalites presentes dans tous les samples du batch
    (les patches incomplets ne penalisent pas les autres).
    """
    inputs_list, labels = zip(*batch)

    common = set(inputs_list[0].keys())
    for d in inputs_list[1:]:
        common &= set(d.keys())

    stacked = {}
    for mod in common:
        stacked[mod] = torch.stack([d[mod] for d in inputs_list])

    return stacked, torch.tensor(labels, dtype=torch.long)
