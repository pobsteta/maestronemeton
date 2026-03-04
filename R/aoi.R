#' Charger une zone d'interet depuis un GeoPackage
#'
#' Lit le fichier GeoPackage et reprojette en Lambert-93 (EPSG:2154)
#' si necessaire. Affiche un resume de l'emprise et de la surface.
#'
#' @param gpkg_path Chemin vers le fichier .gpkg
#' @param layer Nom de la couche (NULL = premiere couche)
#' @return sf object en Lambert-93 (EPSG:2154)
#' @export
#' @examples
#' \dontrun{
#' aoi <- load_aoi("ma_zone.gpkg")
#' }
load_aoi <- function(gpkg_path, layer = NULL) {
  if (!file.exists(gpkg_path)) {
    stop("Fichier AOI introuvable: ", gpkg_path)
  }

  layers <- sf::st_layers(gpkg_path)
  message("Couches dans ", basename(gpkg_path), ": ",
          paste(layers$name, collapse = ", "))

  if (is.null(layer)) {
    layer <- layers$name[1]
  }

  aoi <- sf::st_read(gpkg_path, layer = layer, quiet = TRUE)
  message(sprintf("AOI chargee: %d entite(s), CRS: %s",
                   nrow(aoi), sf::st_crs(aoi)$Name))

  # Reprojection en Lambert-93 si necessaire
  if (is.na(sf::st_crs(aoi)$epsg) || sf::st_crs(aoi)$epsg != 2154) {
    message("Reprojection vers Lambert-93 (EPSG:2154)...")
    aoi <- sf::st_transform(aoi, 2154)
  }

  aoi_union <- sf::st_union(aoi)
  bbox <- sf::st_bbox(aoi_union)
  message(sprintf("Emprise Lambert-93: [%.0f, %.0f] - [%.0f, %.0f]",
                   bbox["xmin"], bbox["ymin"], bbox["xmax"], bbox["ymax"]))
  message(sprintf("Surface: %.2f ha",
                   as.numeric(sf::st_area(aoi_union)) / 10000))

  return(aoi)
}
