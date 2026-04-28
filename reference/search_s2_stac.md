# Rechercher des scenes Sentinel-2 via STAC (Planetary Computer)

Interroge le catalogue STAC de Microsoft Planetary Computer pour trouver
des scenes Sentinel-2 L2A. Les URLs sont automatiquement signees pour
l'acces aux donnees COG.

## Usage

``` r
search_s2_stac(bbox, start_date, end_date, max_cloud = 30)
```

## Arguments

- bbox:

  Vecteur numerique c(xmin, ymin, xmax, ymax) en WGS84

- start_date:

  Date de debut (format "YYYY-MM-DD")

- end_date:

  Date de fin (format "YYYY-MM-DD")

- max_cloud:

  Couverture nuageuse maximale en % (defaut: 30)

## Value

Liste avec `scenes` (data.frame) et `items` (items STAC signes), ou NULL
si aucune scene trouvee
