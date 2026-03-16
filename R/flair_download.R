# =============================================================================
# Telechargement du dataset FLAIR-HUB depuis HuggingFace
# =============================================================================

#' Lister les fichiers d'un dataset HuggingFace
#'
#' Interroge l'API HuggingFace pour lister les fichiers disponibles dans un
#' dataset (ou sous-ensemble).
#'
#' @param repo_id Identifiant du repository HuggingFace (ex: "IGNF/FLAIR-HUB")
#' @param path Sous-chemin optionnel pour filtrer
#' @param token Token HuggingFace (optionnel, pour les repos prives)
#' @return Vecteur de noms de fichiers
#' @export
hf_list_files <- function(repo_id, path = NULL, token = NULL) {
  url <- sprintf("https://huggingface.co/api/datasets/%s/tree/main", repo_id)
  if (!is.null(path)) {
    url <- paste0(url, "/", path)
  }

  h <- curl::new_handle()
  if (!is.null(token)) {
    curl::handle_setheaders(h, Authorization = paste("Bearer", token))
  }

  resp <- tryCatch(
    curl::curl_fetch_memory(url, handle = h),
    error = function(e) {
      warning("Erreur API HuggingFace: ", e$message)
      return(NULL)
    }
  )

  if (is.null(resp) || resp$status_code != 200) {
    warning("Impossible de lister les fichiers (HTTP ", resp$status_code, ")")
    return(character(0))
  }

  items <- jsonlite::fromJSON(rawToChar(resp$content))
  if (is.data.frame(items) && "path" %in% names(items)) {
    return(items$path)
  }
  character(0)
}

#' Telecharger un fichier depuis un dataset HuggingFace
#'
#' @param repo_id Identifiant du repository (ex: "IGNF/FLAIR-HUB")
#' @param filename Nom du fichier dans le repo
#' @param dest_dir Repertoire de destination local
#' @param token Token HuggingFace (optionnel)
#' @return Chemin du fichier telecharge
#' @export
hf_download_file <- function(repo_id, filename, dest_dir, token = NULL) {
  fs::dir_create(dest_dir)

  url <- sprintf("https://huggingface.co/datasets/%s/resolve/main/%s",
                 repo_id, filename)
  dest_file <- file.path(dest_dir, basename(filename))

  if (file.exists(dest_file)) {
    message("  Deja telecharge: ", basename(filename))
    return(dest_file)
  }

  h <- curl::new_handle()
  curl::handle_setopt(h, followlocation = TRUE)
  if (!is.null(token)) {
    curl::handle_setheaders(h, Authorization = paste("Bearer", token))
  }

  message("  Telechargement: ", filename)
  tryCatch(
    curl::curl_download(url, dest_file, handle = h, quiet = TRUE),
    error = function(e) {
      warning("Echec telechargement ", filename, ": ", e$message)
      return(NULL)
    }
  )

  dest_file
}

#' Telecharger un sous-ensemble du dataset FLAIR-HUB
#'
#' Telecharge les fichiers d'une modalite et d'un domaine specifiques
#' du dataset FLAIR-HUB depuis HuggingFace.
#'
#' @param modalite Modalite a telecharger: "aerial", "dem", "spot", "s2", "s1",
#'   "labels_cosia", "labels_lpis"
#' @param domaine Domaine geographique (ex: "D001_2019")
#' @param data_dir Repertoire de base pour les donnees
#' @param repo_id Identifiant du repository (defaut: "IGNF/FLAIR-HUB")
#' @param token Token HuggingFace (optionnel)
#' @return Vecteur de chemins de fichiers telecharges
#' @export
download_flair_subset <- function(modalite, domaine = NULL,
                                   data_dir = "data/flair_hub",
                                   repo_id = "IGNF/FLAIR-HUB",
                                   token = NULL) {
  message(sprintf("=== Telechargement FLAIR-HUB: %s ===", modalite))

  path <- modalite
  if (!is.null(domaine)) {
    path <- file.path(modalite, domaine)
  }

  files <- hf_list_files(repo_id, path = path, token = token)
  if (length(files) == 0) {
    warning("Aucun fichier trouve pour ", path)
    return(character(0))
  }

  # Filtrer les fichiers .tif
  tif_files <- files[grepl("\\.tif$", files, ignore.case = TRUE)]
  message(sprintf("  %d fichiers TIF trouves", length(tif_files)))

  downloaded <- vapply(tif_files, function(f) {
    dest_dir <- file.path(data_dir, dirname(f))
    hf_download_file(repo_id, f, dest_dir, token)
  }, character(1))

  downloaded
}

