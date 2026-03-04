#!/usr/bin/env Rscript
# =============================================================================
# maestro_cli.R
# Interface en ligne de commande pour le package maestro
#
# Utilisation :
#   Rscript maestro_cli.R --aoi data/aoi.gpkg
#   Rscript maestro_cli.R --aoi data/aoi.gpkg --millesime_ortho 2023
# =============================================================================

if (!requireNamespace("optparse", quietly = TRUE)) {
  install.packages("optparse", repos = "https://cloud.r-project.org")
}
if (!requireNamespace("maestro", quietly = TRUE)) {
  stop("Le package 'maestro' n'est pas installe.\n",
       "Installez-le avec : devtools::install() ou R CMD INSTALL .")
}

library(optparse)
library(maestro)

option_list <- list(
  make_option(c("-a", "--aoi"), type = "character", default = "data/aoi.gpkg",
              help = "Chemin vers le fichier GeoPackage de la zone d'interet [default: %default]"),
  make_option(c("-o", "--output"), type = "character", default = "outputs",
              help = "Repertoire de sortie [default: %default]"),
  make_option(c("-m", "--model"), type = "character",
              default = "IGNF/MAESTRO_FLAIR-HUB_base",
              help = "Identifiant du modele Hugging Face [default: %default]"),
  make_option(c("--millesime_ortho"), type = "integer", default = NULL,
              help = "Millesime de l'ortho RVB (NULL = plus recent)"),
  make_option(c("--millesime_irc"), type = "integer", default = NULL,
              help = "Millesime de l'ortho IRC (NULL = plus recent)"),
  make_option(c("-s", "--patch_size"), type = "integer", default = 250L,
              help = "Taille des patches en pixels [default: %default]"),
  make_option(c("--resolution"), type = "double", default = 0.2,
              help = "Resolution spatiale en metres [default: %default]"),
  make_option(c("--gpu"), action = "store_true", default = FALSE,
              help = "Utiliser le GPU (CUDA) si disponible"),
  make_option(c("--token"), type = "character", default = NULL,
              help = "Token Hugging Face (ou variable HUGGING_FACE_HUB_TOKEN)")
)

opt <- parse_args(OptionParser(option_list = option_list))

maestro_pipeline(
  aoi_path        = opt$aoi,
  output_dir      = opt$output,
  model_id        = opt$model,
  millesime_ortho = opt$millesime_ortho,
  millesime_irc   = opt$millesime_irc,
  patch_size      = opt$patch_size,
  resolution      = opt$resolution,
  gpu             = opt$gpu,
  token           = opt$token
)
