# Executer la segmentation MAESTRO sur un patch

Predit la carte de segmentation a 0.2m pour un patch multimodal.

## Usage

``` r
.predire_patch_segmentation(segmenter, modalites_data, gpu = FALSE)
```

## Arguments

- segmenter:

  Modele MAESTROSegmenter (issu de
  [`charger_segmenter()`](https://pobsteta.github.io/maestronemeton/reference/charger_segmenter.md))

- modalites_data:

  Liste nommee de SpatRasters par modalite, deja croppes sur l'emprise
  du patch

- gpu:

  Utiliser CUDA

## Value

Liste avec `classes` (matrice 250x250 int) et `probas` (array)
