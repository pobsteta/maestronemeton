# Executer la segmentation dense MAESTRO sur toute l'AOI

Decoupe l'AOI en patches de 50m, execute la segmentation par patch via
le backbone MAESTRO + decodeur, puis reassemble les predictions en une
carte continue a 0.2m de resolution.

## Usage

``` r
executer_segmentation(
  segmenter,
  modalites,
  aoi,
  output_dir = "outputs",
  patch_size = 250L,
  resolution = 0.2,
  overlap_m = 10,
  gpu = FALSE,
  batch_size = 4L
)
```

## Arguments

- segmenter:

  Modele MAESTROSegmenter

- modalites:

  Liste nommee de SpatRasters complets pour l'AOI (ex:
  `list(aerial=rgbi, dem=dem)`)

- aoi:

  sf object en Lambert-93

- output_dir:

  Repertoire de sortie

- patch_size:

  Taille des patches en pixels (defaut: 250)

- resolution:

  Resolution en metres (defaut: 0.2)

- overlap_m:

  Recouvrement entre patches en metres (defaut: 10)

- gpu:

  Utiliser CUDA

- batch_size:

  Taille des batchs (defaut: 4)

## Value

SpatRaster mono-bande avec les codes NDP0 a 0.2m

## Details

Les patches se chevauchent de 10m (overlap) et les zones de recouvrement
sont resolues par vote de la classe avec la probabilite maximale.
