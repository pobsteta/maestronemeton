# Creer une grille de patches pour l'inference

Genere une grille reguliere de patches carres couvrant l'AOI. Seuls les
patches qui intersectent l'AOI sont conserves.

## Usage

``` r
creer_grille_patches(aoi, taille_patch_m = 51.2)
```

## Arguments

- aoi:

  sf object en Lambert-93

- taille_patch_m:

  Taille des patches en metres (defaut: 51.2 m, correspond a aerial 256
  px @ 0,2 m)

## Value

sf data.frame (grille de patches avec colonne `id`)

## Details

Le pas de la grille doit correspondre a la fenetre physique de la
modalite de reference (typiquement `aerial`). Voir
[`modalite_specs()`](https://pobsteta.github.io/maestronemeton/reference/modalite_specs.md).
