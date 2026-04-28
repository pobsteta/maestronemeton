# Preparer les patches d'entrainement pour le decodeur de segmentation

Decoupe les rasters multimodaux et le masque BD Foret NDP0 en patches de
250x250 px, organises en structure train/val pour l'entrainement.

## Usage

``` r
preparer_patches_entrainement(
  modalites,
  labels,
  aoi,
  output_dir = "data/segmentation",
  patch_size = 250L,
  resolution = 0.2,
  val_ratio = 0.15,
  min_forest_pct = 10
)
```

## Arguments

- modalites:

  Liste nommee de SpatRasters (aerial, dem, s2, ...)

- labels:

  SpatRaster masque NDP0 (issu de
  [`preparer_labels_ndp0()`](https://pobsteta.github.io/maestronemeton/reference/preparer_labels_ndp0.md))

- aoi:

  sf object

- output_dir:

  Repertoire de sortie

- patch_size:

  Taille des patches en pixels (defaut: 250)

- resolution:

  Resolution en metres (defaut: 0.2)

- val_ratio:

  Proportion de patches pour la validation (defaut: 0.15)

- min_forest_pct:

  Pourcentage minimum de foret pour garder un patch (defaut: 10)

## Value

Liste avec le nombre de patches train et val
