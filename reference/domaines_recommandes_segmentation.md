# Domaines FLAIR-HUB recommandes pour l'entrainement segmentation

Retourne une selection de domaines couvrant une diversite d'essences
forestieres (chenes, hetres, pins, sapins, douglas, chataigniers, etc.)
repartis sur differentes regions de France.

## Usage

``` r
domaines_recommandes_segmentation(niveau = "standard")
```

## Arguments

- niveau:

  Niveau de couverture : "minimal" (5 domaines, ~500 patches),
  "standard" (10 domaines, ~1000 patches), "complet" (20 domaines, ~2000
  patches)

## Value

Vecteur de noms de domaines
