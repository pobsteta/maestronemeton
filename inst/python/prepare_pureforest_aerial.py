#!/usr/bin/env python3
"""
prepare_pureforest_aerial.py
============================

Pre-traitement du dataset Hugging Face `IGNF/PureForest` pour le
fine-tuning MAESTRO sur la modalite `aerial`.

Sortie (cf. DEV_PLAN.md sec. 4.4) :

    data/pureforest_maestro/
        patches/<patch_id>/aerial.tif        (4, 256, 256) float32 [0, 1]
        splits/{train,val,test}.txt          un patch_id par ligne
        labels.parquet                       patch_id, label, split, forest_id?
        normalization.json                   mean/std par bande (sur train)
        metadata.parquet                     year_aerial, year_lidar, ...

Phase 1 : seul `aerial` est materialise. Les modalites `dem`, `s2`,
`s1_asc`, `s1_des` sont produites par d'autres scripts en phase 2/3.

Hypotheses sur le schema HF du dataset (a verifier au premier run via
--inspect-schema) :

  - champ `aerial` ou `image`  : ndarray (H, W, C) ou (C, H, W), C=4
    ordre NIR, R, G, B (cf. fiche IGNF/PureForest)
  - champ `label` ou `species` : int 0..12 (mapping cf. essences_pureforest()
    cote R)
  - champ `id` ou `patch_id`   : identifiant unique du patch (string)
  - champ `split`              : optionnel ; sinon les 3 splits sont
    obtenus via `load_dataset(split="train"|"validation"|"test")`

Si les noms different, ajuster les constantes FIELD_* en haut de fichier.

Usage
-----

    # Inspecter le schema sans rien ecrire (recommande au premier run)
    python prepare_pureforest_aerial.py --inspect-schema

    # Smoke test sur 100 patches
    python prepare_pureforest_aerial.py --output data/pf --limit 100

    # Run complet (long, ~50 Go ; a faire sur Scaleway)
    python prepare_pureforest_aerial.py --output /data/pureforest_maestro
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Iterable

import numpy as np


# ---------------------------------------------------------------------------
# Schema du dataset HF — ajuster si necessaire au premier run.
# ---------------------------------------------------------------------------

FIELD_AERIAL_CANDIDATES = ("aerial", "image", "rgbi", "vhr")
FIELD_LABEL_CANDIDATES  = ("label", "species", "class", "tree_species")
FIELD_ID_CANDIDATES     = ("id", "patch_id", "filename", "name")

# Ordre de canaux retourne par PureForest selon la fiche HF :
#   NIR, R, G, B  (4 bandes)
# MAESTRO attend pour la modalite `aerial` :
#   R, G, B, NIR  (cf. fiche IGNF/MAESTRO_FLAIR-HUB_base)
SOURCE_BAND_ORDER = ("NIR", "R", "G", "B")
TARGET_BAND_ORDER = ("R", "G", "B", "NIR")
BAND_REINDEX = [SOURCE_BAND_ORDER.index(b) for b in TARGET_BAND_ORDER]


# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--output", type=Path, default=Path("data/pureforest_maestro"),
                   help="Repertoire de sortie")
    p.add_argument("--cache", type=Path, default=None,
                   help="Repertoire cache HuggingFace (defaut: HF_HOME)")
    p.add_argument("--target-size", type=int, default=256,
                   help="Taille cible des patches en pixels (defaut: 256)")
    p.add_argument("--source-size", type=int, default=250,
                   help="Taille source des patches PureForest (defaut: 250)")
    p.add_argument("--splits", nargs="+",
                   default=["train", "validation", "test"],
                   help="Splits a traiter")
    p.add_argument("--limit", type=int, default=None,
                   help="Nombre max de samples par split (smoke test)")
    p.add_argument("--inspect-schema", action="store_true",
                   help="Affiche les champs disponibles et arrete")
    p.add_argument("--no-stats", action="store_true",
                   help="Ne calcule pas mean/std sur le train (rapide)")
    p.add_argument("--repo", default="IGNF/PureForest",
                   help="Identifiant HuggingFace du dataset")
    p.add_argument("--num-workers", type=int, default=0,
                   help="Workers DataLoader si --use-dataloader")
    return p.parse_args()


def find_field(record: dict, candidates: Iterable[str]) -> str:
    for c in candidates:
        if c in record:
            return c
    raise KeyError(
        f"Aucun des champs {list(candidates)} trouve dans le record. "
        f"Champs disponibles : {sorted(record.keys())}. "
        f"Ajuster FIELD_*_CANDIDATES dans prepare_pureforest_aerial.py."
    )


def to_chw_float(img: np.ndarray, target_size: int) -> np.ndarray:
    """
    Convertit un patch aerial PureForest en (4, target_size, target_size)
    float32 dans [0, 1], reordonne en R, G, B, NIR.

    Accepte (H, W, C), (C, H, W), uint8 ou uint16.
    """
    arr = np.asarray(img)

    if arr.ndim != 3:
        raise ValueError(f"Image patch attendue 3D, recu {arr.shape}")

    # Detecter (H, W, C) vs (C, H, W) via la dimension la plus petite
    if arr.shape[0] in (3, 4) and arr.shape[-1] not in (3, 4):
        # Probablement (C, H, W)
        chw = arr
    elif arr.shape[-1] in (3, 4):
        # (H, W, C)
        chw = np.transpose(arr, (2, 0, 1))
    else:
        raise ValueError(f"Forme inattendue : {arr.shape}")

    if chw.shape[0] != 4:
        raise ValueError(
            f"Patch aerial attend 4 bandes, recu {chw.shape[0]}. "
            f"Verifier l'ordre {SOURCE_BAND_ORDER} dans la source HF.")

    # Reordonner NIR, R, G, B -> R, G, B, NIR
    chw = chw[BAND_REINDEX]

    # Normaliser uint -> float32 [0, 1]
    if chw.dtype == np.uint8:
        chw = chw.astype(np.float32) / 255.0
    elif chw.dtype == np.uint16:
        chw = chw.astype(np.float32) / 65535.0
    else:
        chw = chw.astype(np.float32)
        if chw.max() > 1.5:
            # Heuristique : ortho IGN typiquement 0..255
            chw = chw / 255.0

    # Resample bilineaire vers target_size
    if chw.shape[1] != target_size or chw.shape[2] != target_size:
        try:
            import torch
            import torch.nn.functional as F
            t = torch.from_numpy(chw).unsqueeze(0)  # (1, C, H, W)
            t = F.interpolate(t, size=(target_size, target_size),
                               mode="bilinear", align_corners=False)
            chw = t.squeeze(0).numpy()
        except ImportError:
            # Fallback scipy — degrade gracieusement
            from scipy.ndimage import zoom
            zoom_factor = target_size / chw.shape[1]
            chw = np.stack([zoom(chw[c], zoom_factor, order=1)
                             for c in range(chw.shape[0])])

    return chw.astype(np.float32, copy=False)


def write_aerial_geotiff(path: Path, chw: np.ndarray) -> None:
    """
    Ecrit un GeoTIFF 4 bandes float32. Pas de geometrie reelle (les patches
    PureForest n'ont pas de georeferencement individuel exploite ici).
    """
    try:
        import rasterio
        from rasterio.transform import from_origin
    except ImportError:
        # Fallback tifffile
        import tifffile
        # tifffile attend (H, W, C) ou (C, H, W) selon planarconfig
        tifffile.imwrite(str(path), chw, photometric="rgb", compression="lzw")
        return

    h, w = chw.shape[1], chw.shape[2]
    transform = from_origin(0, h, 1, 1)  # transform unite, sans CRS
    with rasterio.open(
        str(path), "w",
        driver="GTiff",
        width=w, height=h, count=chw.shape[0],
        dtype=np.float32,
        compress="lzw",
        transform=transform,
    ) as dst:
        dst.write(chw)


def main() -> int:
    args = parse_args()

    try:
        from datasets import load_dataset
    except ImportError:
        print("ERREUR: package `datasets` requis. pip install datasets",
              file=sys.stderr)
        return 1

    cache_kwargs = {}
    if args.cache is not None:
        cache_kwargs["cache_dir"] = str(args.cache)

    # --- Inspection de schema ---
    if args.inspect_schema:
        print(f"=== Schema {args.repo} ===")
        for sp in args.splits:
            try:
                ds = load_dataset(args.repo, split=sp, **cache_kwargs)
            except Exception as e:
                print(f"  [WARN] Impossible de charger split {sp}: {e}")
                continue
            print(f"\n--- {sp} ({len(ds)} samples) ---")
            print(f"Features : {ds.features}")
            sample = ds[0]
            print(f"Champs   : {sorted(sample.keys())}")
            for k, v in sample.items():
                desc = type(v).__name__
                if hasattr(v, "shape"):
                    desc += f" shape={v.shape} dtype={v.dtype}"
                elif hasattr(v, "size"):
                    desc += f" size={v.size}"
                print(f"  {k:20s} : {desc}")
        return 0

    out = args.output
    (out / "patches").mkdir(parents=True, exist_ok=True)
    (out / "splits").mkdir(exist_ok=True)

    labels = []
    band_sum   = np.zeros(4, dtype=np.float64)
    band_sumsq = np.zeros(4, dtype=np.float64)
    n_pixels   = 0

    field_aerial = field_label = field_id = None

    for sp in args.splits:
        try:
            ds = load_dataset(args.repo, split=sp, **cache_kwargs)
        except Exception as e:
            print(f"  [WARN] Skip split {sp}: {e}")
            continue
        if args.limit is not None:
            ds = ds.select(range(min(args.limit, len(ds))))

        if field_aerial is None:
            sample = ds[0]
            field_aerial = find_field(sample, FIELD_AERIAL_CANDIDATES)
            field_label  = find_field(sample, FIELD_LABEL_CANDIDATES)
            try:
                field_id = find_field(sample, FIELD_ID_CANDIDATES)
            except KeyError:
                field_id = None
            print(f"  Schema detecte : aerial={field_aerial}, "
                  f"label={field_label}, id={field_id}")

        split_ids = []
        try:
            from tqdm import tqdm
            iterator = tqdm(ds, desc=sp)
        except ImportError:
            iterator = ds

        for i, sample in enumerate(iterator):
            if field_id is not None and sample.get(field_id):
                patch_id = str(sample[field_id])
            else:
                patch_id = f"{sp}_{i:07d}"
            patch_id = patch_id.replace("/", "_").replace("\\", "_")
            label = int(sample[field_label])

            try:
                chw = to_chw_float(sample[field_aerial],
                                     target_size=args.target_size)
            except Exception as e:
                print(f"  [WARN] {patch_id} skip ({e})")
                continue

            patch_dir = out / "patches" / patch_id
            patch_dir.mkdir(parents=True, exist_ok=True)
            write_aerial_geotiff(patch_dir / "aerial.tif", chw)

            labels.append({"patch_id": patch_id, "label": label,
                            "split": sp})
            split_ids.append(patch_id)

            # Statistiques uniquement sur le train officiel
            if sp == "train" and not args.no_stats:
                # accumulation par bande (C, H*W)
                flat = chw.reshape(chw.shape[0], -1).astype(np.float64)
                band_sum   += flat.sum(axis=1)
                band_sumsq += (flat * flat).sum(axis=1)
                n_pixels   += flat.shape[1]

        (out / "splits" / f"{sp}.txt").write_text("\n".join(split_ids) + "\n")
        print(f"  {sp}: {len(split_ids)} patches ecrits")

    # --- Statistiques de normalisation ---
    if n_pixels > 0 and not args.no_stats:
        mean = band_sum / n_pixels
        var  = band_sumsq / n_pixels - mean ** 2
        std  = np.sqrt(np.maximum(var, 1e-12))
        norm = {
            "aerial": {
                "mean": mean.tolist(),
                "std":  std.tolist(),
                "channel_order": list(TARGET_BAND_ORDER),
                "n_pixels": int(n_pixels),
                "computed_on": "train",
            }
        }
        (out / "normalization.json").write_text(json.dumps(norm, indent=2))
        print(f"  normalisation.json : mean={mean.round(4).tolist()} "
              f"std={std.round(4).tolist()}")

    # --- Labels parquet ---
    if labels:
        try:
            import pandas as pd
            pd.DataFrame(labels).to_parquet(out / "labels.parquet",
                                              index=False)
            print(f"  labels.parquet : {len(labels)} lignes")
        except ImportError:
            # Fallback CSV
            with (out / "labels.csv").open("w") as f:
                f.write("patch_id,label,split\n")
                for r in labels:
                    f.write(f"{r['patch_id']},{r['label']},{r['split']}\n")
            print(f"  labels.csv : {len(labels)} lignes "
                  "(installe pandas+pyarrow pour parquet)")

    print("\nPre-traitement aerial termine.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
