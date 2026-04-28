# Telecharger le DEM 2 bandes pour une AOI avec derives terrain

Telecharge le DTM (RGE ALTI 1m) et le DSM (LiDAR HD) depuis la
Geoplateforme IGN via WMS-R, puis calcule les derives morphologiques
(pente, orientation, TPI, TWI) a la resolution native de 1m.

## Usage

``` r
download_dem_for_aoi(aoi, output_dir, dem_channels = c("SLOPE", "TWI"))
```

## Arguments

- aoi:

  sf object en Lambert-93

- output_dir:

  Repertoire de sortie

- dem_channels:

  Vecteur de 2 noms de canaux a utiliser parmi
  `c("DSM", "DTM", "SLOPE", "ASPECT", "TPI", "TWI")`. Defaut:
  `c("SLOPE", "TWI")` (les plus discriminants pour la foret).

## Value

Liste avec `dem` (SpatRaster 2 bandes a 1m), `dem_path`, `dsm_source`,
`dem_channels`, ou NULL si echec

## Details

Le DEM reste a 1m de resolution (50x50 pixels par patch de 50m).
L'utilisateur choisit 2 canaux parmi DSM, DTM, SLOPE, ASPECT, TPI, TWI.
