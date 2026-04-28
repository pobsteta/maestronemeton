# Construire le nom de couche WMS IGN selon le millesime

Construire le nom de couche WMS IGN selon le millesime

## Usage

``` r
ign_layer_name(type = c("ortho", "irc"), millesime = NULL)
```

## Arguments

- type:

  `"ortho"` ou `"irc"`

- millesime:

  `NULL` (mosaique la plus recente) ou entier (ex: 2023)

## Value

Nom de couche WMS (character)

## Examples

``` r
ign_layer_name("ortho")
#> [1] "ORTHOIMAGERY.ORTHOPHOTOS"
ign_layer_name("irc", 2023)
#> [1] "ORTHOIMAGERY.ORTHOPHOTOS.IRC.2023"
```
