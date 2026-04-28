# Telecharger le MNT (RGE ALTI 1m) pour une AOI

Telecharge le Modele Numerique de Terrain depuis la Geoplateforme IGN
via WMS-R. Le MNT est optionnellement reechantillonne a 0.2m pour
s'aligner sur la grille des orthophotos.

## Usage

``` r
download_mnt_for_aoi(aoi, output_dir, rgbi = NULL)
```

## Arguments

- aoi:

  sf object en Lambert-93

- output_dir:

  Repertoire de sortie

- rgbi:

  SpatRaster de reference pour le reechantillonnage a 0.2m (NULL =
  garder la resolution native 1m)

## Value

Liste avec `mnt` (SpatRaster) et `mnt_path`, ou NULL si echec
