# Charger un modele FLAIR pour la segmentation

Charge un modele de segmentation semantique FLAIR (ResNet34-UNet ou
ConvNeXTV2-UPerNet) depuis un fichier de poids.

## Usage

``` r
charger_modele_flair(
  chemin_poids,
  n_classes = 19L,
  in_channels = 4L,
  encoder = "resnet34",
  decoder = "unet",
  device = "cpu"
)
```

## Arguments

- chemin_poids:

  Chemin vers le fichier de poids

- n_classes:

  Nombre de classes (19 pour CoSIA, 23 pour LPIS)

- in_channels:

  Nombre de canaux d'entree (4 = RGBI, 5 = RGBI+DEM)

- encoder:

  Architecture encodeur (ex: "resnet34", "convnextv2_nano")

- decoder:

  Architecture decodeur ("unet" ou "upernet")

- device:

  "cpu" ou "cuda"

## Value

Modele Python charge via reticulate
