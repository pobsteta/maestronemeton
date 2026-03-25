#' Generer un rapport HTML ou PDF du pipeline MAESTRO
#'
#' Compile le template Rmd fourni avec le package pour produire un rapport
#' complet du pipeline : telechargement des donnees, combinaison, creation
#' des patches, indices spectraux et optionnellement inference.
#'
#' @param aoi_path Chemin vers le fichier GeoPackage de l'AOI.
#' @param output_dir Repertoire de sortie pour les resultats et le rapport
#'   (par defaut `"outputs"`).
#' @param format Format de sortie : `"html"` (par defaut) ou `"pdf"`.
#'   Le format PDF necessite une installation LaTeX (voir
#'   [tinytex::install_tinytex()]).
#' @param output_file Nom du fichier de sortie (optionnel). Par defaut
#'   `"rapport_pipeline_aoi.html"` ou `"rapport_pipeline_aoi.pdf"`.
#' @param millesime Millesime des orthophotos IGN (`NULL` = le plus recent).
#' @param inference Logical. Lancer l'inference MAESTRO ? (defaut `FALSE`).
#' @param gpu Logical. Utiliser le GPU pour l'inference ? (defaut `FALSE`).
#' @param model_id Identifiant du modele sur Hugging Face
#'   (defaut `"IGNF/MAESTRO_FLAIR-HUB_base"`).
#' @param use_s2 Logical. Telecharger et integrer les donnees Sentinel-2 ?
#'   (defaut `FALSE`).
#' @param use_s1 Logical. Telecharger et integrer les donnees Sentinel-1 ?
#'   (defaut `FALSE`).
#' @param date_sentinel Date cible pour les donnees Sentinel (format
#'   `"YYYY-MM-DD"` ou `NULL`).
#' @param open Logical. Ouvrir le rapport dans le navigateur apres generation ?
#'   (defaut `TRUE` en session interactive).
#' @return Le chemin du fichier rapport genere (invisiblement).
#' @export
#' @examples
#' \dontrun{
#' # Rapport HTML simple
#' generer_rapport("data/aoi.gpkg")
#'
#' # Rapport PDF avec inference
#' generer_rapport("data/aoi.gpkg", format = "pdf", inference = TRUE)
#'
#' # Rapport complet avec Sentinel-2 et inference GPU
#' generer_rapport(
#'   aoi_path   = "data/aoi.gpkg",
#'   format     = "html",
#'   inference  = TRUE,
#'   gpu        = TRUE,
#'   use_s2     = TRUE,
#'   date_sentinel = "2024-06-15"
#' )
#' }
generer_rapport <- function(aoi_path,
                            output_dir = "outputs",
                            format = c("html", "pdf"),
                            output_file = NULL,
                            millesime = NULL,
                            inference = FALSE,
                            gpu = FALSE,
                            model_id = "IGNF/MAESTRO_FLAIR-HUB_base",
                            use_s2 = FALSE,
                            use_s1 = FALSE,
                            date_sentinel = NULL,
                            open = interactive()) {

  format <- match.arg(format)

  if (!requireNamespace("rmarkdown", quietly = TRUE)) {
    stop("Le package 'rmarkdown' est requis. Installez-le avec :\n",
         "  install.packages('rmarkdown')", call. = FALSE)
  }

  if (format == "pdf" && !requireNamespace("tinytex", quietly = TRUE)) {
    message("Note : le format PDF necessite LaTeX. ",
            "Installez tinytex avec :\n  install.packages('tinytex')\n",
            "  tinytex::install_tinytex()")
  }

  # Localiser le template Rmd

rmd_path <- system.file("scripts/rapport_pipeline_aoi.Rmd",
                            package = "maestro")
  if (!nzchar(rmd_path)) {
    stop("Template Rmd introuvable. Verifiez l'installation du package.",
         call. = FALSE)
  }

  # Repertoire de sortie
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  # Format de sortie rmarkdown
  output_format <- switch(format,
    html = "html_document",
    pdf  = "pdf_document"
  )

  # Nom du fichier de sortie
  if (is.null(output_file)) {
    ext <- if (format == "html") ".html" else ".pdf"
    output_file <- paste0("rapport_pipeline_aoi", ext)
  }

  # Parametres du rapport
  params <- list(
    aoi_path      = normalizePath(aoi_path, mustWork = TRUE),
    output_dir    = normalizePath(output_dir, mustWork = FALSE),
    millesime     = millesime,
    inference     = inference,
    gpu           = gpu,
    model_id      = model_id,
    use_s2        = use_s2,
    use_s1        = use_s1,
    date_sentinel = date_sentinel
  )

  message("Generation du rapport ", format, " ...")
  message("  AOI      : ", params$aoi_path)
  message("  Sortie   : ", file.path(output_dir, output_file))
  message("  Inference: ", ifelse(inference, "oui", "non"))
  if (use_s2) message("  Sentinel-2: oui")
  if (use_s1) message("  Sentinel-1: oui")

  result_path <- rmarkdown::render(
    input         = rmd_path,
    output_format = output_format,
    output_file   = output_file,
    output_dir    = normalizePath(output_dir, mustWork = FALSE),
    params        = params,
    envir         = new.env(parent = globalenv()),
    quiet         = FALSE
  )

  message("Rapport genere : ", result_path)

  if (open && interactive()) {
    utils::browseURL(result_path)
  }

  invisible(result_path)
}
