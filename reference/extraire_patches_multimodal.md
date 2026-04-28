# Extraire les patches multi-modaux depuis plusieurs SpatRasters

Pour chaque cellule de la grille, extrait une fenetre **centree** sur le
centroide de la cellule, dimensionnee selon la specification de chaque
modalite (cf.
[`modalite_specs()`](https://pobsteta.github.io/maestronemeton/reference/modalite_specs.md)).
Les fenetres Sentinel (60 m) depassent legerement la cellule aerienne
(51,2 m) pour respecter la contrainte multiple de `patch_size.mae=2`.

## Usage

``` r
extraire_patches_multimodal(modalites, grille, specs = modalite_specs())
```

## Arguments

- modalites:

  Liste nommee de SpatRaster, ex.
  `list(aerial = ..., dem = ..., s2 = ...)`

- grille:

  sf grille de patches (issue de
  [`creer_grille_patches()`](https://pobsteta.github.io/maestronemeton/reference/creer_grille_patches.md))

- specs:

  Specifications, defaut
  [`modalite_specs()`](https://pobsteta.github.io/maestronemeton/reference/modalite_specs.md)

## Value

Liste de listes nommees : `patches[[i]]$<mod>` matrice (H\*W, C)

## Details

Le contrat de sortie est compatible avec
[`executer_inference_multimodal()`](https://pobsteta.github.io/maestronemeton/reference/executer_inference_multimodal.md)
: chaque modalite est une matrice (`H*W` lignes, `C` colonnes) au format
produit par
[`terra::values()`](https://rspatial.github.io/terra/reference/values.html).
