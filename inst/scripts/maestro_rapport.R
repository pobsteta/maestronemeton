#!/usr/bin/env Rscript
# =============================================================================
# maestro_rapport.R
# Pipeline complet MAESTRO : telechargement, inference, carte des essences
# et generation du rapport graphique PDF avec terra::plot (pattern FLAIR-HUB).
#
# Utilisation dans RStudio (rapport sans inference) :
#   source("inst/scripts/maestro_rapport.R")
#
# Avec inference (necessite Python + PyTorch) :
#   lancer_inference <- TRUE; source("inst/scripts/maestro_rapport.R")
#
# En ligne de commande :
#   Rscript inst/scripts/maestro_rapport.R --inference
#   Rscript inst/scripts/maestro_rapport.R --inference --gpu
#   Rscript inst/scripts/maestro_rapport.R --millesime 2023
#   Rscript inst/scripts/maestro_rapport.R --checkpoint outputs/training/maestro_pureforest_best.pt
# =============================================================================

# --- Packages requis ---
pkgs_requis <- c("sf", "terra", "fs")
for (pkg in pkgs_requis) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop(sprintf("Package '%s' requis. Installez-le avec : install.packages('%s')", pkg, pkg))
  }
}

library(sf)
library(terra)
library(fs)

# --- Charger le package maestronemeton ---
if (requireNamespace("maestronemeton"emeton", quietly = TRUE)) {
  library(maestronemeton)
} else if (requireNamespace("devtools", quietly = TRUE)) {
  devtools::load_all(".")
} else {
  stop("Le package 'maestronemeton' n'est pas installe.")
}

# =============================================================================
# Configuration : palettes et labels (pattern FLAIR-HUB)
# =============================================================================

# Palette de couleurs pour les 13 essences PureForest
ESSENCES_COLORS_PUREFOREST <- c(
  "#2ca02c",   # 0  Chene decidue  - vert fonce
  "#98df8a",   # 1  Chene vert     - vert clair
  "#ff7f0e",   # 2  Hetre          - orange
  "#d62728",   # 3  Chataignier    - rouge
  "#1f77b4",   # 4  Pin maritime   - bleu
  "#aec7e8",   # 5  Pin sylvestre  - bleu clair
  "#9467bd",   # 6  Pin laricio/noir - violet
  "#c5b0d5",   # 7  Pin d'Alep     - violet clair
  "#17becf",   # 8  Epicea         - cyan
  "#006400",   # 9  Sapin          - vert sapin
  "#8c564b",   # 10 Douglas        - brun
  "#e377c2",   # 11 Meleze         - rose
  "#bcbd22"    # 12 Peuplier       - jaune-vert
)

ESSENCES_LABELS_PUREFOREST <- c(
  "Chene decidue", "Chene vert", "Hetre", "Chataignier",
  "Pin maritime", "Pin sylvestre", "Pin laricio/noir", "Pin d'Alep",
  "Epicea", "Sapin", "Douglas", "Meleze", "Peuplier"
)

# Palette de couleurs pour les 8 classes TreeSatAI
ESSENCES_COLORS_TREESATAI <- c(
  "#2ca02c",   # 0  Chenes         - vert fonce
  "#ff7f0e",   # 1  Hetre          - orange
  "#d62728",   # 2  Autres feuillus - rouge
  "#1f77b4",   # 3  Pins           - bleu
  "#17becf",   # 4  Epicea/Sapin   - cyan
  "#8c564b",   # 5  Douglas        - brun
  "#e377c2",   # 6  Meleze         - rose
  "#bdbdbd"    # 7  Cleared        - gris
)

ESSENCES_LABELS_TREESATAI <- c(
  "Chenes", "Hetre", "Autres feuillus", "Pins",
  "Epicea/Sapin", "Douglas", "Meleze", "Cleared"
)

# Variables actives (selectionnees selon le mode)
ESSENCES_COLORS <- ESSENCES_COLORS_PUREFOREST
ESSENCES_LABELS <- ESSENCES_LABELS_PUREFOREST
# =============================================================================
# Fonctions de visualisation (pattern FLAIR-HUB : terra base R)
# =============================================================================

#' Visualiser une image en couleurs naturelles (RGB)
#'
#' @param raster_rgb SpatRaster avec au moins 3 bandes
#' @param title Titre du graphique
#' @param bands Indices des bandes RGB
plot_rgb <- function(raster_rgb, title = "Image RGB", bands = c(1, 2, 3)) {
  if (nlyr(raster_rgb) >= 3) {
    plotRGB(raster_rgb, r = bands[1], g = bands[2], b = bands[3],
            stretch = "lin", main = title, mar = c(2, 2, 3, 2))
  } else {
    plot(raster_rgb, main = title)
  }
}

#' Visualiser le NDVI
#'
#' @param ndvi_raster SpatRaster du NDVI
#' @param title Titre
plot_ndvi <- function(ndvi_raster, title = "NDVI") {
  col_ndvi <- colorRampPalette(
    c("#d73027", "#fc8d59", "#fee08b", "#ffffbf",
      "#d9ef8b", "#91cf60", "#1a9850", "#006837")
  )(100)

  plot(ndvi_raster, main = title, col = col_ndvi, range = c(-0.2, 1),
       plg = list(title = "NDVI"))
}

#' Visualiser le MNT (DSM/DTM)
#'
#' @param dem_raster SpatRaster
#' @param title Titre
plot_mnt <- function(dem_raster, title = "MNT") {
  col_elev <- colorRampPalette(
    c("#313695", "#4575b4", "#74add1", "#abd9e9",
      "#e0f3f8", "#ffffbf", "#fee090", "#fdae61",
      "#f46d43", "#d73027", "#a50026")
  )(100)

  plot(dem_raster, main = title, col = col_elev,
       plg = list(title = "Altitude (m)"))
}

#' Visualiser la carte des essences forestieres
#'
#' @param label_raster SpatRaster des classes d'essences
#' @param title Titre
plot_essences <- function(label_raster, title = "Essences forestieres") {
  vals <- values(label_raster, na.rm = TRUE)
  present_classes <- sort(unique(as.integer(vals)))

  colors <- ESSENCES_COLORS[present_classes + 1]
  labels <- ESSENCES_LABELS[present_classes + 1]

  # Reclasser le raster pour n'avoir que les classes presentes (0..n-1)
  rcl <- cbind(present_classes, seq_along(present_classes))
  r_reclass <- classify(label_raster, rcl)

  plot(r_reclass, main = title, col = colors,
       type = "classes", levels = labels,
       plg = list(legend = labels, cex = 0.7))
}

#' Calculer le NDVI depuis une image RGBI
#'
#' NDVI = (PIR - Rouge) / (PIR + Rouge)
#'
#' @param rgbi_raster SpatRaster avec bandes Rouge (1) et PIR (4)
#' @return SpatRaster du NDVI (valeurs entre -1 et 1)
compute_ndvi <- function(rgbi_raster) {
  pir <- rgbi_raster[[4]]
  rouge <- rgbi_raster[[1]]
  ndvi <- (pir - rouge) / (pir + rouge + 1e-10)
  names(ndvi) <- "NDVI"

  vals <- values(ndvi, na.rm = TRUE)
  message(sprintf("NDVI calcule: min=%.3f, max=%.3f, moy=%.3f",
                   min(vals), max(vals), mean(vals)))
  return(ndvi)
}

#' Statistiques de repartition des essences
#'
#' @param label_raster SpatRaster des classes d'essences
#' @return data.frame avec distribution des classes
compute_essences_stats <- function(label_raster) {
  vals <- values(label_raster, na.rm = TRUE)
  total <- length(vals)

  class_counts <- table(as.integer(vals))
  class_ids <- as.integer(names(class_counts))

  stats <- data.frame(
    class_id = class_ids,
    label = ESSENCES_LABELS[class_ids + 1],
    n_pixels = as.integer(class_counts),
    pct = round(as.numeric(class_counts) / total * 100, 2),
    stringsAsFactors = FALSE
  )

  stats <- stats[order(-stats$pct), ]

  message("=== Distribution des essences forestieres ===")
  message(sprintf("  Total: %d pixels", total))
  for (i in seq_len(min(nrow(stats), 13))) {
    message(sprintf("  %2d. %s: %.1f%%",
                     stats$class_id[i], stats$label[i], stats$pct[i]))
  }

  return(stats)
}

#' Creer un masque de vegetation a partir du NDVI
#'
#' @param ndvi_raster SpatRaster du NDVI
#' @param threshold Seuil NDVI pour considerer de la vegetation
#' @return SpatRaster binaire (1 = vegetation)
mask_vegetation <- function(ndvi_raster, threshold = 0.3) {
  veg_mask <- ndvi_raster >= threshold
  names(veg_mask) <- "vegetation"

  pct <- sum(values(veg_mask, na.rm = TRUE)) / sum(!is.na(values(veg_mask))) * 100
  message(sprintf("Vegetation detectee (NDVI >= %.2f): %.1f%%", threshold, pct))
  return(veg_mask)
}

# =============================================================================
# Arguments
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
millesime <- NULL
utiliser_gpu <- FALSE
aoi_path <- file.path("data", "aoi.gpkg")
output_dir <- "outputs"
if (!exists("checkpoint_path")) checkpoint_path <- NULL

for (i in seq_along(args)) {
  if (args[i] == "--millesime" && i < length(args)) {
    millesime <- as.integer(args[i + 1])
  }
  if (args[i] == "--gpu") utiliser_gpu <- TRUE
  if (args[i] == "--inference") lancer_inference <- TRUE
  if (args[i] == "--aoi" && i < length(args)) aoi_path <- args[i + 1]
  if (args[i] == "--output" && i < length(args)) output_dir <- args[i + 1]
  if (args[i] == "--checkpoint" && i < length(args)) checkpoint_path <- args[i + 1]
}
if (!exists("lancer_inference")) lancer_inference <- FALSE

# Activer le mode TreeSatAI si checkpoint fourni
is_treesatai <- !is.null(checkpoint_path)
if (is_treesatai) {
  ESSENCES_COLORS <- ESSENCES_COLORS_TREESATAI
  ESSENCES_LABELS <- ESSENCES_LABELS_TREESATAI
  lancer_inference <- TRUE
  message("  Mode TreeSatAI (8 classes) avec checkpoint: ", basename(checkpoint_path))
}

dossier_rapport <- file.path(output_dir, "rapport")
dir.create(dossier_rapport, showWarnings = FALSE, recursive = TRUE)

if (!file.exists(aoi_path)) {
  stop("Fichier AOI introuvable : ", aoi_path,
       "\nPlacez votre fichier aoi.gpkg dans le repertoire data/")
}

# =============================================================================
# ETAPE 1 : Pipeline MAESTRO (telechargement + inference)
# =============================================================================

message("\n========================================================")
message(" MAESTRO - Pipeline complet + Rapport graphique")
message("========================================================\n")

# --- 1a. Charger l'AOI ---
message("=== Chargement de l'AOI ===")
aoi <- load_aoi(aoi_path)
aoi_vect <- vect(aoi)
bbox <- st_bbox(aoi)
message(sprintf("  AOI : %s", basename(aoi_path)))
message(sprintf("  Emprise : %.0f x %.0f m",
                bbox["xmax"] - bbox["xmin"], bbox["ymax"] - bbox["ymin"]))

# --- 1b. Telecharger ortho RVB + IRC ---
message("\n=== Telechargement ortho RVB + IRC ===")
message(sprintf("  Millesime : %s",
                if (is.null(millesime)) "plus recent (defaut)" else millesime))

ortho <- download_ortho_for_aoi(aoi, output_dir,
                                 millesime_ortho = millesime,
                                 millesime_irc = millesime)

# --- 1c. Combiner RVB + IRC -> RGBI ---
message("\n=== Combinaison RVB + IRC -> RGBI ===")
rgbi <- combine_rvb_irc(ortho$rvb, ortho$irc)

# --- 1d. Telecharger DEM (DSM + DTM, 2 bandes) pour le rapport ---
message("\n=== Telechargement DEM (DSM + DTM) ===")
dem_data <- prepare_dem(aoi, output_dir, rgbi = rgbi, source = "wms")

# --- 1e. Image RGBI (modalite aerial MAESTRO) ---
# Le DEM n'est PAS empile a RGBI : MAESTRO traite les modalites separement.
image_finale <- rgbi
n_bands <- terra::nlyr(rgbi)

finale_path <- file.path(output_dir, "image_finale.tif")
writeRaster(image_finale, finale_path, overwrite = TRUE, gdal = c("COMPRESS=LZW"))
message(sprintf("  Aerial RGBI : %s (%d bandes)", finale_path, n_bands))

# --- 1f. Grille de patches alignee modalite aerial ---
message("\n=== Grille de patches ===")
specs_mod <- modalite_specs()
patch_size <- specs_mod$aerial$image_size
resolution <- specs_mod$aerial$resolution
taille_patch_m <- specs_mod$aerial$window_m
grille <- creer_grille_patches(aoi, taille_patch_m)

# --- 1g. Inference (opt-in avec --inference) ---
inference_ok <- FALSE
resultats <- NULL
raster_carte <- NULL

if (lancer_inference) {
  tryCatch({
    message("\n=== Configuration Python ===")
    configurer_python()

    # Preparer les modalites pour l'inference multi-modale
    modalites_inf <- list(aerial = rgbi)
    modalites_noms <- c("aerial")
    if (!is.null(dem_data)) {
      dem <- aligner_dem_sur_rgbi(dem_data$dem, rgbi)
      modalites_inf$dem <- dem
      modalites_noms <- c(modalites_noms, "dem")
    }

    # Si checkpoint fine-tune, filtrer les modalites selon celles entrainees
    if (is_treesatai) {
      torch <- reticulate::import("torch")
      ckpt <- torch$load(checkpoint_path, map_location = "cpu")
      ckpt_modalites <- if (!is.null(ckpt$modalites)) {
        unlist(ckpt$modalites)
      } else {
        c("aerial")
      }
      message(sprintf("  Modalites du checkpoint: %s",
                       paste(ckpt_modalites, collapse = " + ")))
      modalites_noms <- intersect(modalites_noms, ckpt_modalites)
      modalites_inf <- modalites_inf[modalites_noms]
      message(sprintf("  Modalites retenues: %s",
                       paste(modalites_noms, collapse = " + ")))
    }

    message("\n=== Extraction des patches (multi-modal) ===")
    patches_multimodal <- extraire_patches_multimodal(modalites_inf, grille, patch_size)

    if (is_treesatai) {
      message("\n=== Inference MAESTRO TreeSatAI (8 classes) ===")
      predictions <- executer_inference_multimodal(
        patches_multimodal, fichiers_modele = NULL,
        modalites = modalites_noms,
        utiliser_gpu = utiliser_gpu,
        checkpoint = checkpoint_path
      )
      essences_table <- essences_treesatai()
    } else {
      message("\n=== Telechargement du modele ===")
      fichiers_modele <- telecharger_modele("IGNF/MAESTRO_FLAIR-HUB_base")

      message("\n=== Inference MAESTRO PureForest (13 classes) ===")
      predictions <- executer_inference_multimodal(
        patches_multimodal, fichiers_modele,
        n_classes = 13L,
        modalites = modalites_noms,
        utiliser_gpu = utiliser_gpu
      )
      essences_table <- essences_pureforest()
    }

    message("\n=== Assemblage des resultats ===")
    resultats <- assembler_resultats(grille, predictions,
                                      essences = essences_table,
                                      dossier_sortie = output_dir)
    raster_carte <- creer_carte_raster(resultats, resolution, output_dir)
    inference_ok <- TRUE

  }, error = function(e) {
    message("\nErreur lors de l'inference: ", e$message)
    message("Installation :")
    message("  conda create -n maestro python=3.10")
    message("  conda activate maestro")
    message("  pip install torch numpy safetensors")
    message("\nLe rapport sera genere sans la carte des essences.")
  })
} else {
  message("\n=== Inference non demandee ===")
  message("  Pour lancer l'inference, utilisez le flag --inference")
  message("  ou definissez lancer_inference <- TRUE avant de sourcer le script")
}

# =============================================================================
# ETAPE 2 : Calculs d'indices spectraux
# =============================================================================

message("\n========================================================")
message(" CALCUL DES INDICES SPECTRAUX")
message("========================================================\n")

# NDVI
ndvi <- compute_ndvi(image_finale)

# Masque vegetation
veg_mask <- mask_vegetation(ndvi)

# MNT
mnt_raster <- if (!is.null(mnt_data)) mnt_data$mnt else image_finale[[n_bands]]

# =============================================================================
# ETAPE 3 : Generation du rapport PDF (pattern FLAIR-HUB : terra base R)
# =============================================================================

message("\n========================================================")
message(" GENERATION DU RAPPORT GRAPHIQUE")
message("========================================================\n")

pdf_path <- file.path(dossier_rapport, "rapport_maestro.pdf")
pdf(pdf_path, width = 16, height = 12)

# --- Page 1 : Comparaison multi-modalites ---
message("  Page 1/3 : Donnees d'entree...")

par(mfrow = c(2, 3), mar = c(2, 2, 3, 4),
    oma = c(0, 0, 3, 0))

# 1. Orthophoto RVB
plot_rgb(ortho$rvb, title = sprintf("Orthophoto RVB (%.1f m)", res(ortho$rvb)[1]))
lines(aoi_vect, col = "red", lwd = 2)

# 2. Infrarouge couleur (IRC)
plot_rgb(ortho$irc, title = sprintf("Infrarouge couleur IRC (%.1f m)", res(ortho$irc)[1]))
lines(aoi_vect, col = "yellow", lwd = 2)

# 3. MNT
plot_mnt(mnt_raster, title = "Modele Numerique de Terrain")
lines(aoi_vect, col = "black", lwd = 2)

# 4. NDVI
plot_ndvi(ndvi, title = "Indice de vegetation (NDVI)")
lines(aoi_vect, col = "black", lwd = 2)

# 5. Masque vegetation
plot(veg_mask, main = "Vegetation (NDVI >= 0.3)",
     col = c("white", "#1a9850"), legend = FALSE)
lines(aoi_vect, col = "black", lwd = 2)
legend("bottomright", legend = c("Non-veg", "Vegetation"),
       fill = c("white", "#1a9850"), cex = 0.8)

# 6. Grille de patches
plotRGB(ortho$rvb, r = 1, g = 2, b = 3, stretch = "lin",
        main = sprintf("Grille de patches (%d x %g m)", nrow(grille), taille_patch_m))
lines(vect(grille), col = "blue", lwd = 0.5)
lines(aoi_vect, col = "red", lwd = 2)

mtext("MAESTRO - Donnees d'entree", outer = TRUE, cex = 1.5, font = 2)
mtext(sprintf("AOI : %s | Date : %s | Emprise : %.0f x %.0f m",
              basename(aoi_path), Sys.Date(),
              bbox["xmax"] - bbox["xmin"], bbox["ymax"] - bbox["ymin"]),
      outer = TRUE, line = -1, cex = 0.9, col = "grey30")

# --- Page 2 : Carte des essences ---
message("  Page 2/3 : Carte des essences...")

if (inference_ok && !is.null(raster_carte)) {
  par(mfrow = c(1, 1), mar = c(2, 2, 4, 6), oma = c(0, 0, 2, 0))

  plot_essences(raster_carte,
                title = sprintf("Carte des essences forestieres - %d patches classifies",
                                nrow(grille)))
  lines(aoi_vect, col = "black", lwd = 2)

  mtext("MAESTRO - Reconnaissance des essences", outer = TRUE, cex = 1.5, font = 2)

} else {
  par(mfrow = c(1, 1), mar = c(2, 2, 4, 2), oma = c(0, 0, 2, 0))

  # Afficher l'ortho en fond avec la grille
  plotRGB(ortho$rvb, r = 1, g = 2, b = 3, stretch = "lin",
          main = "Carte des essences forestieres")
  lines(vect(grille), col = "grey60", lwd = 0.3)
  lines(aoi_vect, col = "red", lwd = 2)

  # Message central
  mid_x <- mean(c(bbox["xmin"], bbox["xmax"]))
  mid_y <- mean(c(bbox["ymin"], bbox["ymax"]))
  text(mid_x, mid_y, "Inference non executee\n(utilisez --inference)",
       cex = 1.5, col = "red", font = 2)

  mtext("MAESTRO - En attente d'inference", outer = TRUE, cex = 1.5, font = 2)
}

# --- Page 3 : Statistiques ---
message("  Page 3/3 : Statistiques...")

if (inference_ok && !is.null(raster_carte)) {
  par(mfrow = c(1, 1), mar = c(5, 12, 4, 2), oma = c(0, 0, 2, 0))

  stats <- compute_essences_stats(raster_carte)

  barplot(stats$pct,
          names.arg = stats$label,
          horiz = TRUE,
          las = 1,
          col = ESSENCES_COLORS[stats$class_id + 1],
          main = sprintf("Repartition des essences (%d especes detectees)", nrow(stats)),
          xlab = "Proportion (%)",
          cex.names = 0.8)

  # Ajouter les pourcentages
  text(stats$pct + 0.5, seq_along(stats$pct) * 1.2 - 0.5,
       sprintf("%.1f%%", stats$pct), cex = 0.7, pos = 4)

  mtext("MAESTRO - Statistiques", outer = TRUE, cex = 1.5, font = 2)

} else {
  par(mfrow = c(1, 1), mar = c(2, 2, 4, 2), oma = c(0, 0, 2, 0))

  # Resume textuel du pipeline
  ess <- if (is_treesatai) essences_treesatai() else essences_pureforest()
  fichiers <- dir_ls(output_dir, type = "file", glob = "*.tif")
  info_lines <- sapply(fichiers, function(f) {
    sz <- file.info(f)$size
    taille <- if (sz > 1e6) sprintf("%.1f Mo", sz / 1e6) else sprintf("%.0f Ko", sz / 1e3)
    sprintf("  %s  (%s)", basename(f), taille)
  })

  resume <- c(
    "MAESTRO - Resume du pipeline",
    "==============================",
    "",
    sprintf("AOI : %s", basename(aoi_path)),
    sprintf("CRS : EPSG:2154 (Lambert-93)"),
    sprintf("Emprise : %.0f x %.0f m",
            bbox["xmax"] - bbox["xmin"], bbox["ymax"] - bbox["ymin"]),
    sprintf("Resolution : %.1f m", res(ortho$rvb)[1]),
    sprintf("Image finale : %d bandes (%s)", nlyr(image_finale),
            paste(names(image_finale), collapse = ", ")),
    sprintf("Patches : %d", nrow(grille)),
    sprintf("Especes : %d classes %s", nrow(ess),
            if (is_treesatai) "TreeSatAI" else "PureForest"),
    "",
    "--- Fichiers generes ---",
    info_lines,
    "",
    "--- Inference ---",
    "Non executee (PyTorch requis)",
    "Relancez avec --inference"
  )

  plot.new()
  title(main = "Resume du pipeline", font.main = 2, cex.main = 1.4)
  text(0.05, seq(0.95, by = -0.04, length.out = length(resume)),
       resume, adj = 0, family = "mono", cex = 0.9)

  mtext("MAESTRO - Resume", outer = TRUE, cex = 1.5, font = 2)
}

dev.off()
message(sprintf("  PDF : %s (%.1f Mo)", pdf_path, file.info(pdf_path)$size / 1e6))

# --- Export PNG (page 1 uniquement) ---
message("\nExport PNG de la page principale...")
png_path <- file.path(dossier_rapport, "rapport_maestro.png")
png(png_path, width = 1600, height = 1200, res = 100)

par(mfrow = c(2, 3), mar = c(2, 2, 3, 4),
    oma = c(0, 0, 3, 0))

plot_rgb(ortho$rvb, title = sprintf("Orthophoto RVB (%.1f m)", res(ortho$rvb)[1]))
lines(aoi_vect, col = "red", lwd = 2)

plot_rgb(ortho$irc, title = sprintf("IRC (%.1f m)", res(ortho$irc)[1]))
lines(aoi_vect, col = "yellow", lwd = 2)

plot_mnt(mnt_raster, title = "MNT")
lines(aoi_vect, col = "black", lwd = 2)

plot_ndvi(ndvi, title = "NDVI")
lines(aoi_vect, col = "black", lwd = 2)

plot(veg_mask, main = "Vegetation (NDVI >= 0.3)",
     col = c("white", "#1a9850"), legend = FALSE)
lines(aoi_vect, col = "black", lwd = 2)

if (inference_ok && !is.null(raster_carte)) {
  plot_essences(raster_carte, title = "Essences forestieres")
  lines(aoi_vect, col = "black", lwd = 2)
} else {
  plotRGB(ortho$rvb, r = 1, g = 2, b = 3, stretch = "lin",
          main = sprintf("Grille (%d patches)", nrow(grille)))
  lines(vect(grille), col = "blue", lwd = 0.5)
  lines(aoi_vect, col = "red", lwd = 2)
}

mtext("MAESTRO - Reconnaissance des essences forestieres", outer = TRUE, cex = 1.5, font = 2)
mtext(sprintf("AOI : %s | %s | %d patches de %g m",
              basename(aoi_path), Sys.Date(), nrow(grille), taille_patch_m),
      outer = TRUE, line = -1, cex = 0.9, col = "grey30")

dev.off()
message(sprintf("  PNG : %s (%.1f Mo)", png_path, file.info(png_path)$size / 1e6))

# --- Affichage dans RStudio si interactif ---
if (interactive()) {
  message("\nAffichage dans RStudio...")

  par(mfrow = c(2, 3), mar = c(2, 2, 3, 4),
      oma = c(0, 0, 3, 0))

  plot_rgb(ortho$rvb, title = "Orthophoto RVB")
  lines(aoi_vect, col = "red", lwd = 2)

  plot_rgb(ortho$irc, title = "IRC")
  lines(aoi_vect, col = "yellow", lwd = 2)

  plot_mnt(mnt_raster, title = "MNT")
  lines(aoi_vect, col = "black", lwd = 2)

  plot_ndvi(ndvi, title = "NDVI")
  lines(aoi_vect, col = "black", lwd = 2)

  plot(veg_mask, main = "Vegetation (NDVI >= 0.3)",
       col = c("white", "#1a9850"), legend = FALSE)
  lines(aoi_vect, col = "black", lwd = 2)

  if (inference_ok && !is.null(raster_carte)) {
    plot_essences(raster_carte, title = "Essences forestieres")
    lines(aoi_vect, col = "black", lwd = 2)
  } else {
    plotRGB(ortho$rvb, r = 1, g = 2, b = 3, stretch = "lin",
            main = sprintf("Grille (%d patches)", nrow(grille)))
    lines(vect(grille), col = "blue", lwd = 0.5)
    lines(aoi_vect, col = "red", lwd = 2)
  }

  mtext("MAESTRO - Reconnaissance des essences forestieres",
        outer = TRUE, cex = 1.5, font = 2)
}

message("\n========================================================")
message(" Rapport termine !")
message(sprintf(" Fichiers dans : %s/", dossier_rapport))
message("========================================================")
