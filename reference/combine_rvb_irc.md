# Combiner les ortho RVB et IRC en image 4 bandes RGBI

Les modeles MAESTRO/FLAIR attendent 4 canaux optiques : Rouge, Vert,
Bleu, PIR. L'IRC IGN fournit le PIR en premiere bande.

## Usage

``` r
combine_rvb_irc(rvb, irc)
```

## Arguments

- rvb:

  SpatRaster ortho RVB (3 bandes : Rouge, Vert, Bleu)

- irc:

  SpatRaster ortho IRC (3 bandes : PIR, Rouge, Vert)

## Value

SpatRaster 4 bandes (Rouge, Vert, Bleu, PIR)
