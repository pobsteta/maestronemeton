#!/usr/bin/env python3
"""
prepare_pureforest_aerial.py
============================

Pre-traitement du dataset `IGNF/PureForest` (Hugging Face Hub) pour le
fine-tuning MAESTRO sur la modalite `aerial`.

Le dataset n'est PAS un dataset HF formate (pas de parquet/arrow). C'est
une collection de ZIP files :

    data/imagery-<species>.zip      18 fichiers, ~25 GB total
    data/lidar-<species>.zip        18 fichiers, ~120 GB total (cf. P2-03)
    metadata/PureForest-patches.csv label + split par patch
    metadata/PureForestID-dictionnary.csv  espece -> class_index 0..12

Ce script :

  1. Telecharge les metadonnees CSV via `hf_hub_download` (idempotent).
  2. Telecharge les zip imagery-<species> demandes (idempotent — cache HF).
  3. Pour chaque TIFF dans le zip : reordonne les bandes NRGB -> RGBI,
     resample 250 -> 256 px, ecrit `patches/<patch_id>/aerial.tif`.
  4. Calcule mean/std par bande sur le split train.
  5. Ecrit `labels.csv`, `splits/{train,validation,test}.txt`, `normalization.json`.

Sortie (compatible `pureforest_dataset.py`) :

    data/pureforest_maestro/
        patches/<patch_id>/aerial.tif       (4, 256, 256) float32 [0, 1]
        splits/{train,validation,test}.txt  un patch_id par ligne
        labels.csv                          patch_id,label,split
        normalization.json                  mean/std aerial sur train

Note : le CSV PureForest utilise `val` ; on l'expose en sortie comme
`validation` pour rester coherent avec `pureforest_dataset.py`.

Usage
-----

    # Smoke test : 1 espece rare (~20 patches, ~12 Mo telecharges)
    python prepare_pureforest_aerial.py \\
        --output data/pf --species Quercus_rubra

    # Subset de validation (3 especes rares, ~150 Mo)
    python prepare_pureforest_aerial.py \\
        --output data/pf \\
        --species Quercus_rubra Abies_nordmanniana Pseudotsuga_menziesii

    # Run complet (Scaleway, ~25 GB de zip + ~50 GB de patches extraits)
    python prepare_pureforest_aerial.py --output /data/pureforest_maestro
"""

from __future__ import annotations

import argparse
import csv as csv_mod
import io
import json
import sys
import zipfile
from collections import defaultdict
from pathlib import Path

import numpy as np

REPO_ID = "IGNF/PureForest"

# Toutes les especes presentes dans le dataset (cf. inspection HF API).
ALL_SPECIES = (
    "Abies_alba", "Abies_nordmanniana", "Castanea_sativa", "Fagus_sylvatica",
    "Larix_decidua", "Picea_abies", "Pinus_halepensis", "Pinus_nigra",
    "Pinus_nigra_laricio", "Pinus_pinaster", "Pinus_sylvestris",
    "Pseudotsuga_menziesii", "Quercus_ilex", "Quercus_petraea",
    "Quercus_pubescens", "Quercus_robur", "Quercus_rubra",
    "Robinia_pseudoacacia",
)

# Ordre des bandes dans les TIFF PureForest (verifie via rasterio.descriptions
# sur Quercus_rubra) : Infrared, Red, Green, Blue.
SOURCE_BAND_ORDER = ("NIR", "R", "G", "B")
TARGET_BAND_ORDER = ("R", "G", "B", "NIR")
BAND_REINDEX = [SOURCE_BAND_ORDER.index(b) for b in TARGET_BAND_ORDER]

# Le CSV PureForest utilise "val" ; on normalise vers "validation" pour rester
# aligne sur pureforest_dataset.py (qui filtre par split == "validation").
SPLIT_NORMALIZE = {"train": "train", "val": "validation", "test": "test"}

