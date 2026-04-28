# Creer des patches d'inference avec overlap

Decoupe un raster en patches de taille fixe avec recouvrement pour
l'inference FLAIR (segmentation pixel).

## Usage

``` r
creer_patches_inference(r, patch_size = 512L, overlap = 128L)
```

## Arguments

- r:

  SpatRaster a decouper

- patch_size:

  Taille des patches en pixels (defaut: 512)

- overlap:

  Recouvrement entre patches en pixels (defaut: 128)

## Value

Liste avec `patches` (liste de SpatRaster), `positions` (data.frame avec
col, row, x, y), `raster_dim` (dimensions du raster original)
