#' Trouver le nom du fichier checkpoint dans un depot Hugging Face
#'
#' Interroge l'API Hugging Face pour lister les fichiers du depot et
#' retourne le fichier de poids le plus probable.
#'
#' @param hf_repo Identifiant du depot (ex: `"IGNF/MAESTRO_FLAIR-HUB_base"`)
#' @return Nom du fichier checkpoint, ou NULL
#' @export
find_checkpoint_name <- function(hf_repo) {
  url <- paste0("https://huggingface.co/api/models/", hf_repo)
  resp <- tryCatch({
    tmp <- tempfile()
    h <- curl::new_handle()
    curl::curl_download(url, tmp, handle = h)
    info <- jsonlite::fromJSON(tmp)
    unlink(tmp)
    info
  }, error = function(e) NULL)
  if (is.null(resp)) return(NULL)

  files <- resp$siblings$rfilename
  ckpt_files <- files[grepl("\\.(ckpt|pth|pt|bin|safetensors)$", files)]
  if (length(ckpt_files) == 0) return(NULL)

  ext_priority <- c("\\.ckpt$", "\\.pth$", "\\.pt$", "\\.bin$", "\\.safetensors$")
  for (pat in ext_priority) {
    matches <- ckpt_files[grepl(pat, ckpt_files)]
    if (length(matches) > 0) return(matches[1])
  }
  ckpt_files[1]
}

#' Telecharger le modele MAESTRO depuis Hugging Face
#'
#' Utilise le package R [hfhub](https://cran.r-project.org/package=hfhub)
#' pour telecharger les poids et la configuration du modele. Les fichiers
#' sont mis en cache par hfhub et reutilises automatiquement.
#'
#' @param repo_id Identifiant du depot HF (ex: `"IGNF/MAESTRO_FLAIR-HUB_base"`)
#' @param token Token Hugging Face (optionnel, ou via `HUGGING_FACE_HUB_TOKEN`)
#' @return Liste avec `config` et `weights` (chemins locaux)
#' @export
telecharger_modele <- function(repo_id = "IGNF/MAESTRO_FLAIR-HUB_base",
                                token = NULL) {
  if (!requireNamespace("hfhub", quietly = TRUE)) {
    stop("Le package 'hfhub' est requis. Installez-le avec : ",
         "install.packages('hfhub')")
  }

  message("=== Telechargement du modele MAESTRO depuis Hugging Face ===")
  message(sprintf("Repository : %s", repo_id))

  if (!is.null(token)) {
    Sys.setenv(HUGGING_FACE_HUB_TOKEN = token)
  }

  fichiers_modele <- list()

  # Config
  tryCatch({
    fichiers_modele$config <- hfhub::hub_download(repo_id, "config.json")
    message(sprintf("  Config : %s", fichiers_modele$config))
  }, error = function(e) message("  Pas de config.json"))

  # Poids : detection auto
  ckpt_name <- find_checkpoint_name(repo_id)
  if (!is.null(ckpt_name)) {
    message(sprintf("  Telechargement via hfhub : %s", ckpt_name))
    tryCatch({
      fichiers_modele$weights <- hfhub::hub_download(repo_id, ckpt_name)
      message(sprintf("  Poids : %s", fichiers_modele$weights))
    }, error = function(e) message("  hfhub echoue: ", e$message))
  }

  # Fallback noms standards
  if (is.null(fichiers_modele$weights)) {
    noms_poids <- c("model.safetensors", "pytorch_model.bin",
                     "model.pt", "checkpoint.pth")
    for (nom in noms_poids) {
      tryCatch({
        fichiers_modele$weights <- hfhub::hub_download(repo_id, nom)
        message(sprintf("  Poids : %s", fichiers_modele$weights))
        break
      }, error = function(e) NULL)
    }
  }

  # Dernier fallback : snapshot
  if (is.null(fichiers_modele$weights)) {
    message("  Tentative de snapshot complet...")
    tryCatch({
      fichiers_modele$snapshot <- hfhub::hub_snapshot(repo_id = repo_id)
      message(sprintf("  Snapshot : %s", fichiers_modele$snapshot))
    }, error = function(e) {
      stop("Impossible de telecharger le modele : ", e$message)
    })
  }

  fichiers_modele
}
