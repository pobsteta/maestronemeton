# Executer l'inference MAESTRO sur des patches (single-modal, legacy)

Charge le modele MAESTRO via le module Python et predit la classe
d'essence forestiere pour chaque patch. Version mono-raster (legacy).

## Usage

``` r
executer_inference(
  patches_data,
  fichiers_modele,
  n_classes = 13L,
  n_bands = 5L,
  utiliser_gpu = FALSE,
  batch_size = 16L
)
```

## Arguments

- patches_data:

  Liste de matrices de patches (issue de
  [`extraire_patches_raster()`](https://pobsteta.github.io/maestronemeton/reference/extraire_patches_raster.md))

- fichiers_modele:

  Liste avec `config` et `weights` (issue de
  [`telecharger_modele()`](https://pobsteta.github.io/maestronemeton/reference/telecharger_modele.md))

- n_classes:

  Nombre de classes de sortie (defaut: 13 pour PureForest)

- n_bands:

  Nombre de bandes d'entree (4 = RGBI, 5 = RGBI+MNT)

- utiliser_gpu:

  Utiliser le GPU CUDA (defaut: FALSE)

- batch_size:

  Taille des batchs pour l'inference (defaut: 16)

## Value

Liste de predictions (codes de classes 0-12)
