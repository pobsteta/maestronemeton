# Telecharger un modele FLAIR pre-entraine depuis HuggingFace

Telecharger un modele FLAIR pre-entraine depuis HuggingFace

## Usage

``` r
telecharger_modele_flair(
  model_id = "IGNF/FLAIR-INC_rgbi_15cl_resnet34-unet",
  token = NULL
)
```

## Arguments

- model_id:

  Identifiant HuggingFace du modele (defaut:
  "IGNF/FLAIR-INC_rgbi_15cl_resnet34-unet")

- token:

  Token HuggingFace (optionnel)

## Value

Liste avec `weights` (chemin des poids) et `config` (configuration)
