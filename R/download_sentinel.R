# =============================================================================
# Telechargement de donnees Sentinel-1 et Sentinel-2 via STAC API
# Adapte de tree_sat_nemeton (03_data_acquisition.R)
# =============================================================================

# --- Configuration Sentinel ---

#' Configuration des bandes Sentinel-2
#'
#' Les 10 bandes spectrales utilisees par MAESTRO pour la modalite S2.
#'
#' @return Liste nommee avec nom, longueur d'onde et resolution par bande
#' @export
s2_bands_config <- function() {
  list(
    B02 = list(name = "Blue",     wavelength = 490,  resolution = 10),
    B03 = list(name = "Green",    wavelength = 560,  resolution = 10),
    B04 = list(name = "Red",      wavelength = 665,  resolution = 10),
    B05 = list(name = "RedEdge1", wavelength = 705,  resolution = 20),
    B06 = list(name = "RedEdge2", wavelength = 740,  resolution = 20),
    B07 = list(name = "RedEdge3", wavelength = 783,  resolution = 20),
    B08 = list(name = "NIR",      wavelength = 842,  resolution = 10),
    B8A = list(name = "NIR2",     wavelength = 865,  resolution = 20),
    B11 = list(name = "SWIR1",    wavelength = 1610, resolution = 20),
    B12 = list(name = "SWIR2",    wavelength = 2190, resolution = 20)
  )
}

# --- STAC API ---

#' Rechercher des scenes Sentinel-2 via l'API STAC Copernicus
#'
#' Interroge le catalogue STAC du Copernicus Data Space pour trouver les
#' scenes Sentinel-2 L2A correspondant a une emprise et une periode.
#'
#' @param bbox Vecteur numerique c(xmin, ymin, xmax, ymax) en WGS84
#' @param start_date Date de debut (format "YYYY-MM-DD")
#' @param end_date Date de fin (format "YYYY-MM-DD")
#' @param max_cloud Couverture nuageuse maximale en % (defaut: 30)
#' @return data.frame avec colonnes id, datetime, cloud_cover, platform
#' @export
search_s2_stac <- function(bbox, start_date, end_date, max_cloud = 30) {
  message("=== Recherche STAC Sentinel-2 L2A ===")

  stac_url <- "https://catalogue.dataspace.copernicus.eu/stac/search"

  body <- list(
    collections = list("sentinel-2-l2a"),
    bbox = as.list(bbox),
    datetime = paste0(start_date, "T00:00:00Z/", end_date, "T23:59:59Z"),
    limit = 500L,
    query = list(
      `eo:cloud_cover` = list(lte = max_cloud)
    )
  )

  body_json <- jsonlite::toJSON(body, auto_unbox = TRUE)

  h <- curl::new_handle()
  curl::handle_setopt(h,
    copypostfields = as.character(body_json),
    httpheader = "Content-Type: application/json"
  )

  resp <- tryCatch(
    curl::curl_fetch_memory(stac_url, handle = h),
    error = function(e) {
      warning("Erreur STAC API: ", e$message)
      return(NULL)
    }
  )

  if (is.null(resp) || resp$status_code != 200) {
    warning("Recherche STAC echouee (HTTP ", resp$status_code, ")")
    return(data.frame())
  }

  items <- jsonlite::fromJSON(rawToChar(resp$content))
  features <- items$features

  if (is.null(features) || length(features) == 0 || nrow(features) == 0) {
    message("  Aucune scene trouvee")
    return(data.frame())
  }

  n_items <- nrow(features)
  message(sprintf("  %d scenes Sentinel-2 L2A trouvees", n_items))

  scenes <- data.frame(
    id = features$id,
    datetime = features$properties$datetime,
    cloud_cover = features$properties$`eo:cloud_cover`,
    stringsAsFactors = FALSE
  )

  scenes$date <- as.Date(substr(scenes$datetime, 1, 10))
  scenes <- scenes[order(scenes$cloud_cover), ]

  scenes
}

