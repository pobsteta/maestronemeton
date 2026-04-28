# Rechercher des scenes Sentinel-1 via STAC (Planetary Computer)

Recherche des produits Sentinel-1 RTC (Radiometric Terrain Corrected)
sur Microsoft Planetary Computer. Les produits RTC sont deja corriges du
terrain, avec les polarisations VV et VH disponibles en COG.

## Usage

``` r
search_s1_stac(bbox, start_date, end_date, orbit_direction = "both")
```

## Arguments

- bbox:

  Vecteur numerique c(xmin, ymin, xmax, ymax) en WGS84

- start_date:

  Date de debut

- end_date:

  Date de fin

- orbit_direction:

  Direction d'orbite: "ascending", "descending" ou "both"

## Value

Liste avec `scenes` (data.frame) et `items` (items STAC signes), ou NULL
si aucun produit trouve
