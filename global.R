# ==============================================================================
# IGL Dashboard v2  |  MINDDEVEL / PADGOF-GIZ
# global.R — Bibliothèques, configuration, chargement des données, utilitaires
# ==============================================================================

# ── 1. BIBLIOTHÈQUES ──────────────────────────────────────────────────────────

suppressPackageStartupMessages({
  library(shiny)
  library(shinydashboard)
  library(shinyWidgets)
  library(shinymanager)
  library(plotly)
  library(leaflet)
  library(DT)
  library(dplyr)
  library(tidyr)
  library(scales)
  library(htmltools)
  library(waiter)
  library(DBI)
  library(RSQLite)
})

# robotoolbox est optionnel — l'app fonctionne sans lui
HAS_ROBOTOOLBOX <- requireNamespace("robotoolbox", quietly = TRUE)

# ── 2. CONSTANTES ─────────────────────────────────────────────────────────────

APP_VERSION  <- "2.0.0"
APP_NAME     <- "IGL Dashboard"
APP_SUBTITLE <- "Indice de Gouvernance Locale"
APP_ORG      <- "MINDDEVEL / PADGOF-GIZ"
APP_YEAR     <- "2026"

DATA_DIR      <- "data"
DATA_FILE     <- file.path(DATA_DIR, "igl_data.RData")
SYNC_LOG_FILE <- file.path(DATA_DIR, "sync_log.rds")
CREDS_DB      <- file.path(DATA_DIR, "credentials.sqlite")
ACTIVITY_LOG  <- file.path(DATA_DIR, "activity_log.rds")

# Passphrase pour la base des identifiants (en prod, définir dans .Renviron)
CREDS_PASSPHRASE <- Sys.getenv("IGL_CREDS_PASSPHRASE", unset = "IGL_Secure_2025_Cameroun")