# Prefixes ajoutes par PureForest aux noms de fichier dans les zip.
ZIP_FILENAME_PREFIXES = ("TRAIN-", "VAL-", "TEST-")


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--output", type=Path,
                   default=Path("data/pureforest_maestro"),
                   help="Repertoire de sortie")
    p.add_argument("--cache", type=Path, default=None,
                   help="Repertoire cache HuggingFace (defaut: HF_HOME)")
    p.add_argument("--species", nargs="+", default=None,
                   help="Liste d'especes a traiter (defaut: toutes les 18). "
                        "Ex: --species Quercus_rubra Abies_nordmanniana")
    p.add_argument("--target-size", type=int, default=256,
                   help="Taille cible des patches en pixels (defaut: 256)")
    p.add_argument("--limit-per-zip", type=int, default=None,
                   help="Nombre max de patches par zip (smoke test)")
    p.add_argument("--no-stats", action="store_true",
                   help="Saute le calcul mean/std (rapide)")
    p.add_argument("--overwrite", action="store_true",
                   help="Reecrit les patches deja presents")
    return p.parse_args()


def _strip_split_prefix(name: str) -> str:
    for pref in ZIP_FILENAME_PREFIXES:
        if name.startswith(pref):
            return name[len(pref):]
    return name


def _patch_id_from_zip_entry(entry: str) -> str | None:
    """imagery/train/TRAIN-Quercus_rubra-C0-176_1_88.tiff -> Quercus_rubra-C0-176_1_88."""
    parts = entry.split("/")
    if len(parts) != 3 or not parts[2].endswith(".tiff"):
        return None
    return _strip_split_prefix(parts[2][:-len(".tiff")])


def load_patch_metadata(csv_path: Path) -> dict[str, tuple[int, str]]:
    """Lit le CSV PureForest et retourne {patch_id: (class_index, split_normalized)}."""
    out: dict[str, tuple[int, str]] = {}
    with csv_path.open(newline="") as f:
        reader = csv_mod.DictReader(f)
        required = {"patch_id", "split", "class_index"}
        missing = required - set(reader.fieldnames or [])
        if missing:
            raise RuntimeError(
                f"Colonnes manquantes dans {csv_path.name} : {sorted(missing)}")
        for row in reader:
            split_raw = row["split"]
            split = SPLIT_NORMALIZE.get(split_raw)
            if split is None:
                raise RuntimeError(
                    f"Split inattendu '{split_raw}' pour patch "
                    f"{row['patch_id']}. Connus : {list(SPLIT_NORMALIZE)}")
            out[row["patch_id"]] = (int(row["class_index"]), split)
    return out


def to_chw_rgbi(img: np.ndarray, target_size: int) -> np.ndarray:
    """(H, W, 4) NRGB uint8 -> (4, target_size, target_size) RGBI float32 [0, 1]."""
    if img.ndim != 3 or img.shape[-1] != 4:
        raise ValueError(f"Image attendue (H, W, 4), recu {img.shape}")

    chw = np.transpose(img, (2, 0, 1))         # (4, H, W) NRGB
    chw = chw[BAND_REINDEX]                    # (4, H, W) RGBI

    if chw.dtype == np.uint8:
        chw = chw.astype(np.float32) / 255.0
    elif chw.dtype == np.uint16:
        chw = chw.astype(np.float32) / 65535.0
    else:
        chw = chw.astype(np.float32)
        if chw.max() > 1.5:
            chw = chw / 255.0

    if chw.shape[1] != target_size or chw.shape[2] != target_size:
        # Bilineaire via torch (pre-installe) ou scipy en fallback.
        try:
            import torch
            import torch.nn.functional as F
            t = torch.from_numpy(chw).unsqueeze(0)
            t = F.interpolate(t, size=(target_size, target_size),
                              mode="bilinear", align_corners=False)
            chw = t.squeeze(0).numpy()
        except ImportError:
            from scipy.ndimage import zoom
            zf = target_size / chw.shape[1]
            chw = np.stack([zoom(chw[c], zf, order=1)
                            for c in range(chw.shape[0])])

    return chw.astype(np.float32, copy=False)


