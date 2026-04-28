# Lister les fichiers d'un dataset HuggingFace

Interroge l'API HuggingFace pour lister les fichiers disponibles dans un
dataset (ou sous-ensemble).

## Usage

``` r
hf_list_files(repo_id, path = NULL, token = NULL)
```

## Arguments

- repo_id:

  Identifiant du repository HuggingFace (ex: "IGNF/FLAIR-HUB")

- path:

  Sous-chemin optionnel pour filtrer

- token:

  Token HuggingFace (optionnel, pour les repos prives)

## Value

Vecteur de noms de fichiers
