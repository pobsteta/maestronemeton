# Telecharger le modele MAESTRO depuis Hugging Face

Utilise le package R [hfhub](https://cran.r-project.org/package=hfhub)
pour telecharger les poids et la configuration du modele. Les fichiers
sont mis en cache par hfhub et reutilises automatiquement.

## Usage

``` r
telecharger_modele(repo_id = "IGNF/MAESTRO_FLAIR-HUB_base", token = NULL)
```

## Arguments

- repo_id:

  Identifiant du depot HF (ex: `"IGNF/MAESTRO_FLAIR-HUB_base"`)

- token:

  Token Hugging Face (optionnel, ou via `HUGGING_FACE_HUB_TOKEN`)

## Value

Liste avec `config` et `weights` (chemins locaux)
