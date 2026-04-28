# Telecharger les domaines FLAIR-HUB recommandes pour la segmentation

Telecharge les patches FLAIR-HUB (aerial + modalites choisies) pour les
domaines recommandes, couvrant une diversite d'essences forestieres.

## Usage

``` r
download_flair_segmentation(
  niveau = "standard",
  modalites = c("aerial", "dem"),
  data_dir = "data/flair_hub",
  token = NULL
)
```

## Arguments

- niveau:

  Niveau de couverture : "minimal", "standard", "complet"

- modalites:

  Modalites a telecharger (defaut: `c("aerial", "dem")`)

- data_dir:

  Repertoire de destination

- token:

  Token HuggingFace (optionnel)

## Value

Vecteur de domaines telecharges
