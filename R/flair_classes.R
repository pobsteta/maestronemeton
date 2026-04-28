# =============================================================================
# Classes d'occupation du sol FLAIR-HUB
# =============================================================================

#' Classes d'occupation du sol CoSIA (15 classes actives + non classifie)
#'
#' Table des classes d'occupation du sol CoSIA apres remapping
#' depuis les codes FLAIR-1. Les classes desactivees (coupe, mixte,
#' ligneux, autre) sont remappees a 0 (non classifie).
#'
#' Compatible avec la sortie des modeles 19 classes apres remapping.
#'
#' @return Un data.frame avec les colonnes code, classe, couleur
#' @export
#' @examples
#' cls <- classes_cosia()
#' cls[cls$code <= 5, ]
classes_cosia <- function() {
  data.frame(
    code = 0:15,
    classe = c(
      "Non classifie",
      "Batiment",
      "Serre / bache plastique",
      "Piscine",
      "Zone impermeable",
      "Zone permeable",
      "Sol nu",
      "Eau",
      "Neige",
      "Herbace / pelouse",
      "Agricole / culture",
      "Terre labouree",
      "Vigne",
      "Feuillu",
      "Conifere",
      "Lande / broussaille"
    ),
    couleur = c(
      "#808080",
      "#db0e9a",
      "#3de6eb",
      "#ffffff",
      "#f80c00",
      "#938e7b",
      "#a97101",
      "#1553ae",
      "#c4b5d2",
      "#55ff00",
      "#fff30d",
      "#e4df7c",
      "#660082",
      "#46e483",
      "#194a26",
      "#f3a60d"
    ),
    stringsAsFactors = FALSE
  )
}


#' Classes CoSIA pour modeles FLAIR-INC 15 classes
#'
#' Table des 15 classes utilisees par les modeles FLAIR-INC,
#' avec codes CoSIA 1-indexed (apres remapping Python).
#' Compatible avec la sortie de `predire_raster_complet()`.
#'
#' @return Un data.frame avec les colonnes code, classe, couleur
#' @export
classes_cosia_15 <- function() {
  data.frame(
    code = 1:15,
    classe = c(
      "Batiment",
      "Serre / bache plastique",
      "Piscine",
      "Zone impermeable",
      "Zone permeable",
      "Sol nu",
      "Eau",
      "Neige",
      "Herbace / pelouse",
      "Agricole / culture",
      "Terre labouree",
      "Vigne",
      "Feuillu",
      "Conifere",
      "Lande / broussaille"
    ),
    couleur = c(
      "#db0e9a",
      "#3de6eb",
      "#ffffff",
      "#f80c00",
      "#938e7b",
      "#a97101",
      "#1553ae",
      "#c4b5d2",
      "#55ff00",
      "#fff30d",
      "#e4df7c",
      "#660082",
      "#46e483",
      "#194a26",
      "#f3a60d"
    ),
    stringsAsFactors = FALSE
  )
}


#' Classes de cultures LPIS/RPG (23 classes)
#'
#' Table des 23 classes de cultures du jeu de donnees FLAIR-HUB,
#' issues du Registre Parcellaire Graphique (RPG / LPIS).
#'
#' @return Un data.frame avec les colonnes code, classe, couleur
#' @export
#' @examples
#' cls <- classes_lpis()
#' head(cls)
classes_lpis <- function() {
  data.frame(
    code = 1:23,
    classe = c(
      "Ble tendre",
      "Mais grain / ensilage",
      "Orge",
      "Autres cereales",
      "Colza",
      "Tournesol",
      "Autres oleagineux",
      "Proteagineux",
      "Plantes a fibres",
      "Semences",
      "Gel / jacheres",
      "Fourrage",
      "Estives / landes",
      "Prairies permanentes",
      "Prairies temporaires",
      "Vergers",
      "Vignes",
      "Fruits a coque",
      "Oliviers",
      "Autres cultures",
      "Legumes / fleurs",
      "Canne a sucre",
      "Divers"
    ),
    couleur = c(
      "#ffff00", "#ff6600", "#d8b56b", "#aa7841", "#00ff00",
      "#ffaa00", "#7faa00", "#00aa7f", "#00ffff", "#007fff",
      "#d2691e", "#7fff00", "#556b2f", "#98fb98", "#90ee90",
      "#ff69b4", "#800080", "#a0522d", "#808000", "#ffa07a",
      "#ff1493", "#00ced1", "#c0c0c0"
    ),
    stringsAsFactors = FALSE
  )
}

#' Modeles FLAIR-HUB pre-entraines disponibles
#'
#' Catalogue des modeles pre-entraines pour la segmentation d'occupation du sol.
#' Les modeles sont heberges sur HuggingFace par l'IGNF.
#'
#' @return Un data.frame avec les colonnes id, architecture, encoder, decoder,
#'   n_bands, supervision, miou
#' @export
#' @examples
#' mods <- flair_models()
#' mods[mods$miou > 60, ]
flair_models <- function() {
  data.frame(
    id = c(
      "IGNF/FLAIR-INC_rgbi_15cl_resnet34-unet",
      "IGNF/FLAIR-INC_rgbie_15cl_resnet34-unet",
      "IGNF/FLAIR-HUB_LC-A_IR_convnextv2tiny-upernet"
    ),
    architecture = c(
      "ResNet34-UNet",
      "ResNet34-UNet",
      "ConvNeXTV2-UPerNet"
    ),
    encoder = c("resnet34", "resnet34", "convnextv2_tiny"),
    decoder = c("unet", "unet", "upernet"),
    n_bands = c(4L, 5L, 4L),
    supervision = c("cosia_15cl", "cosia_15cl", "cosia_19cl"),
    miou = c(55.0, 56.0, 64.1),
    description = c(
      "RGBI 4 bandes (baseline)",
      "RGBI + elevation 5 bandes",
      "FLAIR-HUB multimodal (aerial IR)"
    ),
    stringsAsFactors = FALSE
  )
}