#' Lister les domaines FLAIR-HUB disponibles
#'
#' Interroge l'API HuggingFace pour lister les domaines geographiques
#' disponibles dans le dataset FLAIR-HUB. Chaque domaine correspond
#' a un departement francais + annee (ex: D001_2019 = Ain 2019).
#'
#' @param repo_id Identifiant du repository HuggingFace
#' @param token Token HuggingFace (optionnel)
#' @return data.frame avec colonnes domaine, departement, annee
#' @export
lister_domaines_flair <- function(repo_id = "IGNF/FLAIR-HUB",
                                    token = NULL) {
  # Mapping des numeros de departement vers les noms
  deps <- c(
    "001" = "Ain", "002" = "Aisne", "003" = "Allier",
    "004" = "Alpes-de-Haute-Provence", "005" = "Hautes-Alpes",
    "006" = "Alpes-Maritimes", "007" = "Ardeche", "008" = "Ardennes",
    "009" = "Ariege", "010" = "Aube", "011" = "Aude",
    "012" = "Aveyron", "013" = "Bouches-du-Rhone", "014" = "Calvados",
    "015" = "Cantal", "016" = "Charente", "017" = "Charente-Maritime",
    "018" = "Cher", "019" = "Correze", "021" = "Cote-d'Or",
    "022" = "Cotes-d'Armor", "023" = "Creuse", "024" = "Dordogne",
    "025" = "Doubs", "026" = "Drome", "027" = "Eure",
    "028" = "Eure-et-Loir", "029" = "Finistere", "030" = "Gard",
    "031" = "Haute-Garonne", "032" = "Gers", "033" = "Gironde",
    "034" = "Herault", "035" = "Ille-et-Vilaine", "036" = "Indre",
    "037" = "Indre-et-Loire", "038" = "Isere", "039" = "Jura",
    "040" = "Landes", "041" = "Loir-et-Cher", "042" = "Loire",
    "043" = "Haute-Loire", "044" = "Loire-Atlantique", "045" = "Loiret",
    "046" = "Lot", "047" = "Lot-et-Garonne", "048" = "Lozere",
    "049" = "Maine-et-Loire", "050" = "Manche", "051" = "Marne",
    "052" = "Haute-Marne", "053" = "Mayenne", "054" = "Meurthe-et-Moselle",
    "055" = "Meuse", "056" = "Morbihan", "057" = "Moselle",
    "058" = "Nievre", "059" = "Nord", "060" = "Oise",
    "061" = "Orne", "062" = "Pas-de-Calais", "063" = "Puy-de-Dome",
    "064" = "Pyrenees-Atlantiques", "065" = "Hautes-Pyrenees",
    "066" = "Pyrenees-Orientales", "067" = "Bas-Rhin", "068" = "Haut-Rhin",
    "069" = "Rhone", "070" = "Haute-Saone", "071" = "Saone-et-Loire",
    "072" = "Sarthe", "073" = "Savoie", "074" = "Haute-Savoie",
    "075" = "Paris", "076" = "Seine-Maritime", "077" = "Seine-et-Marne",
    "078" = "Yvelines", "079" = "Deux-Sevres", "080" = "Somme",
    "081" = "Tarn", "082" = "Tarn-et-Garonne", "083" = "Var",
    "084" = "Vaucluse", "085" = "Vendee", "086" = "Vienne",
    "087" = "Haute-Vienne", "088" = "Vosges", "089" = "Yonne",
    "090" = "Territoire de Belfort", "091" = "Essonne",
    "092" = "Hauts-de-Seine", "093" = "Seine-Saint-Denis",
    "094" = "Val-de-Marne", "095" = "Val-d'Oise"
  )

  # Lister les sous-dossiers du dossier aerial/
  files <- hf_list_files(repo_id, path = "aerial", token = token)
  if (length(files) == 0) {
    warning("Impossible de lister les domaines FLAIR-HUB")
    return(data.frame())
  }

  # Extraire les noms de domaine (D001_2019, D013_2020, ...)
  domaines <- unique(dirname(sub("^aerial/", "", files)))
  domaines <- domaines[grepl("^D[0-9]{3}_[0-9]{4}$", domaines)]
  domaines <- sort(domaines)

  # Construire le data.frame
  result <- data.frame(
    domaine = domaines,
    numero_dep = sub("^D([0-9]{3})_.*", "\\1", domaines),
    annee = as.integer(sub("^D[0-9]{3}_([0-9]{4})$", "\\1", domaines)),
    stringsAsFactors = FALSE
  )
  result$departement <- deps[result$numero_dep]
  result$departement[is.na(result$departement)] <- "?"

  message(sprintf("  %d domaines FLAIR-HUB disponibles", nrow(result)))
  result
}


