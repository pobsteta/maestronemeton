# Modeles FLAIR-HUB pre-entraines disponibles

Catalogue des modeles pre-entraines pour la segmentation d'occupation du
sol. Les modeles sont heberges sur HuggingFace par l'IGNF.

## Usage

``` r
flair_models()
```

## Value

Un data.frame avec les colonnes id, architecture, encoder, decoder,
n_bands, supervision, miou

## Examples

``` r
mods <- flair_models()
mods[mods$miou > 60, ]
#>                                              id       architecture
#> 3 IGNF/FLAIR-HUB_LC-A_IR_convnextv2tiny-upernet ConvNeXTV2-UPerNet
#>           encoder decoder n_bands supervision miou
#> 3 convnextv2_tiny upernet       4  cosia_19cl 64.1
#>                        description
#> 3 FLAIR-HUB multimodal (aerial IR)
```
