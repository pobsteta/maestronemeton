#' Classes d'essences forestieres PureForest
#'
#' Table des 13 classes d'essences forestieres du jeu de donnees PureForest,
#' utilise pour l'entrainement du modele MAESTRO. Source : BD Foret V2 / IGN.
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
      "Chene decidue",
      "Chene vert",
      "Hetre",
      "Chataignier",
      "Pin maritime",
      "Pin sylvestre",
      "Pin laricio/noir",
      "Pin d'Alep",
      "Epicea",
      "Sapin",
      "Douglas",
      "Meleze",
      "Peuplier"
    ),
    nom_latin = c(
      "Quercus spp. (deciduous)",
      "Quercus ilex",
      "Fagus sylvatica",
      "Castanea sativa",
      "Pinus pinaster",
      "Pinus sylvestris",
      "Pinus nigra",
      "Pinus halepensis",
      "Picea abies",
      "Abies alba",
      "Pseudotsuga menziesii",
      "Larix spp.",
      "Populus spp."
    ),
    type = c(
      "feuillu", "feuillu", "feuillu", "feuillu",
      "resineux", "resineux", "resineux", "resineux",
      "resineux", "resineux", "resineux", "resineux",
      "feuillu"
    ),
    stringsAsFactors = FALSE
  )
}
