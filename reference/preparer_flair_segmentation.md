# Preparer les patches FLAIR-HUB pour l'entrainement du decodeur

Organise les patches FLAIR-HUB existants (deja labellises avec
[`labelliser_flair_bdforet()`](https://pobsteta.github.io/maestronemeton/reference/labelliser_flair_bdforet.md))
en structure train/val attendue par `train_segmentation.py`. Les patches
avec moins de `min_forest_pct`% de foret sont exclus.

## Usage

``` r
preparer_flair_segmentation(
  flair_dir = "data/flair_hub",
  output_dir = "data/segmentation",
  modalites = c("aerial", "dem"),
  val_ratio = 0.15,
  min_forest_pct = 10,
  domaines = NULL,
  max_patches = NULL
)
```

## Arguments

- flair_dir:

  Repertoire racine FLAIR-HUB contenant aerial/, dem/, labels_ndp0/
  (issu de
  [`labelliser_flair_bdforet()`](https://pobsteta.github.io/maestronemeton/reference/labelliser_flair_bdforet.md))

- output_dir:

  Repertoire de sortie pour les patches reorganises

- modalites:

  Vecteur des modalites a inclure (defaut: `c("aerial", "dem")`)

- val_ratio:

  Proportion de patches pour la validation (defaut: 0.15)

- min_forest_pct:

  Pourcentage minimum de foret pour garder un patch (defaut: 10)

- domaines:

  Vecteur de domaines a utiliser (`NULL` = tous)

- max_patches:

  Nombre maximum de patches a utiliser (`NULL` = tous)

## Value

Liste avec n_train, n_val, n_skipped

## Details

Structure de sortie :

    output_dir/
      train/
        aerial/   patch_00001.tif, ...
        dem/      patch_00001.tif, ...
        labels/   patch_00001.tif, ...
      val/
        aerial/   ...
        dem/      ...
        labels/   ...