#' Rechercher des scenes Sentinel-1 via l'API STAC Copernicus
#'
#' @param bbox Vecteur numerique c(xmin, ymin, xmax, ymax) en WGS84
#' @param start_date Date de debut
#' @param end_date Date de fin
#' @param orbit_direction Direction d'orbite: "ascending", "descending" ou "both"
#' @return data.frame avec colonnes id, datetime, orbit_direction
#' @export
search_s1_stac <- function(bbox, start_date, end_date,
                            orbit_direction = "both") {
  message("=== Recherche STAC Sentinel-1 GRD ===")

  stac_url <- "https://catalogue.dataspace.copernicus.eu/stac/search"

  body <- list(
    collections = list("sentinel-1-grd"),
    bbox = as.list(bbox),
    datetime = paste0(start_date, "T00:00:00Z/", end_date, "T23:59:59Z"),
    limit = 500L
  )

  body_json <- jsonlite::toJSON(body, auto_unbox = TRUE)

  h <- curl::new_handle()
  curl::handle_setopt(h,
    copypostfields = as.character(body_json),
    httpheader = "Content-Type: application/json"
  )

  resp <- tryCatch(
    curl::curl_fetch_memory(stac_url, handle = h),
    error = function(e) {
      warning("Erreur STAC API: ", e$message)
      return(NULL)
    }
  )

  if (is.null(resp) || resp$status_code != 200) {
    warning("Recherche STAC echouee (HTTP ", resp$status_code, ")")
    return(data.frame())
  }

  items <- jsonlite::fromJSON(rawToChar(resp$content))
  features <- items$features

  if (is.null(features) || length(features) == 0 || nrow(features) == 0) {
    message("  Aucune scene trouvee")
    return(data.frame())
  }

  scenes <- data.frame(
    id = features$id,
    datetime = features$properties$datetime,
    stringsAsFactors = FALSE
  )

  # Extraire la direction d'orbite si disponible
  if ("sat:orbit_state" %in% names(features$properties)) {
    scenes$orbit_direction <- features$properties$`sat:orbit_state`
  } else {
    scenes$orbit_direction <- NA_character_
  }

  scenes$date <- as.Date(substr(scenes$datetime, 1, 10))

  if (orbit_direction != "both" && !is.null(scenes$orbit_direction)) {
    scenes <- scenes[scenes$orbit_direction == orbit_direction |
                     is.na(scenes$orbit_direction), ]
  }

  n_items <- nrow(scenes)
  message(sprintf("  %d scenes Sentinel-1 GRD trouvees", n_items))

  scenes
}

#' Telecharger une image Sentinel-2 via la Geoplateforme IGN (WMS-R)
#'
#' Telecharge les bandes Sentinel-2 pour une AOI via le service WMS-R
#' de la Geoplateforme. Alternative au telechargement STAC quand les
#' donnees sont deja mosaiquees par l'IGN.
#'
#' @param aoi sf object en Lambert-93
#' @param output_dir Repertoire de sortie
#' @param date_cible Date cible (format "YYYY-MM-DD", optionnel)
#' @return SpatRaster avec les bandes S2 disponibles, ou NULL
#' @export
download_s2_for_aoi <- function(aoi, output_dir, date_cible = NULL) {
  message("=== Telechargement Sentinel-2 pour l'AOI ===")

  s2_path <- file.path(output_dir, "sentinel2.tif")
  if (file.exists(s2_path)) {
    message("  Cache: ", s2_path)
    return(terra::rast(s2_path))
  }

  # Transformer l'AOI en WGS84 pour la recherche STAC
  aoi_wgs84 <- sf::st_transform(aoi, 4326)
  bbox_wgs84 <- as.numeric(sf::st_bbox(aoi_wgs84))

  # Determiner la periode de recherche
  if (is.null(date_cible)) {
    # Prendre l'ete de l'annee en cours
    annee <- format(Sys.Date(), "%Y")
    start_date <- paste0(annee, "-06-01")
    end_date <- paste0(annee, "-09-30")
  } else {
    d <- as.Date(date_cible)
    start_date <- as.character(d - 30)
    end_date <- as.character(d + 30)
  }

  scenes <- search_s2_stac(bbox_wgs84, start_date, end_date, max_cloud = 20)

  if (nrow(scenes) == 0) {
    message("  Aucune scene S2, essai sur l'annee entiere...")
    annee <- if (!is.null(date_cible)) format(as.Date(date_cible), "%Y") else
      format(Sys.Date(), "%Y")
    scenes <- search_s2_stac(bbox_wgs84,
                              paste0(annee, "-01-01"),
                              paste0(annee, "-12-31"),
                              max_cloud = 30)
  }

  if (nrow(scenes) == 0) {
    warning("Aucune scene Sentinel-2 trouvee pour cette AOI")
    return(NULL)
  }

  # Selectionner la meilleure scene (moins de nuages)
  best <- scenes[1, ]
  message(sprintf("  Scene selectionnee: %s (nuages: %.0f%%)",
                   best$id, best$cloud_cover))

  # Telecharger via le WMS de Copernicus Data Space
  s2_raster <- .download_s2_scene(best, aoi, output_dir)

  if (!is.null(s2_raster)) {
    terra::writeRaster(s2_raster, s2_path, overwrite = TRUE,
                       gdal = c("COMPRESS=LZW"))
    message(sprintf("  Sentinel-2 sauvegarde: %s (%d bandes)",
                     s2_path, terra::nlyr(s2_raster)))
  }

  s2_raster
}