#' Domaines FLAIR-HUB recommandes pour l'entrainement segmentation
#'
#' Retourne une selection de domaines couvrant une diversite d'essences
#' forestieres (chenes, hetres, pins, sapins, douglas, chataigniers, etc.)
#' repartis sur differentes regions de France.
#'
#' @param niveau Niveau de couverture : "minimal" (5 domaines, ~500 patches),
#'   "standard" (10 domaines, ~1000 patches), "complet" (20 domaines,
#'   ~2000 patches)
#' @return Vecteur de noms de domaines
#' @export
domaines_recommandes_segmentation <- function(niveau = "standard") {
  # Selection basee sur la couverture des 10 classes NDP0 :
  # - Chene : largement distribue (Centre, Ouest, Sud-Ouest)
  # - Hetre : Nord-Est, montagnes
  # - Chataignier : Massif Central, Perigord, Corse
  # - Pin maritime : Landes, Gironde
  # - Pin sylvestre : Massif Central, Alpes
  # - Epicea/Sapin : Vosges, Jura, Alpes
  # - Douglas : Massif Central
  # - Meleze : Alpes du Sud
  # - Peuplier : vallees fluviales (Loire, Garonne)

  minimal <- c(
    "D033_2020",  # Gironde     : pin maritime, chene
    "D063_2019",  # Puy-de-Dome : douglas, hetre, epicea
    "D088_2019",  # Vosges      : epicea, sapin, hetre
    "D024_2020",  # Dordogne    : chataignier, chene
    "D077_2020"   # Seine-et-Marne : chene, hetre (Fontainebleau)
  )

  standard <- c(
    minimal,
    "D040_2020",  # Landes      : pin maritime
    "D039_2019",  # Jura        : epicea, sapin, hetre
    "D019_2019",  # Correze     : chataignier, hetre, douglas
    "D005_2019",  # Hautes-Alpes: meleze, pin sylvestre
    "D045_2019"   # Loiret      : chene, pin sylvestre, peuplier
  )

  complet <- c(
    standard,
    "D048_2019",  # Lozere      : pin sylvestre, hetre, epicea
    "D038_2020",  # Isere       : epicea, sapin, hetre
    "D015_2019",  # Cantal      : hetre, epicea, douglas
    "D057_2019",  # Moselle     : hetre, chene
    "D073_2019",  # Savoie      : epicea, meleze
    "D047_2020",  # Lot-et-Garonne : chene, peuplier
    "D012_2019",  # Aveyron     : chene, pin sylvestre, hetre
    "D067_2019",  # Bas-Rhin    : hetre, sapin, chene
    "D081_2020",  # Tarn        : chene, chataignier, douglas
    "D007_2019"   # Ardeche     : chataignier, pin, chene
  )

  domaines <- switch(niveau,
    minimal  = minimal,
    standard = standard,
    complet  = complet,
    stop("Niveau inconnu: '", niveau, "'. Utilisez 'minimal', 'standard' ou 'complet'")
  )

  message(sprintf("  %d domaines recommandes (niveau '%s')", length(domaines), niveau))
  message(sprintf("  Domaines: %s", paste(domaines, collapse = ", ")))
  domaines
}


