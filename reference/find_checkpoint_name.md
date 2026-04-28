# Trouver le nom du fichier checkpoint dans un depot Hugging Face

Interroge l'API Hugging Face pour lister les fichiers du depot et
retourne le fichier de poids le plus probable.

## Usage

``` r
find_checkpoint_name(hf_repo)
```

## Arguments

- hf_repo:

  Identifiant du depot (ex: `"IGNF/MAESTRO_FLAIR-HUB_base"`)

## Value

Nom du fichier checkpoint, ou NULL
