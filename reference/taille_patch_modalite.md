# Taille de patch par modalite MAESTRO

Wrapper retro-compatible autour de
[`modalite_specs()`](https://pobsteta.github.io/maestronemeton/reference/modalite_specs.md).
Pour de nouveaux developpements, preferer l'acces direct via
`modalite_specs()$<mod>$image_size`.

## Usage

``` r
taille_patch_modalite(mod_name, taille_pixels_ref = 256L)
```

## Arguments

- mod_name:

  Nom de la modalite

- taille_pixels_ref:

  Taille pour aerial/dem si mod_name n'est pas connue

## Value

Entier : nombre de pixels du patch