def write_geotiff_4band(path: Path, chw: np.ndarray) -> None:
    """4 bandes float32 sans georeferencement (le DataLoader n'en a pas besoin)."""
    try:
        import rasterio
        from rasterio.transform import from_origin
        h, w = chw.shape[1], chw.shape[2]
        transform = from_origin(0, h, 1, 1)
        with rasterio.open(
            str(path), "w",
            driver="GTiff",
            width=w, height=h, count=chw.shape[0],
            dtype=np.float32,
            compress="lzw",
            transform=transform,
        ) as dst:
            dst.write(chw)
    except ImportError:
        import tifffile
        tifffile.imwrite(str(path), chw, photometric="rgb",
                         compression="lzw")


def process_species(species: str, *, hf_cache: Path | None,
                    output: Path, target_size: int,
                    metadata: dict[str, tuple[int, str]],
                    limit: int | None, overwrite: bool,
                    stats_acc: dict | None) -> tuple[int, int, int, int]:
    """Retourne (n_patches_ecrits, n_skip_unknown, n_skip_existing, n_pixels_train)."""
    from huggingface_hub import hf_hub_download

    print(f"\n--- {species} ---", flush=True)
    zip_local = hf_hub_download(
        repo_id=REPO_ID, repo_type="dataset",
        filename=f"data/imagery-{species}.zip",
        cache_dir=str(hf_cache) if hf_cache else None,
    )

    n_written = n_unknown = n_existing = n_pixels = 0
    try:
        from tqdm import tqdm
    except ImportError:
        def tqdm(it, **_):  # type: ignore[no-redef]
            return it

    with zipfile.ZipFile(zip_local) as z:
        entries = [n for n in z.namelist() if n.endswith(".tiff")]
        if limit is not None:
            entries = entries[:limit]

        for entry in tqdm(entries, desc=species, leave=False):
            patch_id = _patch_id_from_zip_entry(entry)
            if patch_id is None or patch_id not in metadata:
                n_unknown += 1
                continue

            label, split = metadata[patch_id]
            patch_dir = output / "patches" / patch_id
            target = patch_dir / "aerial.tif"
            if target.exists() and not overwrite:
                n_existing += 1
                continue
            patch_dir.mkdir(parents=True, exist_ok=True)

            try:
                import tifffile
                with z.open(entry) as fp:
                    arr = tifffile.imread(io.BytesIO(fp.read()))
                chw = to_chw_rgbi(arr, target_size=target_size)
            except Exception as e:
                print(f"  [WARN] {patch_id} skip ({e})", flush=True)
                continue

            write_geotiff_4band(target, chw)
            n_written += 1

            if stats_acc is not None and split == "train":
                flat = chw.reshape(chw.shape[0], -1).astype(np.float64)
                stats_acc["sum"]   += flat.sum(axis=1)
                stats_acc["sumsq"] += (flat * flat).sum(axis=1)
                stats_acc["n"]     += flat.shape[1]
                n_pixels += flat.shape[1]

    print(f"  {species}: {n_written} patches ecrits, "
          f"{n_existing} existants skippes, {n_unknown} hors metadata",
          flush=True)
    return n_written, n_unknown, n_existing, n_pixels


