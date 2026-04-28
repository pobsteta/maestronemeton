# Construire les periodes de recherche multi-annuelles

A partir d'un vecteur d'annees et d'une saison, genere les intervalles
de dates a interroger via STAC.

## Usage

``` r
build_date_ranges(annees_sentinel, saison = "ete")
```

## Arguments

- annees_sentinel:

  Vecteur d'annees (ex: 2021:2024)

- saison:

  Saison cible : "ete" (juin-sept), "printemps" (mars-mai), "automne"
  (sept-nov), "annee" (jan-dec), ou vecteur de 2 mois c(debut, fin)

## Value

data.frame avec colonnes `start_date` et `end_date`
