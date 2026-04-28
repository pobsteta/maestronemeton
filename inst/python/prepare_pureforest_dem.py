#!/usr/bin/env python3
"""
prepare_pureforest_dem.py
=========================

Pre-traitement des nuages LAZ PureForest pour generer la modalite `dem`
MAESTRO (DSM + DTM, 2 canaux).

Architecture identique a `prepare_pureforest_aerial.py` :

  1. Telecharge `metadata/PureForest-patches.csv` via `hf_hub_download`
     (idempotent, cache HF natif).
  2. Pour chaque espece demandee, telecharge `data/lidar-<species>.zip`.
  3. Pour chaque LAZ dans le zip :
     - charge les points via `laspy` (backend `lazrs`),
     - DTM = points classe ASPRS 2 (sol), Delaunay TIN + interpolation
       lineaire sur grille 1 m alignee sur la bbox du LAZ,
     - DSM = points `return_number == 1` (premiers retours), idem,
     - upsample bilineaire a 256 x 256 (resolution finale ~ 0,2 m,
       alignee sur la modalite aerial),
     - ecrit `patches/<patch_id>/dem.tif` (2, 256, 256) float32 en
       EPSG:2154 avec transform alignee sur le LAZ.
  4. Calcule mean/std par bande (DSM, DTM) sur le split train.
  5. Met a jour `normalization.json` (preserve les autres modalites,
     en particulier `aerial` deja ecrit).

Le DataLoader `pureforest_dataset.PureForestDataset` charge automatiquement
ce fichier quand `modalities=["aerial", "dem"]`.

Usage
-----

    # Smoke test : 1 espece rare (~20 patches, ~12 Mo telecharges)
    python prepare_pureforest_dem.py \\
        --output data/pf --species Quercus_rubra

    # Run complet (Scaleway, ~120 GB de zip + ~3 GB de patches DEM extraits)
    python prepare_pureforest_dem.py --output /data/pureforest_maestro

Note : le repertoire `--output` doit etre le meme que pour
`prepare_pureforest_aerial.py` (les deux scripts ecrivent sous
`patches/<id>/`).
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

# Importe la liste d'especes depuis le module aerial pour rester DRY.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from prepare_pureforest_aerial import (  # noqa: E402
    ALL_SPECIES, SPLIT_NORMALIZE, ZIP_FILENAME_PREFIXES,
    load_patch_metadata,
)

# Classification ASPRS standard (cf. specs LAS 1.4).
ASPRS_GROUND = 2

# Resolution de la grille intermediaire (m / pixel). Le LAZ couvre 50 x 50 m,
# donc 1 m donne 50 x 50 cellules, suffisant compte tenu de la densite
# (~10-20 pts/m^2) et de la taille des houppiers. On upsample ensuite a
# 256 x 256 pour aligner sur la modalite aerial 0,2 m.
GRID_RES_M = 1.0


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--output", type=Path,
                   default=Path("data/pureforest_maestro"),
                   help="Repertoire de sortie (idem prepare_pureforest_aerial.py)")
    p.add_argument("--cache", type=Path, default=None,
                   help="Repertoire cache HuggingFace (defaut: HF_HOME)")
    p.add_argument("--species", nargs="+", default=None,
                   help="Liste d'especes a traiter (defaut: toutes les 18)")
    p.add_argument("--target-size", type=int, default=256,
                   help="Taille cible des patches en pixels (defaut: 256)")
    p.add_argument("--limit-per-zip", type=int, default=None,
                   help="Nombre max de patches par zip (smoke test)")
    p.add_argument("--no-stats", action="store_true",
                   help="Saute le calcul mean/std")
    p.add_argument("--overwrite", action="store_true",
                   help="Reecrit les patches deja presents")
    return p.parse_args()


def _strip_split_prefix(name: str) -> str:
    for pref in ZIP_FILENAME_PREFIXES:
        if name.startswith(pref):
            return name[len(pref):]
    return name


def _patch_id_from_zip_entry(entry: str) -> str | None:
    """lidar/train/TRAIN-Quercus_rubra-C0-176_1_88.laz -> Quercus_rubra-C0-176_1_88."""
    parts = entry.split("/")
    if len(parts) != 3 or not parts[2].endswith(".laz"):
        return None
    return _strip_split_prefix(parts[2][:-len(".laz")])


def _interpolate_grid(x: np.ndarray, y: np.ndarray, z: np.ndarray,
                      xmin: float, xmax: float,
                      ymin: float, ymax: float,
                      nx: int, ny: int) -> np.ndarray:
    """Interpole z sur une grille (ny, nx) via Delaunay TIN + nearest fallback.

    Convention image : ligne 0 = haut (ymax), colonne 0 = gauche (xmin).
    Les coordonnees de pixel sont les centres de cellule.
    """
    if len(x) < 4:
        return np.full((ny, nx), np.nan, dtype=np.float32)

    res_x = (xmax - xmin) / nx
    res_y = (ymax - ymin) / ny
    xs = xmin + (np.arange(nx) + 0.5) * res_x
    ys = ymax - (np.arange(ny) + 0.5) * res_y  # haut -> bas
    XX, YY = np.meshgrid(xs, ys)

    from scipy.interpolate import griddata
    grid = griddata((x, y), z, (XX, YY), method="linear")
    nan_mask = np.isnan(grid)
    if nan_mask.any():
        nn = griddata((x, y), z, (XX, YY), method="nearest")
        grid[nan_mask] = nn[nan_mask]
    return grid.astype(np.float32)


def _resample_bilinear(arr_chw: np.ndarray, target_size: int) -> np.ndarray:
    """(C, H, W) -> (C, target_size, target_size) bilineaire."""
    if arr_chw.shape[1] == target_size and arr_chw.shape[2] == target_size:
        return arr_chw
    try:
        import torch
        import torch.nn.functional as F
        t = torch.from_numpy(arr_chw).unsqueeze(0)
        t = F.interpolate(t, size=(target_size, target_size),
                          mode="bilinear", align_corners=False)
        return t.squeeze(0).numpy().astype(np.float32, copy=False)
    except ImportError:
        from scipy.ndimage import zoom
        zf = target_size / arr_chw.shape[1]
        return np.stack(
            [zoom(arr_chw[c], zf, order=1) for c in range(arr_chw.shape[0])]
        ).astype(np.float32, copy=False)


def laz_to_dem(las_bytes: bytes, target_size: int) -> tuple[np.ndarray, tuple[float, float, float, float]]:
    """LAZ bytes -> ((2, target_size, target_size) float32, (xmin, ymin, xmax, ymax))."""
    import laspy
    las = laspy.read(io.BytesIO(las_bytes))

    xmin, xmax = float(las.header.x_min), float(las.header.x_max)
    ymin, ymax = float(las.header.y_min), float(las.header.y_max)

    # Garde-fou : le footprint attendu est 50 x 50 m. On accepte 49-51 pour
    # tolerer les arrondis flottants, on rejette le reste.
    extent_x = xmax - xmin
    extent_y = ymax - ymin
    if not (49.0 <= extent_x <= 51.0 and 49.0 <= extent_y <= 51.0):
        raise ValueError(
            f"Footprint LAZ inattendu : {extent_x:.1f} x {extent_y:.1f} m "
            f"(attendu ~50 x 50 m)")

    nx = int(round(extent_x / GRID_RES_M))
    ny = int(round(extent_y / GRID_RES_M))

    x = np.asarray(las.x, dtype=np.float64)
    y = np.asarray(las.y, dtype=np.float64)
    z = np.asarray(las.z, dtype=np.float64)
    cls = np.asarray(las.classification)
    rn  = np.asarray(las.return_number)

    # DTM : sol classe 2 (fallback : tous les points si trop peu)
    gnd = cls == ASPRS_GROUND
    if gnd.sum() < 4:
        gnd = np.ones_like(cls, dtype=bool)
    dtm = _interpolate_grid(x[gnd], y[gnd], z[gnd],
                             xmin, xmax, ymin, ymax, nx, ny)

    # DSM : premiers retours (rn == 1, fallback : tous les points)
    fr = rn == 1
    if fr.sum() < 4:
        fr = np.ones_like(rn, dtype=bool)
    dsm = _interpolate_grid(x[fr], y[fr], z[fr],
                             xmin, xmax, ymin, ymax, nx, ny)

    # Stack (2, H, W) puis upsample a target_size.
    dem = np.stack([dsm, dtm], axis=0)
    dem = _resample_bilinear(dem, target_size)

    return dem.astype(np.float32, copy=False), (xmin, ymin, xmax, ymax)


def write_dem_geotiff(path: Path, dem: np.ndarray,
                       bbox: tuple[float, float, float, float]) -> None:
    """2 bandes float32 georeferencees Lambert-93 (EPSG:2154)."""
    xmin, ymin, xmax, ymax = bbox
    h, w = dem.shape[1], dem.shape[2]
    res_x = (xmax - xmin) / w
    res_y = (ymax - ymin) / h
    try:
        import rasterio
        from rasterio.transform import from_origin
        transform = from_origin(xmin, ymax, res_x, res_y)
        with rasterio.open(
            str(path), "w",
            driver="GTiff",
            width=w, height=h, count=2,
            dtype=np.float32,
            crs="EPSG:2154",
            transform=transform,
            compress="lzw",
        ) as dst:
            dst.write(dem)
            dst.set_band_description(1, "DSM")
            dst.set_band_description(2, "DTM")
    except ImportError:
        import tifffile
        tifffile.imwrite(str(path), dem, compression="lzw")


def process_species(species: str, *, hf_cache: Path | None,
                    output: Path, target_size: int,
                    metadata: dict[str, tuple[int, str]],
                    limit: int | None, overwrite: bool,
                    stats_acc: dict | None) -> tuple[int, int, int]:
    """Retourne (n_written, n_skip_unknown, n_skip_existing)."""
    from huggingface_hub import hf_hub_download

    print(f"\n--- {species} ---", flush=True)
    zip_local = hf_hub_download(
        repo_id=REPO_ID, repo_type="dataset",
        filename=f"data/lidar-{species}.zip",
        cache_dir=str(hf_cache) if hf_cache else None,
    )

    n_written = n_unknown = n_existing = 0
    try:
        from tqdm import tqdm
    except ImportError:
        def tqdm(it, **_):  # type: ignore[no-redef]
            return it

    with zipfile.ZipFile(zip_local) as z:
        entries = [n for n in z.namelist() if n.endswith(".laz")]
        if limit is not None:
            entries = entries[:limit]

        for entry in tqdm(entries, desc=species, leave=False):
            patch_id = _patch_id_from_zip_entry(entry)
            if patch_id is None or patch_id not in metadata:
                n_unknown += 1
                continue

            label, split = metadata[patch_id]
            patch_dir = output / "patches" / patch_id
            target = patch_dir / "dem.tif"
            if target.exists() and not overwrite:
                n_existing += 1
                continue
            patch_dir.mkdir(parents=True, exist_ok=True)

            try:
                raw = z.read(entry)
                dem, bbox = laz_to_dem(raw, target_size=target_size)
            except Exception as e:
                print(f"  [WARN] {patch_id} skip ({e})", flush=True)
                continue

            write_dem_geotiff(target, dem, bbox)
            n_written += 1

            if stats_acc is not None and split == "train":
                # 2 bandes (DSM, DTM) — ignore les NaN si subsist (rare)
                for c in range(2):
                    band = dem[c].astype(np.float64).ravel()
                    band = band[np.isfinite(band)]
                    stats_acc["sum"][c]   += band.sum()
                    stats_acc["sumsq"][c] += (band * band).sum()
                    stats_acc["n"][c]     += band.size

    print(f"  {species}: {n_written} patches DEM ecrits, "
          f"{n_existing} existants skippes, {n_unknown} hors metadata",
          flush=True)
    return n_written, n_unknown, n_existing


def update_normalization(output: Path, stats_acc: dict | None) -> None:
    if stats_acc is None or any(n == 0 for n in stats_acc["n"]):
        return
    n = np.asarray(stats_acc["n"], dtype=np.float64)
    mean = np.asarray(stats_acc["sum"]) / n
    var  = np.asarray(stats_acc["sumsq"]) / n - mean ** 2
    std  = np.sqrt(np.maximum(var, 1e-12))

    norm_path = output / "normalization.json"
    existing = {}
    if norm_path.exists():
        try:
            existing = json.loads(norm_path.read_text())
        except Exception:
            existing = {}

    existing["dem"] = {
        "mean": mean.tolist(),
        "std":  std.tolist(),
        "channel_order": ["DSM", "DTM"],
        "n_pixels": int(n.min()),  # par bande, identique en pratique
        "computed_on": "train",
    }
    norm_path.write_text(json.dumps(existing, indent=2))
    print(f"  normalization.json [dem] mean={np.round(mean, 3).tolist()} "
          f"std={np.round(std, 3).tolist()}")


def main() -> int:
    args = parse_args()

    try:
        from huggingface_hub import hf_hub_download  # noqa: F401
        import laspy  # noqa: F401
        from scipy.interpolate import griddata  # noqa: F401
    except ImportError as e:
        print(f"ERREUR: dependance manquante : {e}. "
              f"pip install huggingface_hub laspy lazrs scipy", file=sys.stderr)
        return 1

    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "patches").mkdir(exist_ok=True)

    print(f"=== Preparation dem PureForest -> {args.output} ===")
    print(f"  Cache HF : {args.cache or '(defaut)'}")

    # 1. Metadonnees
    print("\n--- Telechargement metadata ---")
    csv_local = hf_hub_download(
        repo_id=REPO_ID, repo_type="dataset",
        filename="metadata/PureForest-patches.csv",
        cache_dir=str(args.cache) if args.cache else None,
    )
    metadata = load_patch_metadata(Path(csv_local))
    print(f"  {len(metadata)} patches dans le CSV")

    # 2. Especes a traiter
    species_list = args.species or list(ALL_SPECIES)
    unknown = set(species_list) - set(ALL_SPECIES)
    if unknown:
        print(f"ERREUR: especes inconnues : {sorted(unknown)}", file=sys.stderr)
        return 1

    # 3. Pre-traitement
    stats_acc = None if args.no_stats else {
        "sum":   [0.0, 0.0],
        "sumsq": [0.0, 0.0],
        "n":     [0, 0],
    }
    total_written = total_unknown = 0
    for sp in species_list:
        n_w, n_u, _ = process_species(
            sp, hf_cache=args.cache, output=args.output,
            target_size=args.target_size, metadata=metadata,
            limit=args.limit_per_zip, overwrite=args.overwrite,
            stats_acc=stats_acc,
        )
        total_written += n_w
        total_unknown += n_u

    # 4. Normalisation
    print("\n--- Indexation ---")
    update_normalization(args.output, stats_acc)

    # 5. Bilan : patches DEM presents
    n_dem = sum(
        1 for d in (args.output / "patches").iterdir()
        if (d / "dem.tif").exists() and d.name in metadata
    )
    print(f"\nTermine : {total_written} patches DEM ecrits, "
          f"{n_dem} indexes au total, "
          f"{total_unknown} entrees zip hors metadata.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
