#' Specifications des modalites MAESTRO
#'
#' Table declarative des modalites attendues par le modele
#' `IGNF/MAESTRO_FLAIR-HUB_base`. Chaque entree decrit la forme du patch
#' a fournir au DataLoader / au pipeline d'inference :
#'
#' - `in_channels`    : nombre de canaux pour le `patch_embed` de la modalite ;
#' - `image_size`     : cote du patch en pixels ;
#' - `resolution`     : taille de pixel au sol en metres ;
#' - `patch_size_mae` : stride du `Conv2d(stride=patch_size_mae)` du
#'    `patch_embed`. `image_size` doit en etre un multiple, sinon le modele
#'    rogne silencieusement les bords ;
#' - `window_m`       : fenetre physique = `image_size * resolution`.
#'
#' Les valeurs reproduisent la configuration FLAIR-HUB du modele de base
#' (cf. fiche HF `IGNF/MAESTRO_FLAIR-HUB_base`), a l'echelle 50 m de
#' PureForest. Les fenetres Sentinel sont elargies a 60 m pour respecter le
#' multiple de `patch_size_mae=2` sans padding artificiel.
#'
#' @return Liste nommee de specifications par modalite
#' @export
#' @examples
#' specs <- modalite_specs()
#' specs$aerial$image_size  # 256
#' specs$s2$window_m        # 60
modalite_specs <- function() {
  list(
    aerial = list(in_channels   = 4L,
                   image_size    = 256L,
                   resolution    = 0.2,
                   patch_size_mae = 16L,
                   window_m       = 51.2),
    dem    = list(in_channels   = 2L,
                   image_size    = 256L,
                   resolution    = 0.2,
                   patch_size_mae = 32L,
                   window_m       = 51.2),
    s2     = list(in_channels   = 10L,
                   image_size    = 6L,
                   resolution    = 10,
                   patch_size_mae = 2L,
                   window_m       = 60),
    s1_asc = list(in_channels   = 2L,
                   image_size    = 6L,
                   resolution    = 10,
                   patch_size_mae = 2L,
                   window_m       = 60),
    s1_des = list(in_channels   = 2L,
                   image_size    = 6L,
                   resolution    = 10,
                   patch_size_mae = 2L,
                   window_m       = 60)
  )
}

#' Taille de patch par modalite MAESTRO
#'
#' Wrapper retro-compatible autour de [modalite_specs()]. Pour de nouveaux
#' developpements, preferer l'acces direct via `modalite_specs()$<mod>$image_size`.
#'
#' @param mod_name Nom de la modalite
#' @param taille_pixels_ref Taille pour aerial/dem si mod_name n'est pas connue
#' @return Entier : nombre de pixels du patch
#' @export
taille_patch_modalite <- function(mod_name, taille_pixels_ref = 256L) {
  specs <- modalite_specs()
  if (mod_name %in% names(specs)) {
    return(as.integer(specs[[mod_name]]$image_size))
  }
  as.integer(taille_pixels_ref)
}

#' Creer une grille de patches pour l'inference
#'
#' Genere une grille reguliere de patches carres couvrant l'AOI.
#' Seuls les patches qui intersectent l'AOI sont conserves.
#'
#' Le pas de la grille doit correspondre a la fenetre physique de la
#' modalite de reference (typiquement `aerial`). Voir [modalite_specs()].
#'
#' @param aoi sf object en Lambert-93
#' @param taille_patch_m Taille des patches en metres (defaut: 51.2 m,
#'   correspond a aerial 256 px @ 0,2 m)
#' @return sf data.frame (grille de patches avec colonne `id`)
#' @export
creer_grille_patches <- function(aoi, taille_patch_m = 51.2) {
  message("=== Creation de la grille de patches ===")

  bbox <- sf::st_bbox(aoi)

  x_coords <- seq(bbox["xmin"], bbox["xmax"], by = taille_patch_m)
  y_coords <- seq(bbox["ymin"], bbox["ymax"], by = taille_patch_m)

  patches <- expand.grid(x = x_coords, y = y_coords)
  patches$xmax <- patches$x + taille_patch_m
  patches$ymax <- patches$y + taille_patch_m

  creer_poly <- function(i) {
    sf::st_polygon(list(matrix(c(
      patches$x[i],    patches$y[i],
      patches$xmax[i], patches$y[i],
      patches$xmax[i], patches$ymax[i],
      patches$x[i],    patches$ymax[i],
      patches$x[i],    patches$y[i]
    ), ncol = 2, byrow = TRUE)))
  }

  geometries <- lapply(seq_len(nrow(patches)), creer_poly)
  grille <- sf::st_sf(
    id = seq_len(nrow(patches)),
    geometry = sf::st_sfc(geometries, crs = sf::st_crs(aoi))
  )

  intersects <- sf::st_intersects(grille, sf::st_union(aoi), sparse = FALSE)[, 1]
  grille <- grille[intersects, ]
  grille$id <- seq_len(nrow(grille))

  message(sprintf("  Patches generes : %d", nrow(grille)))
  message(sprintf("  Taille patch    : %.1f m x %.1f m",
                   taille_patch_m, taille_patch_m))

  grille
}