# Créer les répertoires nécessaires
dir.create(DATA_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create("logs",   showWarnings = FALSE, recursive = TRUE)

# ── 3. PALETTE DE COULEURS ────────────────────────────────────────────────────

IGL_VERT       <- "#2D6A4F"
IGL_VERT_CLAIR <- "#40916C"
IGL_VERT_PALE  <- "#95D5B2"
IGL_BLEU       <- "#1D3557"
IGL_BLEU_CLAIR <- "#457B9D"
IGL_JAUNE      <- "#FCD116"
IGL_ROUGE      <- "#CE1126"
IGL_ORANGE     <- "#F77F00"
IGL_GRIS       <- "#6C757D"

couleurs_perf <- c(
  "Très bonne" = "#2D6A4F",
  "Bonne"      = "#40916C",
  "Moyenne"    = "#FCBF49",
  "Faible"     = "#F77F00",
  "Critique"   = "#D62828"
)
niveaux_perf <- c("Très bonne", "Bonne", "Moyenne", "Faible", "Critique")

# Coordonnées géographiques des régions (Cameroun)
COORDS_REGIONS <- data.frame(
  region_name = c("Adamaoua","Centre","Est","Extrême-Nord","Littoral",
                  "Nord","Nord-Ouest","Ouest","Sud","Sud-Ouest"),
  lng = c(13.5, 11.5, 14.0, 14.3,  9.7, 13.4, 10.1, 10.1, 11.0,  9.2),
  lat = c( 7.3,  3.9,  4.0, 10.6,  4.1,  9.3,  6.0,  5.5,  2.8,  4.9),
  stringsAsFactors = FALSE
)

# ── 4. INITIALISATION DE LA BASE D'IDENTIFIANTS ───────────────────────────────

initialize_credentials <- function() {
  if (!file.exists(CREDS_DB)) {
    credentials_init <- data.frame(
      user              = c("admin",          "evaluateur",       "visualiseur"),
      password          = c("Admin@IGL2025!", "Eval@IGL2025!",    "View@IGL2025!"),
      name              = c("Administrateur", "Évaluateur IGL",   "Visualiseur"),
      start             = rep(as.character(Sys.Date()), 3),
      expire            = rep(as.character(Sys.Date() + 730), 3),
      admin             = c(TRUE, FALSE, FALSE),
      permissions       = c("admin", "evaluateur", "visualiseur"),
      comment           = c(
        "Compte administrateur — changer le mot de passe immédiatement",
        "Compte évaluateur — accès visualisation et téléchargement",
        "Compte visualiseur — accès visualisation uniquement"
      ),
      # ── Périmètre des données accessibles (vide = toutes les données) ──
      data_regions      = c("", "", ""),
      data_departements = c("", "", ""),
      data_communes     = c("", "", ""),
      stringsAsFactors = FALSE
    )
    tryCatch({
      shinymanager::create_db(
        credentials_data = credentials_init,
        sqlite_path      = CREDS_DB,
        passphrase       = CREDS_PASSPHRASE
      )
      message("[IGL] ✅ Base d'identifiants créée : ", CREDS_DB)
      message("[IGL] ⚠️  CHANGER les mots de passe par défaut après la 1ère connexion !")
    }, error = function(e) {
      message("[IGL] ❌ Erreur création identifiants : ", conditionMessage(e))
    })
  }
}

# ── Migration : ajoute les colonnes de périmètre aux DB existantes ───────────
migrate_credentials_db <- function() {
  if (!file.exists(CREDS_DB)) return(invisible())

  tryCatch({
    conn <- DBI::dbConnect(RSQLite::SQLite(), CREDS_DB)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    users <- shinymanager::read_db_decrypt(conn, "credentials", CREDS_PASSPHRASE)

    needs_migration <- FALSE
    if (!"data_regions"      %in% names(users)) { users$data_regions      <- ""; needs_migration <- TRUE }
    if (!"data_departements" %in% names(users)) { users$data_departements <- ""; needs_migration <- TRUE }
    if (!"data_communes"     %in% names(users)) { users$data_communes     <- ""; needs_migration <- TRUE }

    if (needs_migration) {
      shinymanager::write_db_encrypt(conn, users, "credentials", CREDS_PASSPHRASE)
      message("[IGL] ✅ Migration BDD : colonnes data_regions/data_departements/data_communes ajoutées")
    }
  }, error = function(e) {
    message("[IGL] ⚠️  Migration ignorée : ", conditionMessage(e))
  })
}

initialize_credentials()
migrate_credentials_db()

# ── 5. TRAITEMENT DES DONNÉES KOBOTOOLBOX ─────────────────────────────────────

process_kobo_data <- function(raw_data) {
  if (!is.data.frame(raw_data) || nrow(raw_data) == 0)
    stop("Données KoboToolbox vides ou invalides.")

  # Mapping flexible des colonnes géographiques
  find_col <- function(candidates) {
    found <- intersect(tolower(candidates), tolower(names(raw_data)))
    if (length(found) > 0) names(raw_data)[tolower(names(raw_data)) == found[1]] else NULL
  }

  col_region   <- find_col(c("region_name","region","b_region","region_evaluee","Région"))
  col_division <- find_col(c("division_name","division","b_departement","departement","Département"))
  col_commune  <- find_col(c("subdivision_name","subdivision","commune","b_commune","commune_evaluee","Commune"))

  if (any(sapply(list(col_region, col_division, col_commune), is.null))) {
    stop("Colonnes géographiques introuvables. Disponibles: ",
         paste(names(raw_data)[1:min(20, ncol(raw_data))], collapse = ", "))
  }

  df <- raw_data %>%
    rename(
      region_name      = !!col_region,
      division_name    = !!col_division,
      subdivision_name = !!col_commune
    ) %>%
    mutate(across(any_of(c(
      paste0("q", c(101:107, 201:207, 301:306, 401:406), "_score"),
      paste0("d", 1:4, "_score"), "igl_score"
    )), as.numeric))

  # Calcul des scores de domaine manquants
  calc_domain <- function(df, prefix, n_max) {
    cols <- paste0(prefix, 1:n_max, "_score")
    available <- intersect(cols, names(df))
    if (length(available) >= 1)
      round(rowMeans(df[, available, drop = FALSE], na.rm = TRUE), 2)
    else
      rep(0.5, nrow(df))
  }

  if (!"d1_score" %in% names(df)) df$d1_score <- calc_domain(df, "q10", 7)
  if (!"d2_score" %in% names(df)) df$d2_score <- calc_domain(df, "q20", 7)
  if (!"d3_score" %in% names(df)) df$d3_score <- calc_domain(df, "q30", 6)
  if (!"d4_score" %in% names(df)) df$d4_score <- calc_domain(df, "q40", 6)
  if (!"igl_score" %in% names(df)) {
    df$igl_score <- round(
      df$d1_score * 0.35 + df$d2_score * 0.25 +
      df$d3_score * 0.25 + df$d4_score * 0.15, 2
    )
  }

  # Contraindre les scores dans [0, 1]
  score_cols <- c("d1_score","d2_score","d3_score","d4_score","igl_score")
  df <- df %>% mutate(across(all_of(score_cols), ~ pmin(1, pmax(0, .x))))

  # Pré-calcul des colonnes optionnelles hors mutate (cur_data() et names(.)
  # sont fragiles à l'intérieur d'un mutate dplyr)
  has_sub_time <- "_submission_time" %in% names(df)
  has_eval     <- "evaluateur"        %in% names(df)
  has_audio    <- "commentaire_audio" %in% names(df)

  eval_dates <- if (has_sub_time) {
    as.Date(substr(df[["_submission_time"]], 1, 10))
  } else {
    rep(Sys.Date(), nrow(df))
  }
  eval_noms  <- if (has_eval)  df[["evaluateur"]]        else rep("N/A",             nrow(df))
  eval_audio <- if (has_audio) df[["commentaire_audio"]] else rep("Non disponible",  nrow(df))

  # Ajouter les interprétations et recommandations
  df <- df %>% mutate(
    igl_interpretation = get_interpretation(igl_score),
    d1_interpretation  = case_when(
      d1_score >= 0.80 ~ "Très bonne gouvernance administrative",
      d1_score >= 0.60 ~ "Bonne gouvernance administrative",
      d1_score >= 0.40 ~ "Gouvernance administrative moyenne",
      d1_score >= 0.20 ~ "Faible gouvernance administrative",
      TRUE             ~ "Gouvernance administrative critique"),
    d2_interpretation  = case_when(
      d2_score >= 0.80 ~ "Très bonne gouvernance financière",
      d2_score >= 0.60 ~ "Bonne gouvernance financière",
      d2_score >= 0.40 ~ "Gouvernance financière moyenne",
      d2_score >= 0.20 ~ "Faible gouvernance financière",
      TRUE             ~ "Gouvernance financière critique"),
    d3_interpretation  = case_when(
      d3_score >= 0.80 ~ "Très bonne gouvernance participative",
      d3_score >= 0.60 ~ "Bonne gouvernance participative",
      d3_score >= 0.40 ~ "Gouvernance participative moyenne",
      d3_score >= 0.20 ~ "Faible gouvernance participative",
      TRUE             ~ "Gouvernance participative critique"),
    d4_interpretation  = case_when(
      d4_score >= 0.80 ~ "Très bon exercice des compétences",
      d4_score >= 0.60 ~ "Bon exercice des compétences",
      d4_score >= 0.40 ~ "Exercice moyen des compétences",
      d4_score >= 0.20 ~ "Faible exercice des compétences",
      TRUE             ~ "Exercice critique des compétences"),
    igl_recommandation = case_when(
      igl_score >= 0.80 ~ "Commune modèle. Maintenir les acquis et partager les bonnes pratiques.",
      igl_score >= 0.60 ~ "Bonne performance. Consolider les forces et cibler les domaines faibles.",
      igl_score >= 0.40 ~ "Performance moyenne. Élaborer un plan d'amélioration avec accompagnement.",
      igl_score >= 0.20 ~ "Performance faible. Plan d'urgence requis avec accompagnement soutenu.",
      TRUE              ~ "Situation critique. Audit complet et plan de redressement recommandés."),
    d1_recommandation  = case_when(
      d1_score >= 0.80 ~ "Maintenir les acquis en matière de sessions et de gestion du personnel.",
      d1_score >= 0.60 ~ "Consolider la régularité des sessions et le suivi des actes.",
      d1_score >= 0.40 ~ "Améliorer la tenue des sessions et systématiser la transmission des actes.",
      d1_score >= 0.20 ~ "Intervention urgente sur l'organisation administrative.",
      TRUE             ~ "Restructuration complète de la gouvernance administrative requise."),
    d2_recommandation  = case_when(
      d2_score >= 0.80 ~ "Poursuivre la bonne gestion budgétaire et la transparence.",
      d2_score >= 0.60 ~ "Renforcer le suivi de l'exécution budgétaire.",
      d2_score >= 0.40 ~ "Améliorer la mobilisation des recettes et la reddition des comptes.",
      d2_score >= 0.20 ~ "Intervention urgente sur la gestion financière.",
      TRUE             ~ "Audit financier et tutelle financière recommandés."),
    d3_recommandation  = case_when(
      d3_score >= 0.80 ~ "Maintenir les mécanismes de participation citoyenne.",
      d3_score >= 0.60 ~ "Renforcer les cadres de concertation avec les populations.",
      d3_score >= 0.40 ~ "Mettre en place des mécanismes formels de participation.",
      d3_score >= 0.20 ~ "Intervention urgente : instaurer des mécanismes de participation.",
      TRUE             ~ "Absence de participation. Cadres de concertation urgents."),
    d4_recommandation  = case_when(
      d4_score >= 0.80 ~ "Poursuivre l'exercice effectif des compétences transférées.",
      d4_score >= 0.60 ~ "Consolider l'exercice des compétences transférées.",
      d4_score >= 0.40 ~ "Renforcer les capacités d'exercice des compétences.",
      d4_score >= 0.20 ~ "Intervention urgente sur les compétences transférées.",
      TRUE             ~ "Incapacité à exercer les compétences. Accompagnement indispensable."),
    domaines_faibles = paste0(
      ifelse(d1_score < 0.60, "Gouvernance Administrative; ", ""),
      ifelse(d2_score < 0.60, "Gouvernance Financière; ", ""),
      ifelse(d3_score < 0.60, "Gouvernance Participative; ", ""),
      ifelse(d4_score < 0.60, "Compétences Transférées; ", "")),
    evaluation_date   = eval_dates,
    evaluateur        = eval_noms,
    commentaire_audio = eval_audio
  )

  df
}

# ── 6. CALCUL DES AGRÉGATIONS ─────────────────────────────────────────────────

compute_aggregations <- function() {
  stopifnot(exists("igl_data"), nrow(igl_data) > 0)

  divisions_scores <<- igl_data %>%
    group_by(region_name, division_name) %>%
    summarise(
      nb_communes = n(),
      d1_score = round(mean(d1_score, na.rm = TRUE), 2),
      d2_score = round(mean(d2_score, na.rm = TRUE), 2),
      d3_score = round(mean(d3_score, na.rm = TRUE), 2),
      d4_score = round(mean(d4_score, na.rm = TRUE), 2),
      igl_score = round(mean(igl_score, na.rm = TRUE), 2),
      .groups = "drop"
    ) %>%
    mutate(igl_interpretation = get_interpretation(igl_score))

  regions_scores <<- igl_data %>%
    group_by(region_name) %>%
    summarise(
      nb_communes = n(),
      d1_score = round(mean(d1_score, na.rm = TRUE), 2),
      d2_score = round(mean(d2_score, na.rm = TRUE), 2),
      d3_score = round(mean(d3_score, na.rm = TRUE), 2),
      d4_score = round(mean(d4_score, na.rm = TRUE), 2),
      igl_score = round(mean(igl_score, na.rm = TRUE), 2),
      .groups = "drop"
    ) %>%
    mutate(igl_interpretation = get_interpretation(igl_score))

  national_score <<- data.frame(
    nb_communes = nrow(igl_data),
    d1_score    = round(mean(igl_data$d1_score, na.rm = TRUE), 2),
    d2_score    = round(mean(igl_data$d2_score, na.rm = TRUE), 2),
    d3_score    = round(mean(igl_data$d3_score, na.rm = TRUE), 2),
    d4_score    = round(mean(igl_data$d4_score, na.rm = TRUE), 2),
    igl_score   = round(mean(igl_data$igl_score, na.rm = TRUE), 2),
    stringsAsFactors = FALSE
  ) %>% mutate(igl_interpretation = get_interpretation(igl_score))

  regions <<- data.frame(
    region_name = sort(unique(igl_data$region_name)),
    stringsAsFactors = FALSE
  )
}

# ── 7. CHARGEMENT PRINCIPAL DES DONNÉES ───────────────────────────────────────

charger_donnees <- function(force_kobo = FALSE) {

  sync_info <- list(source = "inconnu", timestamp = Sys.time(),
                    status = "pending", message = "Chargement en cours...")

  kobo_url   <- Sys.getenv("KOBO_URL",       unset = "")
  kobo_token <- Sys.getenv("KOBO_TOKEN",     unset = "")
  kobo_uid   <- Sys.getenv("KOBO_ASSET_UID", unset = "")
  kobo_ok    <- nchar(kobo_url) > 0 && nchar(kobo_token) > 0 && nchar(kobo_uid) > 0

  # ── A. Tentative KoboToolbox ─────────────────────────────────────
  if ((kobo_ok || force_kobo) && HAS_ROBOTOOLBOX) {
    tryCatch({
      message("[IGL] Connexion à KoboToolbox : ", kobo_url, " ...")
      robotoolbox::kobo_setup(url = kobo_url, token = kobo_token)
      asset    <- robotoolbox::kobo_asset(kobo_uid)
      raw_data <- robotoolbox::kobo_data(asset, all = TRUE)
      message("[IGL] ", nrow(raw_data), " soumissions reçues.")

      igl_data <<- process_kobo_data(raw_data)
      compute_aggregations()

      save(igl_data, divisions_scores, regions_scores, national_score, regions,
           file = DATA_FILE)

      sync_info <- list(
        source    = "kobo",
        timestamp = Sys.time(),
        status    = "success",
        message   = paste0("Synchronisé depuis KoboToolbox : ",
                           nrow(igl_data), " communes | ",
                           format(Sys.time(), "%d/%m/%Y %H:%M"))
      )
      saveRDS(sync_info, SYNC_LOG_FILE)
      message("[IGL] ✅ Données KoboToolbox chargées (", nrow(igl_data), " communes).")
      return(sync_info)

    }, error = function(e) {
      message("[IGL] ⚠️  Erreur KoboToolbox : ", conditionMessage(e))
      sync_info$status  <<- "kobo_error"
      sync_info$message <<- paste0("Erreur KoboToolbox : ", conditionMessage(e),
                                    " | Utilisation du cache local.")
    })
  }

  # ── B. Cache local ────────────────────────────────────────────────
  if (file.exists(DATA_FILE)) {
    env_tmp <- new.env(parent = emptyenv())
    tryCatch({
      load(DATA_FILE, envir = env_tmp)
      igl_data         <<- env_tmp$igl_data
      divisions_scores <<- env_tmp$divisions_scores
      regions_scores   <<- env_tmp$regions_scores
      national_score   <<- env_tmp$national_score
      regions          <<- env_tmp$regions

      age_h   <- round(as.numeric(difftime(Sys.time(), file.mtime(DATA_FILE), units = "hours")), 1)
      warning <- if (age_h > 24) paste0(" ⚠️ Cache âgé de ", age_h, "h — actualisation recommandée") else ""
      icone   <- if (sync_info$status == "kobo_error") "⚠️ Fallback" else "📁 Cache local"

      sync_info <<- list(
        source    = "local_cache",
        timestamp = file.mtime(DATA_FILE),
        status    = if (sync_info$status == "kobo_error") "fallback" else "local",
        message   = paste0(icone, " : ", nrow(igl_data), " communes | ",
                            format(file.mtime(DATA_FILE), "%d/%m/%Y %H:%M"), warning)
      )
      saveRDS(sync_info, SYNC_LOG_FILE)
      message("[IGL] Données chargées depuis cache local (", nrow(igl_data), " communes).")
      return(sync_info)

    }, error = function(e) {
      message("[IGL] Erreur cache local : ", conditionMessage(e))
    })
  }

  # ── C. Données de démonstration ───────────────────────────────────
  message("[IGL] Génération des données de démonstration...")
  source("generate_data.R", local = FALSE)

  sync_info <- list(
    source    = "demo",
    timestamp = Sys.time(),
    status    = "demo",
    message   = paste0("Données de DÉMONSTRATION — ", nrow(igl_data),
                        " communes fictives | Configurez KOBO_URL, KOBO_TOKEN, KOBO_ASSET_UID pour les données réelles.")
  )
  saveRDS(sync_info, SYNC_LOG_FILE)
  message("[IGL] Données de démonstration générées (", nrow(igl_data), " communes).")
  return(sync_info)
}

# ── 8. CHARGEMENT INITIAL ─────────────────────────────────────────────────────

sync_info_global <- tryCatch(
  charger_donnees(),
  error = function(e) {
    message("[IGL] ERREUR CRITIQUE : ", conditionMessage(e))
    list(status = "critical_error", message = conditionMessage(e))
  }
)

# Listes pour les filtres
liste_regions      <- sort(unique(igl_data$region_name))
liste_departements <- sort(unique(igl_data$division_name))
liste_communes     <- sort(unique(igl_data$subdivision_name))

# ── 9. FONCTIONS UTILITAIRES ──────────────────────────────────────────────────

format_score <- function(x) sprintf("%.2f", x)
format_pct   <- function(x) paste0(round(x * 100, 1), "%")

get_interpretation <- function(score) {
  case_when(
    score >= 0.80 ~ "Très bonne",
    score >= 0.60 ~ "Bonne",
    score >= 0.40 ~ "Moyenne",
    score >= 0.20 ~ "Faible",
    TRUE          ~ "Critique"
  )
}

# Résout le bug jsonlite : retourne un vecteur non nommé pour plotly
map_couleurs <- function(interpretations) {
  unname(couleurs_perf[as.character(interpretations)])
}

# KPI box stylisée
kpi_box <- function(valeur, label, icone = "chart-bar", couleur = "green") {
  bg <- switch(couleur,
    "green"  = "linear-gradient(135deg, #2D6A4F, #40916C)",
    "blue"   = "linear-gradient(135deg, #1D3557, #457B9D)",
    "yellow" = "linear-gradient(135deg, #F9C74F, #F77F00)",
    "red"    = "linear-gradient(135deg, #CE1126, #E63946)",
    "orange" = "linear-gradient(135deg, #F77F00, #FCBF49)",
    "grey"   = "linear-gradient(135deg, #546E7A, #78909C)",
    "linear-gradient(135deg, #2D6A4F, #40916C)"
  )
  txt_color <- if (couleur %in% c("yellow", "orange")) "#333" else "white"

  tags$div(
    class = "kpi-box",
    style = paste0("background:", bg, "; color:", txt_color,
                   "; padding:16px 18px; border-radius:10px; margin-bottom:15px;",
                   " box-shadow:0 4px 14px rgba(0,0,0,0.18);"),
    tags$div(
      style = "display:flex; align-items:center;",
      tags$i(class = paste0("fa fa-", icone),
             style = "font-size:28px; margin-right:14px; opacity:0.85;"),
      tags$div(
        tags$div(style = "font-size:22px; font-weight:700; line-height:1.15;", valeur),
        tags$div(style = "font-size:12px; opacity:0.9; margin-top:3px;", label)
      )
    )
  )
}

# Badge de rôle coloré
role_badge <- function(role) {
  cfg <- list(
    admin       = list(bg = "#CE1126", label = "Administrateur"),
    evaluateur  = list(bg = "#1D3557", label = "Évaluateur"),
    visualiseur = list(bg = "#2D6A4F", label = "Visualiseur")
  )
  c <- cfg[[role]] %||% list(bg = "#666", label = role)
  tags$span(
    style = paste0("background:", c$bg, "; color:white; padding:2px 10px;",
                   " border-radius:12px; font-size:11px; font-weight:600;"),
    c$label
  )
}

# Journal d'activité
log_activity <- function(user, action, detail = "") {
  tryCatch({
    entry <- data.frame(timestamp = Sys.time(), user = user,
                        action = action, detail = detail,
                        stringsAsFactors = FALSE)
    existing <- if (file.exists(ACTIVITY_LOG)) readRDS(ACTIVITY_LOG) else data.frame()
    updated  <- bind_rows(existing, entry)
    if (nrow(updated) > 2000) updated <- tail(updated, 2000)
    saveRDS(updated, ACTIVITY_LOG)
  }, error = function(e) NULL)  # journalisation silencieuse
}

# Opérateur null-coalesce
`%||%` <- function(x, y) if (!is.null(x)) x else y

# ── Filtrage CASCADÉ selon le périmètre de données d'un utilisateur ──────────
# Logique : on applique le filtre le plus PRÉCIS d'abord (communes > départements
# > régions). Vide à un niveau = pas de restriction à ce niveau.
apply_user_scope <- function(df, scope_regions = character(0),
                                   scope_departements = character(0),
                                   scope_communes = character(0)) {
  if (length(scope_communes) > 0) {
    return(df[df$subdivision_name %in% scope_communes, , drop = FALSE])
  }
  if (length(scope_departements) > 0) {
    return(df[df$division_name %in% scope_departements, , drop = FALSE])
  }
  if (length(scope_regions) > 0) {
    return(df[df$region_name %in% scope_regions, , drop = FALSE])
  }
  df   # aucune restriction → toutes les données
}

# ── 10. OPTIONS ───────────────────────────────────────────────────────────────

options(shiny.maxRequestSize = 200 * 1024^2)

# ── 11. BANNER CONSOLE ────────────────────────────────────────────────────────

cat("\n╔══════════════════════════════════════════════════════╗\n")
cat("║  IGL Dashboard v2  |  MINDDEVEL / PADGOF-GIZ          ║\n")
cat("╠══════════════════════════════════════════════════════╣\n")
cat(sprintf("║  Source    : %-40s║\n", sync_info_global$source))
cat(sprintf("║  Communes  : %-40s║\n", nrow(igl_data)))
cat(sprintf("║  Régions   : %-40s║\n", length(liste_regions)))
cat(sprintf("║  KoboTools : %-40s║\n", if (HAS_ROBOTOOLBOX) "Disponible" else "Non installé"))
cat("╚══════════════════════════════════════════════════════╝\n\n")
