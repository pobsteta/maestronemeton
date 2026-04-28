# Executer l'inference FLAIR avec blending Hann

Execute la segmentation semantique sur un raster complet en decoupant en
patches avec overlap et en fusionnant les predictions avec une fenetre
de Hann pour eviter les artefacts de bord.

## Usage

``` r
executer_inference_flair(
  r,
  modele,
  patch_size = 512L,
  overlap = 128L,
  n_classes = 19L,
  utiliser_gpu = FALSE,
  batch_size = 4L
)
```

## Arguments

- r:

  SpatRaster d'entree (RGBI 4 bandes ou RGBI+DEM 5 bandes)

- modele:

  Modele FLAIR charge (issue de
  [`charger_modele_flair()`](https://pobsteta.github.io/maestronemeton/reference/charger_modele_flair.md))

- patch_size:

  Taille des patches (defaut: 512)

- overlap:

  Recouvrement entre patches (defaut: 128)

- n_classes:

  Nombre de classes de sortie (defaut: 19)

- utiliser_gpu:

  Utiliser le GPU CUDA (defaut: FALSE)

- batch_size:

  Taille des batchs (defaut: 4)

## Value

SpatRaster mono-bande avec les classes predites
