# Telecharger un sous-ensemble du dataset FLAIR-HUB

Telecharge le fichier ZIP d'une modalite et d'un domaine specifiques du
dataset FLAIR-HUB depuis HuggingFace, puis le dezippe.

## Usage

``` r
download_flair_subset(
  modalite,
  domaine = NULL,
  data_dir = "data/flair_hub",
  repo_id = "IGNF/FLAIR-HUB",
  token = NULL
)
```

## Arguments

- modalite:

  Modalite a telecharger: "aerial", "dem", "s2", "s1_asc", "s1_des",
  "spot", "labels_cosia", "labels_lpis"

- domaine:

  Identifiant domaine-annee (ex: "D033-2018"). Utiliser
  [`lister_domaines_flair()`](https://pobsteta.github.io/maestronemeton/reference/lister_domaines_flair.md)
  pour voir les domaines disponibles.

- data_dir:

  Repertoire de base pour les donnees

- repo_id:

  Identifiant du repository (defaut: "IGNF/FLAIR-HUB")

- token:

  Token HuggingFace (optionnel)

## Value

Chemin du repertoire contenant les TIF extraits (invisible)

## Details

Les fichiers FLAIR-HUB sont organises en archives ZIP nommees
`data/DXXX-YYYY_MODALITY.zip` (ex: `data/D033-2018_AERIAL_RGBI.zip`).
