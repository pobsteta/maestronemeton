# Evaluer les predictions par rapport a une reference

Calcule les metriques de precision : accuracy globale, mean IoU, et IoU
par classe.

## Usage

``` r
evaluer_predictions(prediction, reference, n_classes = 19L, classes = NULL)
```

## Arguments

- prediction:

  SpatRaster de prediction (classification)

- reference:

  SpatRaster de reference (verite terrain)

- n_classes:

  Nombre de classes (defaut: 19)

- classes:

  Table des classes (optionnel, pour les noms)

## Value

Liste avec `accuracy`, `mean_iou`, `per_class_iou` (data.frame)