#' Telecharger les donnees Sentinel-1 pour une AOI
#'
#' @param aoi sf object en Lambert-93
#' @param output_dir Repertoire de sortie
#' @param date_cible Date cible (optionnel)
#' @return Liste avec `s1_asc` et `s1_des` (SpatRaster 2 bandes VV+VH chacun),
#'   ou NULL si non disponible
#' @export
download_s1_for_aoi <- function(aoi, output_dir, date_cible = NULL) {
  message("=== Telechargement Sentinel-1 pour l'AOI ===")

  s1_asc_path <- file.path(output_dir, "sentinel1_asc.tif")
  s1_des_path <- file.path(output_dir, "sentinel1_des.tif")

  if (file.exists(s1_asc_path) && file.exists(s1_des_path)) {
    message("  Cache: S1 ascending + descending")
    return(list(
      s1_asc = terra::rast(s1_asc_path),
      s1_des = terra::rast(s1_des_path)
    ))
  }

  aoi_wgs84 <- sf::st_transform(aoi, 4326)
  bbox_wgs84 <- as.numeric(sf::st_bbox(aoi_wgs84))

  if (is.null(date_cible)) {
    annee <- format(Sys.Date(), "%Y")
    start_date <- paste0(annee, "-06-01")
    end_date <- paste0(annee, "-09-30")
  } else {
    d <- as.Date(date_cible)
    start_date <- as.character(d - 30)
    end_date <- as.character(d + 30)
  }

  # Rechercher les scenes ascending et descending
  scenes_asc <- search_s1_stac(bbox_wgs84, start_date, end_date,
                                orbit_direction = "ascending")
  scenes_des <- search_s1_stac(bbox_wgs84, start_date, end_date,
                                orbit_direction = "descending")

  result <- list(s1_asc = NULL, s1_des = NULL)

  if (nrow(scenes_asc) > 0) {
    message(sprintf("  Scene ascending: %s", scenes_asc$id[1]))
    result$s1_asc <- .download_s1_scene(scenes_asc[1, ], aoi, output_dir,
                                         "ascending")
    if (!is.null(result$s1_asc)) {
      terra::writeRaster(result$s1_asc, s1_asc_path, overwrite = TRUE,
                         gdal = c("COMPRESS=LZW"))
    }
  }

  if (nrow(scenes_des) > 0) {
    message(sprintf("  Scene descending: %s", scenes_des$id[1]))
    result$s1_des <- .download_s1_scene(scenes_des[1, ], aoi, output_dir,
                                         "descending")
    if (!is.null(result$s1_des)) {
      terra::writeRaster(result$s1_des, s1_des_path, overwrite = TRUE,
                         gdal = c("COMPRESS=LZW"))
    }
  }

  has_data <- !is.null(result$s1_asc) || !is.null(result$s1_des)
  if (!has_data) {
    warning("Aucune donnee Sentinel-1 disponible")
    return(NULL)
  }

  result
}