#' Telecharger les domaines FLAIR-HUB recommandes pour la segmentation
#'
#' Telecharge les patches FLAIR-HUB (aerial + modalites choisies) pour
#' les domaines recommandes, couvrant une diversite d'essences forestieres.
#'
#' @param niveau Niveau de couverture : "minimal", "standard", "complet"
#' @param modalites Modalites a telecharger (defaut: `c("aerial", "dem")`)
#' @param data_dir Repertoire de destination
#' @param token Token HuggingFace (optionnel)
#' @return Vecteur de domaines telecharges
#' @export
download_flair_segmentation <- function(niveau = "standard",
                                          modalites = c("aerial", "dem"),
                                          data_dir = "data/flair_hub",
                                          token = NULL) {
  domaines <- domaines_recommandes_segmentation(niveau)

  message(sprintf("\n=== Telechargement FLAIR-HUB : %d domaines x %d modalites ===",
                   length(domaines), length(modalites)))

  for (dom in domaines) {
    for (mod in modalites) {
      tryCatch(
        download_flair_subset(mod, domaine = dom, data_dir = data_dir,
                               token = token),
        error = function(e) {
          warning(sprintf("Echec %s/%s: %s", mod, dom, e$message))
        }
      )
    }
  }

  message(sprintf("\n=== Telechargement termine : %s/ ===", data_dir))
  invisible(domaines)
}


#' Telecharger le toy dataset FLAIR-HUB
#'
#' Telecharge un petit jeu de donnees d'exemple pour tester le pipeline.
#'
#' @param data_dir Repertoire de destination
#' @param token Token HuggingFace (optionnel)
#' @return Chemin du repertoire contenant les donnees
#' @export
download_flair_toy <- function(data_dir = "data/flair_hub_toy",
                                token = NULL) {
  message("=== Telechargement du toy dataset FLAIR-HUB ===")
  fs::dir_create(data_dir)

  repo_id <- "IGNF/FLAIR-HUB"

  # Telecharger un petit domaine d'exemple
  download_flair_subset("aerial", domaine = "D001_2019",
                         data_dir = data_dir, repo_id = repo_id, token = token)
  download_flair_subset("labels_cosia", domaine = "D001_2019",
                         data_dir = data_dir, repo_id = repo_id, token = token)

  message("Toy dataset telecharge dans: ", data_dir)
  data_dir
}

#' Charger un patch FLAIR-HUB depuis un fichier GeoTIFF
#'
#' @param tif_path Chemin vers le fichier GeoTIFF du patch
#' @return SpatRaster
#' @export
load_flair_patch <- function(tif_path) {
  if (!file.exists(tif_path)) {
    stop("Fichier introuvable: ", tif_path)
  }
  terra::rast(tif_path)
}

#' Scanner les fichiers FLAIR-HUB disponibles localement
#'
#' Explore un repertoire pour detecter les patches FLAIR-HUB
#' et leurs modalites.
#'
#' @param data_dir Repertoire contenant les donnees FLAIR-HUB
#' @return Liste nommee par modalite, chacune contenant les chemins des fichiers
#' @export
scan_flair_files <- function(data_dir = "data/flair_hub") {
  if (!dir.exists(data_dir)) {
    message("Repertoire introuvable: ", data_dir)
    return(list())
  }

  modalites <- c("aerial", "dem", "spot", "s2", "s1",
                 "labels_cosia", "labels_lpis")

  result <- list()
  for (mod in modalites) {
    mod_dir <- file.path(data_dir, mod)
    if (dir.exists(mod_dir)) {
      files <- list.files(mod_dir, pattern = "\\.tif$",
                          recursive = TRUE, full.names = TRUE)
      if (length(files) > 0) {
        result[[mod]] <- files
        message(sprintf("  %s: %d fichiers", mod, length(files)))
      }
    }
  }

  if (length(result) == 0) {
    message("Aucun fichier FLAIR-HUB trouve dans: ", data_dir)
  }

  result
}
