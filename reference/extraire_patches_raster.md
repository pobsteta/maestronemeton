# Extraire les patches d'un raster unique (mono-modal)

Variante mono-modale de
[`extraire_patches_multimodal()`](https://pobsteta.github.io/maestronemeton/reference/extraire_patches_multimodal.md)
: utilise uniquement la modalite `aerial`. Conservee pour les usages
legers et les tests d'integration.

## Usage

``` r
extraire_patches_raster(r, grille, taille_pixels = 256L)
```

## Arguments

- r:

  SpatRaster multi-bandes (typiquement RGBI 4 bandes)

- grille:

  sf grille de patches

- taille_pixels:

  Taille du patch en pixels (defaut: 256)

## Value

Liste de matrices (H\*W, C)