#' Extraire les patches multi-modaux depuis plusieurs SpatRasters
#'
#' Pour chaque cellule de la grille, extrait une fenetre **centree** sur
#' le centroide de la cellule, dimensionnee selon la specification de
#' chaque modalite (cf. [modalite_specs()]). Les fenetres Sentinel
#' (60 m) depassent legerement la cellule aerienne (51,2 m) pour respecter
#' la contrainte multiple de `patch_size.mae=2`.
#'
#' Le contrat de sortie est compatible avec
#' [executer_inference_multimodal()] : chaque modalite est une matrice
#' (`H*W` lignes, `C` colonnes) au format produit par `terra::values()`.
#'
#' @param modalites Liste nommee de SpatRaster, ex.
#'   `list(aerial = ..., dem = ..., s2 = ...)`
#' @param grille sf grille de patches (issue de [creer_grille_patches()])
#' @param specs Specifications, defaut [modalite_specs()]
#' @return Liste de listes nommees : `patches[[i]]$<mod>` matrice (H*W, C)
#' @export
extraire_patches_multimodal <- function(modalites, grille,
                                          specs = modalite_specs()) {
  message("=== Extraction des patches multi-modaux ===")

  modalites_actives <- names(modalites)
  inconnues <- setdiff(modalites_actives, names(specs))
  if (length(inconnues) > 0L) {
    stop(sprintf(
      "Modalite(s) non supportee(s): %s. Connues: %s",
      paste(inconnues, collapse = ", "),
      paste(names(specs), collapse = ", ")
    ))
  }

  for (mn in modalites_actives) {
    s <- specs[[mn]]
    message(sprintf(
      "  %-7s: %3d x %3d px (%2d bandes, fenetre %.1f m, patch_size.mae=%d)",
      mn, s$image_size, s$image_size, s$in_channels, s$window_m,
      s$patch_size_mae))
  }

  n_patches <- nrow(grille)
  patches <- vector("list", n_patches)
  skipped <- integer(length(modalites_actives))
  names(skipped) <- modalites_actives

  for (i in seq_len(n_patches)) {
    bbox <- sf::st_bbox(grille[i, ])
    cx <- as.numeric((bbox["xmin"] + bbox["xmax"]) / 2)
    cy <- as.numeric((bbox["ymin"] + bbox["ymax"]) / 2)

    patch_data <- list()
    for (mn in modalites_actives) {
      r <- modalites[[mn]]
      s <- specs[[mn]]
      half_w <- s$window_m / 2
      ext_patch <- terra::ext(cx - half_w, cx + half_w,
                                cy - half_w, cy + half_w)

      ext_raster <- terra::ext(r)
      overlap <- !(ext_patch[1] >= ext_raster[2] ||
                   ext_patch[2] <= ext_raster[1] ||
                   ext_patch[3] >= ext_raster[4] ||
                   ext_patch[4] <= ext_raster[3])

      if (!overlap) {
        patch_data[[mn]] <- matrix(NA_real_,
                                     nrow = s$image_size * s$image_size,
                                     ncol = s$in_channels)
        skipped[mn] <- skipped[mn] + 1L
        next
      }

      crop_result <- tryCatch(terra::crop(r, ext_patch),
                                error = function(e) NULL)
      if (is.null(crop_result)) {
        patch_data[[mn]] <- matrix(NA_real_,
                                     nrow = s$image_size * s$image_size,
                                     ncol = s$in_channels)
        skipped[mn] <- skipped[mn] + 1L
        next
      }

      if (terra::ncol(crop_result) != s$image_size ||
          terra::nrow(crop_result) != s$image_size) {
        template <- terra::rast(
          ext = ext_patch,
          nrows = s$image_size, ncols = s$image_size,
          crs = terra::crs(r),
          nlyrs = terra::nlyr(r)
        )
        crop_result <- terra::resample(crop_result, template,
                                          method = "bilinear")
      }

      patch_data[[mn]] <- terra::values(crop_result)
    }
    patches[[i]] <- patch_data

    if (i %% 100 == 0 || i == n_patches) {
      message(sprintf("  Patches extraits : %d / %d", i, n_patches))
    }
  }

  for (mn in modalites_actives) {
    if (skipped[mn] > 0L) {
      message(sprintf("  %s : %d patch(es) hors raster (rempli NA)",
                       mn, skipped[mn]))
    }
  }
  message(sprintf("  Total patches : %d", length(patches)))
  patches
}

#' Extraire les patches d'un raster unique (mono-modal)
#'
#' Variante mono-modale de [extraire_patches_multimodal()] : utilise
#' uniquement la modalite `aerial`. Conservee pour les usages legers et
#' les tests d'integration.
#'
#' @param r SpatRaster multi-bandes (typiquement RGBI 4 bandes)
#' @param grille sf grille de patches
#' @param taille_pixels Taille du patch en pixels (defaut: 256)
#' @return Liste de matrices (H*W, C)
#' @export
extraire_patches_raster <- function(r, grille, taille_pixels = 256L) {
  patches <- extraire_patches_multimodal(
    modalites = list(aerial = r),
    grille = grille,
    specs = list(aerial = list(in_channels = terra::nlyr(r),
                                  image_size = as.integer(taille_pixels),
                                  resolution = NA_real_,
                                  patch_size_mae = NA_integer_,
                                  window_m = as.numeric(taille_pixels) *
                                              terra::res(r)[1]))
  )
  lapply(patches, function(p) p$aerial)
}
