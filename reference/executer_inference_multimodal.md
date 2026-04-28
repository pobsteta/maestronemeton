# Executer l'inference MAESTRO multi-modale sur des patches

Charge le modele MAESTRO multi-modal et predit la classe d'essence
forestiere pour chaque patch en utilisant toutes les modalites
disponibles.

## Usage

``` r
executer_inference_multimodal(
  patches_multimodal,
  fichiers_modele,
  n_classes = 13L,
  modalites = c("aerial", "dem"),
  utiliser_gpu = FALSE,
  batch_size = 16L,
  checkpoint = NULL
)
```

## Arguments

- patches_multimodal:

  Liste de listes nommees (issue de
  [`extraire_patches_multimodal()`](https://pobsteta.github.io/maestronemeton/reference/extraire_patches_multimodal.md)).
  Chaque element contient les matrices (H\*W x C) par modalite :
  `patches[[i]]$aerial`, `patches[[i]]$dem`

- fichiers_modele:

  Liste avec `config` et `weights` (issue de
  [`telecharger_modele()`](https://pobsteta.github.io/maestronemeton/reference/telecharger_modele.md))

- n_classes:

  Nombre de classes de sortie (defaut: 13 pour PureForest)

- modalites:

  Vecteur des noms de modalites a utiliser (defaut:
  `c("aerial", "dem")`)

- utiliser_gpu:

  Utiliser le GPU CUDA (defaut: FALSE)

- batch_size:

  Taille des batchs pour l'inference (defaut: 16)

- checkpoint:

  Chemin vers un checkpoint fine-tune `*.pt`/`*.ckpt`/ `*.safetensors`.
  Si fourni, charge ce checkpoint plutot que le modele referencee par
  `fichiers_modele$weights`.

## Value

Liste de predictions (codes de classes 0-12)