def write_outputs(output: Path,
                   metadata: dict[str, tuple[int, str]],
                   present_ids: set[str],
                   stats_acc: dict | None) -> None:
    # labels.csv
    labels_path = output / "labels.csv"
    with labels_path.open("w", newline="") as f:
        w = csv_mod.writer(f)
        w.writerow(["patch_id", "label", "split"])
        for pid in sorted(present_ids):
            label, split = metadata[pid]
            w.writerow([pid, label, split])
    print(f"  labels.csv : {len(present_ids)} lignes")

    # splits/<split>.txt
    by_split: dict[str, list[str]] = defaultdict(list)
    for pid in sorted(present_ids):
        by_split[metadata[pid][1]].append(pid)
    splits_dir = output / "splits"
    splits_dir.mkdir(exist_ok=True)
    for split in ("train", "validation", "test"):
        (splits_dir / f"{split}.txt").write_text(
            "\n".join(by_split.get(split, [])) + "\n")
        print(f"  splits/{split}.txt : {len(by_split.get(split, []))} ids")

    # normalization.json
    if stats_acc is not None and stats_acc["n"] > 0:
        n = stats_acc["n"]
        mean = stats_acc["sum"] / n
        var  = stats_acc["sumsq"] / n - mean ** 2
        std  = np.sqrt(np.maximum(var, 1e-12))
        norm = {
            "aerial": {
                "mean": mean.tolist(),
                "std":  std.tolist(),
                "channel_order": list(TARGET_BAND_ORDER),
                "n_pixels": int(n),
                "computed_on": "train",
            }
        }
        norm_path = output / "normalization.json"
        # Preserve les autres modalites existantes (cf. dem en P2-03).
        if norm_path.exists():
            try:
                existing = json.loads(norm_path.read_text())
                existing.update(norm)
                norm = existing
            except Exception:
                pass
        norm_path.write_text(json.dumps(norm, indent=2))
        print(f"  normalization.json : aerial mean={np.round(mean, 4).tolist()} "
              f"std={np.round(std, 4).tolist()}")


def main() -> int:
    args = parse_args()

    try:
        from huggingface_hub import hf_hub_download
    except ImportError:
        print("ERREUR: package `huggingface_hub` requis. "
              "pip install huggingface_hub", file=sys.stderr)
        return 1

    hf_cache = args.cache
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "patches").mkdir(exist_ok=True)

    print(f"=== Preparation aerial PureForest -> {args.output} ===")
    print(f"  Cache HF : {hf_cache or '(defaut)'}")

    # 1. Metadonnees
    print("\n--- Telechargement metadata ---")
    csv_local = hf_hub_download(
        repo_id=REPO_ID, repo_type="dataset",
        filename="metadata/PureForest-patches.csv",
        cache_dir=str(hf_cache) if hf_cache else None,
    )
    metadata = load_patch_metadata(Path(csv_local))
    print(f"  {len(metadata)} patches dans le CSV "
          f"(splits : "
          f"train={sum(1 for _, s in metadata.values() if s == 'train')}, "
          f"val={sum(1 for _, s in metadata.values() if s == 'validation')}, "
          f"test={sum(1 for _, s in metadata.values() if s == 'test')})")

    # 2. Especes a traiter
    species_list = args.species or list(ALL_SPECIES)
    unknown = set(species_list) - set(ALL_SPECIES)
    if unknown:
        print(f"ERREUR: especes inconnues : {sorted(unknown)}", file=sys.stderr)
        print(f"  Choix : {list(ALL_SPECIES)}", file=sys.stderr)
        return 1

    # 3. Pre-traitement
    stats_acc = None if args.no_stats else {
        "sum":   np.zeros(4, dtype=np.float64),
        "sumsq": np.zeros(4, dtype=np.float64),
        "n":     0,
    }
    total_written = total_unknown = 0
    for sp in species_list:
        n_w, n_u, _, _ = process_species(
            sp, hf_cache=hf_cache, output=args.output,
            target_size=args.target_size, metadata=metadata,
            limit=args.limit_per_zip, overwrite=args.overwrite,
            stats_acc=stats_acc,
        )
        total_written += n_w
        total_unknown += n_u

    # 4. Sorties
    print("\n--- Indexation ---")
    present_ids = {
        d.name for d in (args.output / "patches").iterdir()
        if (d / "aerial.tif").exists() and d.name in metadata
    }
    write_outputs(args.output, metadata, present_ids, stats_acc)

    print(f"\nTermine : {total_written} patches ecrits, "
          f"{len(present_ids)} indexes au total, "
          f"{total_unknown} entrees zip hors metadata.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
