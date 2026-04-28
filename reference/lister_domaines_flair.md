# Lister les domaines FLAIR-HUB disponibles

Interroge l'API HuggingFace pour lister les domaines geographiques
disponibles dans le dataset FLAIR-HUB. Chaque domaine correspond a un
departement francais + annee (ex: D001_2019 = Ain 2019).

## Usage

``` r
lister_domaines_flair(repo_id = "IGNF/FLAIR-HUB", token = NULL)
```

## Arguments

- repo_id:

  Identifiant du repository HuggingFace

- token:

  Token HuggingFace (optionnel)

## Value

data.frame avec colonnes domaine, departement, annee
