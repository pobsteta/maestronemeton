# Charger le decodeur de segmentation MAESTRO

Charge un backbone MAESTRO pre-entraine et un decodeur de segmentation
sauvegarde pour produire des cartes d'essences a 0.2m de resolution.

## Usage

``` r
charger_segmenter(
  backbone_path,
  decoder_path,
  modalites = c("aerial", "dem"),
  gpu = FALSE
)
```

## Arguments

- backbone_path:

  Chemin vers le checkpoint MAESTRO (.ckpt)

- decoder_path:

  Chemin vers le decodeur de segmentation (.pt)

- modalites:

  Vecteur des modalites a charger

- gpu:

  Utiliser CUDA (defaut: FALSE)

## Value

Modele Python MAESTROSegmenter via reticulate