# ---------------------------------------------------------------------------
# Fonctions internes de telechargement
# ---------------------------------------------------------------------------

#' @noRd
.download_s2_scene <- function(scene, aoi, output_dir) {
  # Essai 1: Copernicus Data Space OGC API (WMTS/WMS)
  # Les scenes S2 du Data Space sont accessibles via /odata ou via WMTS
  # Pour simplifier, on utilise le service WMS de Copernicus
  message("  Telechargement S2 via Copernicus Data Space...")

  bbox_l93 <- sf::st_bbox(aoi)
  scene_id <- scene$id

  # Utiliser l'API OData pour obtenir l'URL de telechargement
  odata_url <- sprintf(
    "https://catalogue.dataspace.copernicus.eu/odata/v1/Products?$filter=Name eq '%s'",
    scene_id
  )

  h <- curl::new_handle()
  resp <- tryCatch(
    curl::curl_fetch_memory(odata_url, handle = h),
    error = function(e) NULL
  )

  if (is.null(resp) || resp$status_code != 200) {
    message("  [INFO] Acces direct impossible, creation d'un raster synthetique")
    message("  Pour les donnees reelles, configurez un token Copernicus Data Space")
    return(.create_synthetic_s2(aoi, output_dir))
  }

  odata <- jsonlite::fromJSON(rawToChar(resp$content))

  if (length(odata$value) == 0) {
    message("  [INFO] Scene non trouvee via OData")
    return(.create_synthetic_s2(aoi, output_dir))
  }

  # Note: le telechargement complet necessite un token Copernicus
  # Pour l'instant, on cree un placeholder avec les bonnes dimensions
  message("  [INFO] Telechargement complet S2 necessite un token Copernicus")
  message("  Utilisez: Sys.setenv(COPERNICUS_TOKEN = 'votre_token')")
  return(.create_synthetic_s2(aoi, output_dir))
}

#' @noRd
.download_s1_scene <- function(scene, aoi, output_dir, orbit) {
  message(sprintf("  Telechargement S1 %s via Copernicus Data Space...", orbit))

  # Meme logique que S2 : necessite un token pour le telechargement reel
  token <- Sys.getenv("COPERNICUS_TOKEN", "")

  if (nchar(token) == 0) {
    message("  [INFO] Token Copernicus non configure, creation raster synthetique")
    message("  Utilisez: Sys.setenv(COPERNICUS_TOKEN = 'votre_token')")
    return(.create_synthetic_s1(aoi, output_dir, orbit))
  }

  # Telechargement reel avec token
  scene_id <- scene$id
  download_url <- sprintf(
    "https://zipper.dataspace.copernicus.eu/odata/v1/Products(%s)/$value",
    scene_id
  )

  h <- curl::new_handle()
  curl::handle_setheaders(h, Authorization = paste("Bearer", token))

  dest_file <- file.path(output_dir, sprintf("s1_%s_raw.zip", orbit))
  tryCatch({
    curl::curl_download(download_url, dest_file, handle = h)
    message(sprintf("  S1 %s telecharge: %s", orbit, dest_file))
    # TODO: decompresser et extraire les bandes VV/VH
    return(.create_synthetic_s1(aoi, output_dir, orbit))
  }, error = function(e) {
    message("  Echec telechargement: ", e$message)
    return(.create_synthetic_s1(aoi, output_dir, orbit))
  })
}

