#' Classes d'essences forestieres PureForest
#'
#' Table des 13 classes d'essences forestieres du jeu de donnees PureForest
#' (IGN), utilise pour l'entrainement du modele MAESTRO. Source officielle :
#' fiche dataset Hugging Face `IGNF/PureForest`.
#'
#' @return Un data.frame avec les colonnes code, classe, nom_latin et type
#' @export
#' @examples
#' ess <- essences_pureforest()
#' ess[ess$type == "feuillu", ]
essences_pureforest <- function() {
  data.frame(
    code = 0:12,
    classe = c(
      "Chene decidu",
      "Chene vert",
      "Hetre",
      "Chataignier",
      "Robinier",
      "Pin maritime",
      "Pin sylvestre",
      "Pin noir",
      "Pin d'Alep",
      "Sapin",
      "Epicea",
      "Meleze",
      "Douglas"
    ),
    nom_latin = c(
      "Quercus robur, Q. petraea, Q. pubescens",
      "Quercus ilex",
      "Fagus sylvatica",
      "Castanea sativa",
      "Robinia pseudoacacia",
      "Pinus pinaster",
      "Pinus sylvestris",
      "Pinus nigra",
      "Pinus halepensis",
      "Abies alba",
      "Picea abies",
      "Larix decidua, L. kaempferi",
      "Pseudotsuga menziesii"
    ),
    type = c(
      "feuillu", "feuillu", "feuillu", "feuillu", "feuillu",
      "resineux", "resineux", "resineux", "resineux",
      "resineux", "resineux", "resineux", "resineux"
    ),
    stringsAsFactors = FALSE
  )
}


#' Classes d'essences forestieres TreeSatAI (legacy, 7 classes)
#'
#' Table des 7 classes regroupees, conservee uniquement pour la
#' compatibilite avec les checkpoints fine-tunes sur TreeSatAI produits
#' avant la migration vers PureForest 13 classes (cf. DEV_PLAN.md, phase 0).
#' Non exportee, ne pas utiliser pour de nouveaux entrainements.
#'
#' @return data.frame (code, classe, nom_latin, type)
#' @keywords internal
#' @noRd
essences_treesatai <- function() {
  data.frame(
    code = 0:6,
    classe = c(
      "Chene",
      "Hetre",
      "Pin",
      "Epicea",
      "Douglas/Sapin",
      "Meleze",
      "Feuillus divers"
    ),
    nom_latin = c(
      "Quercus spp.",
      "Fagus sylvatica",
      "Pinus spp.",
      "Picea abies",
      "Pseudotsuga menziesii, Abies alba",
      "Larix spp.",
      "Betula, Populus, Alnus, Fraxinus, Acer, etc."
    ),
    type = c(
      "feuillu", "feuillu",
      "resineux", "resineux", "resineux", "resineux",
      "feuillu"
    ),
    stringsAsFactors = FALSE
  )
}
