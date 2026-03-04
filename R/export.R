#' Assembler les predictions dans un GeoPackage
#'
#' Joint les predictions de classes aux patches de la grille, produit un
#' fichier GeoPackage et un CSV de statistiques.
#'
#' @param grille sf grille de patches
#' @param predictions Liste de predictions (codes de classes)
#' @param essences Table des essences (issue de [essences_pureforest()])
#' @param dossier_sortie Repertoire de sortie
#' @return sf data.frame enrichi des colonnes `code_essence`, `classe`, etc.
#' @export
assembler_resultats <- function(grille, predictions, essences = NULL,
                                 dossier_sortie = "resultats") {
  message("=== Assemblage des resultats ===")
  dir.create(dossier_sortie, showWarnings = FALSE, recursive = TRUE)

  if (is.null(essences)) essences <- essences_pureforest()

  grille$code_essence <- unlist(predictions)
  grille <- merge(grille, essences, by.x = "code_essence", by.y = "code",
                  all.x = TRUE)

  chemin_gpkg <- file.path(dossier_sortie, "essences_forestieres.gpkg")
  sf::st_write(grille, chemin_gpkg, delete_dsn = TRUE, quiet = TRUE)
  message(sprintf("  GeoPackage : %s", chemin_gpkg))

  # Statistiques
  message("\n=== Statistiques des essences detectees ===")
  stats <- as.data.frame(table(grille$classe))
  names(stats) <- c("Essence", "Nombre_patches")
  stats$Proportion <- round(stats$Nombre_patches /
                              sum(stats$Nombre_patches) * 100, 1)
  stats <- stats[order(-stats$Nombre_patches), ]
  print(stats, row.names = FALSE)

  chemin_csv <- file.path(dossier_sortie, "statistiques_essences.csv")
  write.csv(stats, chemin_csv, row.names = FALSE)
  message(sprintf("  Statistiques CSV : %s", chemin_csv))

  grille
}

#' Creer le raster de classification des essences
#'
#' Rasterise les predictions vectorielles en un GeoTIFF avec les codes
#' d'essences (0 a 12).
#'
#' @param grille sf data.frame avec colonne `code_essence`
#' @param resolution Resolution en metres (defaut: 0.2)
#' @param dossier_sortie Repertoire de sortie
#' @return SpatRaster de classification
#' @export
creer_carte_raster <- function(grille, resolution = 0.2,
                                dossier_sortie = "resultats") {
  message("=== Creation du raster de classification ===")

  bbox <- sf::st_bbox(grille)
  template <- terra::rast(
    xmin = bbox["xmin"], xmax = bbox["xmax"],
    ymin = bbox["ymin"], ymax = bbox["ymax"],
    res = resolution,
    crs = sf::st_crs(grille)$wkt
  )

  raster_classe <- terra::rasterize(terra::vect(grille), template,
                                     field = "code_essence")

  chemin_tif <- file.path(dossier_sortie, "essences_forestieres.tif")
  terra::writeRaster(raster_classe, chemin_tif, overwrite = TRUE)
  message(sprintf("  Raster GeoTIFF : %s", chemin_tif))

  raster_classe
}