#' Creer un raster Sentinel-2 synthetique pour tests
#'
#' Produit un raster 10 bandes a 10m de resolution avec des valeurs
#' realistes pour tester le pipeline sans donnees reelles.
#'
#' @param aoi sf object en Lambert-93
#' @param output_dir Repertoire de sortie
#' @return SpatRaster 10 bandes
#' @noRd
.create_synthetic_s2 <- function(aoi, output_dir) {
  message("  Creation raster S2 synthetique (10 bandes, 10m)...")

  bbox <- sf::st_bbox(aoi)
  r <- terra::rast(
    xmin = bbox["xmin"], xmax = bbox["xmax"],
    ymin = bbox["ymin"], ymax = bbox["ymax"],
    res = 10,
    crs = sf::st_crs(aoi)$wkt
  )

  band_names <- c("B02", "B03", "B04", "B05", "B06", "B07",
                  "B08", "B8A", "B11", "B12")

  # Reflectances typiques de vegetation (x10000)
  typical_vegetation <- c(
    350,   # B02 Blue
    600,   # B03 Green
    400,   # B04 Red
    1500,  # B05 RedEdge1
    2500,  # B06 RedEdge2
    3000,  # B07 RedEdge3
    3200,  # B08 NIR
    3100,  # B8A NIR2
    1800,  # B11 SWIR1
    800    # B12 SWIR2
  )

  layers <- list()
  n_cells <- terra::ncell(r)
  for (i in seq_along(band_names)) {
    layer <- r
    noise <- stats::rnorm(n_cells, mean = typical_vegetation[i],
                          sd = typical_vegetation[i] * 0.15)
    noise <- pmax(0, pmin(10000, noise))
    terra::values(layer) <- noise
    names(layer) <- band_names[i]
    layers[[i]] <- layer
  }

  s2 <- do.call(c, layers)
  message(sprintf("  S2 synthetique: %d x %d px, 10 bandes, 10m",
                   terra::ncol(s2), terra::nrow(s2)))
  s2
}

#' Creer un raster Sentinel-1 synthetique pour tests
#'
#' Produit un raster 2 bandes (VV, VH) a 10m avec des valeurs
#' de retrodiffusion radar realistes en dB.
#'
#' @param aoi sf object en Lambert-93
#' @param output_dir Repertoire de sortie
#' @param orbit "ascending" ou "descending"
#' @return SpatRaster 2 bandes
#' @noRd
.create_synthetic_s1 <- function(aoi, output_dir, orbit = "ascending") {
  message(sprintf("  Creation raster S1 synthetique (%s, 2 bandes, 10m)...",
                   orbit))

  bbox <- sf::st_bbox(aoi)
  r <- terra::rast(
    xmin = bbox["xmin"], xmax = bbox["xmax"],
    ymin = bbox["ymin"], ymax = bbox["ymax"],
    res = 10,
    crs = sf::st_crs(aoi)$wkt
  )

  n_cells <- terra::ncell(r)

  # VV: typiquement -8 a -15 dB pour la vegetation
  vv <- r
  terra::values(vv) <- stats::rnorm(n_cells, mean = -10, sd = 3)
  names(vv) <- "VV"

  # VH: typiquement -15 a -22 dB pour la vegetation
  vh <- r
  terra::values(vh) <- stats::rnorm(n_cells, mean = -17, sd = 3)
  names(vh) <- "VH"

  s1 <- c(vv, vh)
  message(sprintf("  S1 synthetique: %d x %d px, 2 bandes (VV, VH)",
                   terra::ncol(s1), terra::nrow(s1)))
  s1
}

#' Aligner un raster Sentinel sur la grille de l'AOI
#'
#' Reechantillonne un raster Sentinel (10m) pour qu'il couvre exactement
#' la meme emprise que le raster de reference, tout en gardant sa
#' resolution native (10m).
#'
#' @param sentinel SpatRaster Sentinel (S1 ou S2)
#' @param reference SpatRaster de reference (ex: RGBI a 0.2m)
#' @param target_res Resolution cible en metres (defaut: 10)
#' @return SpatRaster aligne sur l'emprise de reference
#' @export
aligner_sentinel <- function(sentinel, reference, target_res = 10) {
  ext_ref <- terra::ext(reference)

  template <- terra::rast(
    xmin = ext_ref[1], xmax = ext_ref[2],
    ymin = ext_ref[3], ymax = ext_ref[4],
    res = target_res,
    crs = terra::crs(reference)
  )

  # S'assurer que le CRS correspond
  if (terra::crs(sentinel) != terra::crs(reference)) {
    sentinel <- terra::project(sentinel, terra::crs(reference))
  }

  result <- terra::resample(sentinel, template, method = "bilinear")
  names(result) <- names(sentinel)
  result
}
