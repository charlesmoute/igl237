# ==============================================================================
# IGL Dashboard v2  |  MINDDEVEL / PADGOF-GIZ
# server.R — Logique serveur complète, authentifiée et corrigée
# ==============================================================================

server <- function(input, output, session) {

  # ── AUTHENTIFICATION SHINYMANAGER ─────────────────────────────────────────
  res_auth <- secure_server(
    check_credentials = check_credentials(CREDS_DB, passphrase = CREDS_PASSPHRASE)
  )
  
  # ── ÉTAT UTILISATEUR (peuplé une seule fois à la connexion) ──────────────
  # Approche reactiveValues + observeEvent : évite les chaînes req()/tryCatch()
  # qui se bloquent mutuellement et retournent silencieusement FALSE.
  user_state <- reactiveValues(
    ok                = FALSE,
    login             = "",
    name              = "",
    permissions       = "visualiseur",
    is_admin          = FALSE,
    can_download      = FALSE,
    # ── Périmètre des données accessibles ──────────────────────────────────
    # Vide (vector character(0)) = aucune restriction sur ce niveau
    # Si non vide, on applique le filtre le plus précis disponible (cascade)
    data_regions      = character(0),
    data_departements = character(0),
    data_communes     = character(0)
  )

  # ── INITIALISATION DEPUIS L'UTILISATEUR AUTHENTIFIÉ ───────────────────────
  # CORRECTION DÉFINITIVE : on n'utilise PAS res_auth$result (qui n'existe pas
  # dans shinymanager). On lit directement res_auth$user_info via un observe()
  # qui se déclenche dès que les infos sont disponibles.
  observe({
    # Lecture robuste de user_info (peut être valeur ou reactive selon version)
    info <- tryCatch({
      val <- res_auth$user_info
      if (is.function(val)) val() else val
    }, error = function(e) NULL)

    user_login <- tryCatch({
      v <- res_auth$user
      if (is.function(v)) v() else v
    }, error = function(e) NULL)

    # ── FALLBACK : si user_info indisponible mais user oui, lire depuis la DB ─
    if ((is.null(info) || (is.data.frame(info) && nrow(info) == 0)) &&
        !is.null(user_login) && nchar(as.character(user_login)) > 0) {
      info <- tryCatch({
        conn <- DBI::dbConnect(RSQLite::SQLite(), CREDS_DB)
        on.exit(DBI::dbDisconnect(conn), add = TRUE)
        all_users <- shinymanager::read_db_decrypt(conn, "credentials", CREDS_PASSPHRASE)
        all_users[all_users$user == as.character(user_login), , drop = FALSE]
      }, error = function(e) NULL)
    }

    # Si toujours pas d'info, attendre le prochain tick
    if (is.null(info)) return()
    if (is.data.frame(info) && nrow(info) == 0) return()

    # ── Évite la ré-exécution inutile ─────────────────────────────────────
    if (isTRUE(user_state$ok) && identical(user_state$login, as.character(user_login))) return()

    # ── Extraction robuste : structure varie selon version shinymanager ───
    safe_get <- function(field) {
      val <- tryCatch({
        if (is.data.frame(info)) info[1, field]
        else                     info[[field]]
      }, error = function(e) NA)
      if (length(val) == 0) NA else val[1]
    }

    if (is.null(user_login) || nchar(as.character(user_login)) == 0) {
      user_login <- as.character(safe_get("user"))
    }
    user_login <- as.character(user_login)
    user_name  <- as.character(safe_get("name"))
    user_perms <- as.character(safe_get("permissions"))
    raw_admin  <- safe_get("admin")

    # Détection admin (formats multiples : TRUE / 1 / "1" / "TRUE")
    user_admin <-
      isTRUE(as.logical(raw_admin)) ||
      identical(as.character(raw_admin), "1") ||
      identical(toupper(as.character(raw_admin)), "TRUE")

    # FALLBACK ULTIME : mapping login → rôle pour les 3 comptes par défaut
    login_lc <- tolower(trimws(user_login))
    if (login_lc == "admin")      { user_admin <- TRUE; user_perms <- "admin"      }
    if (login_lc == "evaluateur"  && (is.na(user_perms) || nchar(trimws(user_perms)) == 0))
      user_perms <- "evaluateur"
    if (login_lc == "visualiseur" && (is.na(user_perms) || nchar(trimws(user_perms)) == 0))
      user_perms <- "visualiseur"

    if (is.na(user_perms) || nchar(trimws(user_perms)) == 0)
      user_perms <- if (user_admin) "admin" else "visualiseur"
    if (is.na(user_name)  || nchar(trimws(user_name))  == 0)
      user_name <- user_login

    # ── Lecture du périmètre de données ─────────────────────────────────
    parse_scope <- function(field) {
      raw <- as.character(safe_get(field))
      if (is.na(raw) || nchar(trimws(raw)) == 0) return(character(0))
      vals <- trimws(strsplit(raw, ";", fixed = TRUE)[[1]])
      vals[nchar(vals) > 0]
    }
    user_data_regions      <- parse_scope("data_regions")
    user_data_departements <- parse_scope("data_departements")
    user_data_communes     <- parse_scope("data_communes")

    # ── Mise à jour user_state (ok EN DERNIER) ──────────────────────────
    user_state$login             <- user_login
    user_state$name              <- user_name
    user_state$permissions       <- user_perms
    user_state$is_admin          <- user_admin || identical(tolower(user_perms), "admin")
    user_state$can_download      <- user_admin || tolower(user_perms) %in% c("admin", "evaluateur")
    user_state$data_regions      <- user_data_regions
    user_state$data_departements <- user_data_departements
    user_state$data_communes     <- user_data_communes
    user_state$ok                <- TRUE   # ← déclenche tous les renderUI

    message("[IGL] ✅ Connexion : ", user_login,
            " | role=", user_perms,
            " | admin=", user_state$is_admin,
            " | download=", user_state$can_download,
            " | scope: ", length(user_data_regions), " rég / ",
            length(user_data_departements), " dép / ",
            length(user_data_communes), " com")

    log_activity(user_login, "connexion", paste0("role=", user_perms))

    # ── Rafraîchir les filtres sidebar selon le périmètre ───────────────
    df_scope <- apply_user_scope(igl_data,
                                 user_data_regions,
                                 user_data_departements,
                                 user_data_communes)
    updateSelectInput(session, "filtre_region",
                      choices  = c("Toutes les régions" = "",
                                   sort(unique(df_scope$region_name))),
                      selected = "")
    updateSelectInput(session, "filtre_departement",
                      choices  = c("Tous les départements" = ""), selected = "")
    updateSelectInput(session, "filtre_commune",
                      choices  = c("Toutes les communes" = ""), selected = "")
    updateSelectInput(session, "export_commune_select",
                      choices  = sort(unique(df_scope$subdivision_name)))
  })

  # ── MENU LATÉRAL DYNAMIQUE (méthode officielle shinydashboard) ──────────────
  # sidebarMenuOutput / renderMenu = seul moyen fiable pour un menu conditionnel.
  # hideTab/showTab et uiOutput dans sidebarMenu ne fonctionnent PAS dans
  # shinydashboard pour les menuItem.
  output$sidebar_menu <- renderMenu({
    items <- list(
      menuItem("Vue Nationale",          tabName = "national",      icon = icon("globe")),
      menuItem("Analyse Régionale",      tabName = "regional",      icon = icon("map")),
      menuItem("Analyse Départementale", tabName = "departemental", icon = icon("map-marker-alt")),
      menuItem("Détail Commune",         tabName = "communal",      icon = icon("city")),
      menuItem("Classement",             tabName = "classement",    icon = icon("list-ol")),
      menuItem("Analytique",             tabName = "analytique",    icon = icon("chart-line"),
               badgeLabel = "Nouveau", badgeColor = "yellow"),
      menuItem("Export Résultats",       tabName = "export",        icon = icon("file-download"))
    )

    if (isTRUE(user_state$is_admin)) {
      items <- c(items, list(
        menuItem("Administration", tabName = "admin", icon = icon("cog"),
                 badgeLabel = "Admin", badgeColor = "red")
      ))
    }

    do.call(sidebarMenu, c(list(id = "tabs"), items))
  })

  # ── ÉCRAN DE CHARGEMENT ────────────────────────────────────────────────────
  w <- Waiter$new(
    html  = tagList(
      spin_fading_circles(),
      tags$br(),
      tags$span("Chargement du tableau de bord IGL...",
                style = "color:#2D6A4F; font-weight:600; font-size:14px;")
    ),
    color = "rgba(244,246,249,0.95)"
  )
  w$show()
  Sys.sleep(0.8)
  w$hide()



  # ── ÉTAT DE SYNCHRONISATION (réactif, peut être rafraîchi) ────────────────
  sync_rv <- reactiveVal(sync_info_global)

  # ── INFORMATIONS UTILISATEUR DANS LE HEADER ───────────────────────────────
  output$user_info_header <- renderUI({
    req(user_state$ok)
    u <- user_state

    # Badge périmètre si l'utilisateur a une restriction
    perimetre_badge <- if (length(u$data_communes) > 0) {
      tags$span(style = "background:#F77F00; color:white; padding:1px 6px; border-radius:8px; font-size:9px; margin-left:4px;",
                paste0(length(u$data_communes), " com."))
    } else if (length(u$data_departements) > 0) {
      tags$span(style = "background:#F77F00; color:white; padding:1px 6px; border-radius:8px; font-size:9px; margin-left:4px;",
                paste0(length(u$data_departements), " dép."))
    } else if (length(u$data_regions) > 0) {
      tags$span(style = "background:#F77F00; color:white; padding:1px 6px; border-radius:8px; font-size:9px; margin-left:4px;",
                paste0(length(u$data_regions), " rég."))
    } else NULL

    tags$a(href = "#",
           style = "color:white; font-size:12px; padding:10px 14px; display:flex; align-items:center;",
      tags$i(class = "fa fa-user-circle", style = "font-size:18px; margin-right:8px; opacity:0.85;"),
      tags$div(
        tags$div(style = "font-size:12px; font-weight:600; line-height:1.2;", u$name),
        tags$div(style = paste0("font-size:10px; opacity:0.75; background:",
                                 switch(u$permissions,
                                   admin = "#CE1126", evaluateur = "#1D3557", "#2D6A4F"),
                                 "; color:white; border-radius:8px; padding:1px 6px; margin-top:2px;",
                                 " display:inline-block;"),
                 switch(u$permissions,
                   admin = "Administrateur", evaluateur = "Évaluateur", "Visualiseur"),
                 perimetre_badge
        )
      )
    )
  })

  # Badge de synchronisation
  output$sync_badge <- renderUI({
    si <- sync_rv()
    color_style <- switch(
      si$status,
      "success"  = "background:#2D6A4F;",
      "demo"     = "background:#1D3557;",
      "fallback" = "background:#F77F00;",
      "error"    = "background:#CE1126;",
      "background:#546E7A;"
    )
    icone <- switch(si$status,
      "success"  = "check-circle", "demo" = "flask",
      "fallback" = "exclamation-triangle", "error" = "times-circle",
      "redo")
    ts <- if (!is.null(si$timestamp)) format(si$timestamp, "%d/%m %H:%M") else "—"
    tags$a(href = "#", title = si$message,
           style = paste0("color:white; font-size:11px; padding:10px 12px;",
                          " display:flex; align-items:center; border-left:1px solid rgba(255,255,255,0.1);"),
      tags$span(
        style = paste0("display:inline-flex; align-items:center; ", color_style,
                       " padding:3px 9px; border-radius:20px; font-size:10px;"),
        tags$i(class = paste0("fa fa-", icone), style = "margin-right:4px;"),
        ts
      )
    )
  })

  # ── MENU ADMIN (conditionnel) ──────────────────────────────────────────────

  # ── FILTRES EN CASCADE ─────────────────────────────────────────────────────
  observeEvent(input$filtre_region, {
    if (nchar(input$filtre_region) > 0) {
      deps <- igl_data_scoped() %>% filter(region_name == input$filtre_region) %>%
        pull(division_name) %>% unique() %>% sort()
      updateSelectInput(session, "filtre_departement",
                        choices = c("Tous les départements" = "", deps))
    } else {
      updateSelectInput(session, "filtre_departement",
                        choices = c("Tous les départements" = ""))
    }
    updateSelectInput(session, "filtre_commune", choices = c("Toutes les communes" = ""))
  })

  observeEvent(input$filtre_departement, {
    if (nchar(input$filtre_departement) > 0) {
      coms <- igl_data_scoped() %>% filter(division_name == input$filtre_departement) %>%
        pull(subdivision_name) %>% unique() %>% sort()
      updateSelectInput(session, "filtre_commune",
                        choices = c("Toutes les communes" = "", coms))
    } else {
      updateSelectInput(session, "filtre_commune", choices = c("Toutes les communes" = ""))
    }
  })

  observeEvent(input$btn_reinitialiser, {
    updateSelectInput(session, "filtre_region",      selected = "")
    updateSelectInput(session, "filtre_departement", selected = "")
    updateSelectInput(session, "filtre_commune",     selected = "")
  })

  # ── DONNÉES PÉRIMÈTRE UTILISATEUR ──────────────────────────────────────────
  # Tous les autres réactifs et UI partent de igl_data_scoped() au lieu de
  # igl_data directement. Permet à chaque utilisateur de voir uniquement les
  # données de son périmètre (régions/départements/communes autorisés).
  igl_data_scoped <- reactive({
    req(user_state$ok)
    apply_user_scope(igl_data,
                     user_state$data_regions,
                     user_state$data_departements,
                     user_state$data_communes)
  })

  # Agrégations recalculées sur le périmètre utilisateur
  regions_scores_user <- reactive({
    df <- igl_data_scoped()
    df %>%
      group_by(region_name) %>%
      summarise(
        nb_communes = n(),
        d1_score    = round(mean(d1_score, na.rm = TRUE), 2),
        d2_score    = round(mean(d2_score, na.rm = TRUE), 2),
        d3_score    = round(mean(d3_score, na.rm = TRUE), 2),
        d4_score    = round(mean(d4_score, na.rm = TRUE), 2),
        igl_score   = round(mean(igl_score, na.rm = TRUE), 2),
        .groups     = "drop"
      ) %>%
      mutate(igl_interpretation = get_interpretation(igl_score))
  })

  # ── DONNÉES FILTRÉES ───────────────────────────────────────────────────────
  donnees_filtrees <- reactive({
    df <- igl_data_scoped()
    if (nchar(input$filtre_region)      > 0) df <- df %>% filter(region_name      == input$filtre_region)
    if (nchar(input$filtre_departement) > 0) df <- df %>% filter(division_name    == input$filtre_departement)
    if (nchar(input$filtre_commune)     > 0) df <- df %>% filter(subdivision_name == input$filtre_commune)
    df
  })

  region_selectionnee <- reactive({
    if (nchar(input$filtre_region) > 0) {
      input$filtre_region
    } else {
      regs <- sort(unique(igl_data_scoped()$region_name))
      if (length(regs) > 0) regs[1] else ""
    }
  })

  dept_selectionne <- reactive({
    if (nchar(input$filtre_departement) > 0) {
      input$filtre_departement
    } else {
      deps <- igl_data_scoped() %>%
        filter(region_name == region_selectionnee()) %>%
        pull(division_name) %>% unique() %>% sort()
      if (length(deps) > 0) deps[1] else ""
    }
  })

  commune_selectionnee <- reactive({
    if (nchar(input$filtre_commune) > 0) {
      input$filtre_commune
    } else {
      coms <- igl_data_scoped() %>% filter(division_name == dept_selectionne()) %>%
        pull(subdivision_name) %>% unique() %>% sort()
      if (length(coms) > 0) coms[1] else ""
    }
  })

  # ── HELPER : graphique radar (scatterpolar) avec correction plotly ─────────
  # FIX : ajout explicite de mode = "lines+markers" pour éviter les 2 warnings plotly
  make_radar <- function(r_vals, theta_labels, nom, fill_color, line_color) {
    # Fermer le polygone
    r_closed     <- c(r_vals, r_vals[1])
    theta_closed <- c(theta_labels, theta_labels[1])

    plot_ly(
      type      = "scatterpolar",
      mode      = "lines+markers",          # ← FIX: évite "No mode specified" + "lines not in mode"
      fill      = "toself",
      fillcolor = fill_color,
      r         = r_closed,
      theta     = theta_closed,
      name      = nom,
      line      = list(color = line_color, width = 2),
      marker    = list(size = 7, color = line_color)
    ) %>%
      layout(
        polar = list(
          radialaxis = list(
            visible  = TRUE,
            range    = c(0, 1),
            tickvals = c(0, 0.25, 0.5, 0.75, 1),
            tickfont = list(size = 9)
          ),
          angularaxis = list(tickfont = list(size = 11))
        ),
        showlegend     = TRUE,
        margin         = list(t = 30, b = 30, l = 60, r = 60),
        paper_bgcolor  = "transparent",
        plot_bgcolor   = "transparent"
      )
  }

  THETA_DOMAINES <- c("D1 Administrative", "D2 Financière",
                      "D3 Participative", "D4 Compétences")

  # ── ──────────────────────────────────────────────────────────────────────
  # ONGLET 1 : VUE NATIONALE
  # ── ──────────────────────────────────────────────────────────────────────

  output$kpi_igl_national <- renderUI({
    score  <- round(mean(donnees_filtrees()$igl_score, na.rm = TRUE), 2)
    interp <- get_interpretation(score)
    col    <- if (score >= 0.6) "green" else if (score >= 0.4) "orange" else "red"
    kpi_box(paste0(format_score(score), " / 1"), paste("Score IGL Moyen —", interp), "tachometer-alt", col)
  })

  output$kpi_nb_communes <- renderUI({
    kpi_box(nrow(donnees_filtrees()), "Communes Évaluées", "city", "blue")
  })

  output$kpi_meilleure_region <- renderUI({
    df <- donnees_filtrees() %>% group_by(region_name) %>%
      summarise(s = mean(igl_score, na.rm = TRUE), .groups = "drop") %>% arrange(desc(s))
    if (nrow(df) > 0)
      kpi_box(paste0(df$region_name[1], " (", format_score(df$s[1]), ")"),
              "Meilleure Région", "award", "green")
    else kpi_box("N/A", "Meilleure Région", "award", "green")
  })

  output$kpi_region_attention <- renderUI({
    df <- donnees_filtrees() %>% group_by(region_name) %>%
      summarise(s = mean(igl_score, na.rm = TRUE), .groups = "drop") %>% arrange(s)
    if (nrow(df) > 0)
      kpi_box(paste0(df$region_name[1], " (", format_score(df$s[1]), ")"),
              "Région à Surveiller", "exclamation-triangle", "red")
    else kpi_box("N/A", "Région à Surveiller", "exclamation-triangle", "red")
  })

  # Carte nationale
  output$carte_nationale <- renderLeaflet({
    map_data <- regions_scores_user() %>%
      left_join(COORDS_REGIONS, by = "region_name")

    pal <- colorFactor(palette = unname(couleurs_perf),
                       levels  = niveaux_perf, ordered = TRUE)

    leaflet(map_data) %>%
      addProviderTiles(providers$CartoDB.Positron) %>%
      setView(lng = 12.3, lat = 5.95, zoom = 6) %>%
      addCircleMarkers(
        lng         = ~lng, lat = ~lat,
        radius      = ~igl_score * 32,
        # FIX : map_couleurs() retourne un vecteur sans noms (unnamed)
        color       = ~map_couleurs(igl_interpretation),
        fillColor   = ~map_couleurs(igl_interpretation),
        fillOpacity = 0.72,
        stroke      = TRUE, weight = 2,
        popup = ~paste0(
          "<div style='font-family:Arial;'>",
          "<b style='font-size:14px;'>", region_name, "</b><br>",
          "<hr style='margin:5px 0;'>",
          "Score IGL : <b>", format_score(igl_score), "</b> — ", igl_interpretation, "<br>",
          "Communes : ", nb_communes, "<br>",
          "<hr style='margin:5px 0;'>",
          "D1 Admin : ", format_score(d1_score), " | D2 Finance : ", format_score(d2_score), "<br>",
          "D3 Particip : ", format_score(d3_score), " | D4 Compét : ", format_score(d4_score),
          "</div>"
        ),
        label = ~paste0(region_name, " : ", format_score(igl_score))
      ) %>%
      addLegend(
        position = "bottomright",
        colors   = unname(couleurs_perf),
        labels   = niveaux_perf,
        title    = "Performance IGL",
        opacity  = 0.85
      )
  })

  # Pie chart performance nationale
  output$pie_perf_nationale <- renderPlotly({
    df <- donnees_filtrees() %>%
      mutate(igl_interpretation = factor(igl_interpretation, levels = niveaux_perf)) %>%
      count(igl_interpretation, .drop = FALSE) %>% filter(n > 0)

    # FIX jsonlite : unname() sur le vecteur de couleurs
    colors_vec <- unname(couleurs_perf[as.character(df$igl_interpretation)])

    plot_ly(df, labels = ~igl_interpretation, values = ~n, type = "pie",
            hole = 0.45, textinfo = "label+value",
            textposition = "outside", textfont = list(size = 11),
            marker = list(colors = colors_vec,
                          line   = list(color = "#FFFFFF", width = 2))) %>%
      layout(showlegend = TRUE,
             legend      = list(orientation = "h", x = 0, y = -0.2, font = list(size = 10)),
             margin      = list(t = 10, b = 40, l = 10, r = 10),
             paper_bgcolor = "transparent", plot_bgcolor = "transparent")
  })

  # Barres par région
  output$bar_regions <- renderPlotly({
    df <- donnees_filtrees() %>%
      group_by(region_name) %>%
      summarise(igl_score = round(mean(igl_score, na.rm = TRUE), 2), .groups = "drop") %>%
      arrange(igl_score)

    # FIX jsonlite : unname()
    bar_colors <- unname(couleurs_perf[get_interpretation(df$igl_score)])

    plot_ly(df, x = ~igl_score, y = ~reorder(region_name, igl_score),
            type = "bar", orientation = "h",
            text = ~format_score(igl_score), textposition = "outside",
            textfont = list(size = 11, color = IGL_BLEU),
            marker = list(color = bar_colors,
                          line  = list(color = "#FFFFFF", width = 0.5))) %>%
      layout(xaxis = list(title = "Score IGL", range = c(0, 1.1),
                          showgrid = TRUE, gridcolor = "#F0F0F0"),
             yaxis  = list(title = ""),
             margin = list(t = 5, b = 30, l = 5, r = 50),
             paper_bgcolor = "transparent", plot_bgcolor = "transparent")
  })

  # Tableau régions
  output$table_regions <- renderDT({
    df <- regions_scores_user() %>%
      select(region_name, nb_communes, d1_score, d2_score, d3_score, d4_score,
             igl_score, igl_interpretation) %>%
      arrange(desc(igl_score))

    datatable(df,
      colnames  = c("Région","Communes","D1 Admin","D2 Finance",
                    "D3 Particip.","D4 Compét.","IGL","Interprétation"),
      options   = list(pageLength = 10, dom = "tip", scrollX = TRUE),
      rownames  = FALSE
    ) %>%
      formatStyle("igl_score",
        backgroundColor = styleInterval(c(0.2, 0.4, 0.6, 0.8),
          c("#FFCCCC","#FFE0B2","#FFF9C4","#C8E6C9","#A5D6A7"))) %>%
      formatRound(columns = c("d1_score","d2_score","d3_score","d4_score","igl_score"), digits = 2)
  })

  output$interpretation_nationale <- renderUI({
    score  <- round(mean(donnees_filtrees()$igl_score, na.rm = TRUE), 2)
    interp <- get_interpretation(score)
    moy <- donnees_filtrees() %>%
      summarise(d1 = mean(d1_score), d2 = mean(d2_score),
                d3 = mean(d3_score), d4 = mean(d4_score))
    faibles <- c()
    if (moy$d1 < 0.6) faibles <- c(faibles, "Gouvernance Administrative")
    if (moy$d2 < 0.6) faibles <- c(faibles, "Gouvernance Financière")
    if (moy$d3 < 0.6) faibles <- c(faibles, "Gouvernance Participative")
    if (moy$d4 < 0.6) faibles <- c(faibles, "Compétences Transférées")

    tags$div(class = "synthesis-box",
      tags$h4(style = "color:#2D6A4F;", "Synthèse Nationale"),
      tags$p(tags$b("Score IGL moyen : "), format_score(score), " — ", tags$b(interp)),
      if (length(faibles) > 0)
        tags$p(tags$b("Domaines à renforcer : "), paste(faibles, collapse = ", ")),
      tags$p(tags$b("Recommandation : "),
        if (score >= 0.6) "Poursuivre les efforts et cibler les régions les moins performantes."
        else "Renforcer l'accompagnement technique dans les régions à faible performance.")
    )
  })

  # ── ──────────────────────────────────────────────────────────────────────
  # ONGLET 2 : ANALYSE RÉGIONALE
  # ── ──────────────────────────────────────────────────────────────────────

  donnees_region <- reactive({
    igl_data_scoped() %>% filter(region_name == region_selectionnee())
  })

  output$kpi_region_score <- renderUI({
    score  <- round(mean(donnees_region()$igl_score, na.rm = TRUE), 2)
    interp <- get_interpretation(score)
    col    <- if (score >= 0.6) "green" else if (score >= 0.4) "orange" else "red"
    kpi_box(paste0(format_score(score), " — ", interp),
            paste("Région", region_selectionnee()), "map", col)
  })

  output$kpi_region_nb_dept <- renderUI({
    n <- donnees_region() %>% pull(division_name) %>% unique() %>% length()
    kpi_box(n, "Départements", "map-marker-alt", "blue")
  })

  output$kpi_region_meilleur_dept <- renderUI({
    df <- donnees_region() %>% group_by(division_name) %>%
      summarise(s = mean(igl_score, na.rm = TRUE), .groups = "drop") %>% arrange(desc(s))
    if (nrow(df) > 0)
      kpi_box(paste0(df$division_name[1], " (", format_score(df$s[1]), ")"),
              "Meilleur Département", "arrow-up", "green")
  })

  output$kpi_region_faible_dept <- renderUI({
    df <- donnees_region() %>% group_by(division_name) %>%
      summarise(s = mean(igl_score, na.rm = TRUE), .groups = "drop") %>% arrange(s)
    if (nrow(df) > 0)
      kpi_box(paste0(df$division_name[1], " (", format_score(df$s[1]), ")"),
              "Département à Surveiller", "exclamation-triangle", "red")
  })

  output$bar_dept_region <- renderPlotly({
    df <- donnees_region() %>%
      group_by(division_name) %>%
      summarise(igl_score = round(mean(igl_score, na.rm = TRUE), 2), .groups = "drop") %>%
      arrange(igl_score)

    plot_ly(df, x = ~igl_score, y = ~reorder(division_name, igl_score),
            type = "bar", orientation = "h",
            text = ~format_score(igl_score), textposition = "outside",
            textfont = list(size = 11),
            # FIX jsonlite
            marker = list(color = unname(couleurs_perf[get_interpretation(df$igl_score)]))) %>%
      layout(xaxis  = list(title = "Score IGL", range = c(0, 1.1)),
             yaxis  = list(title = ""),
             margin = list(t = 5, b = 30, l = 5, r = 50),
             paper_bgcolor = "transparent", plot_bgcolor = "transparent")
  })

  output$radar_region <- renderPlotly({
    df <- donnees_region() %>%
      summarise(d1 = mean(d1_score, na.rm = TRUE), d2 = mean(d2_score, na.rm = TRUE),
                d3 = mean(d3_score, na.rm = TRUE), d4 = mean(d4_score, na.rm = TRUE))
    # FIX : make_radar() inclut mode = "lines+markers"
    make_radar(c(df$d1, df$d2, df$d3, df$d4), THETA_DOMAINES,
               region_selectionnee(), "rgba(45,106,79,0.25)", IGL_VERT)
  })

  output$table_dept_region <- renderDT({
    df <- donnees_region() %>%
      group_by(division_name) %>%
      summarise(nb = n(), d1 = round(mean(d1_score), 2), d2 = round(mean(d2_score), 2),
                d3 = round(mean(d3_score), 2), d4 = round(mean(d4_score), 2),
                igl = round(mean(igl_score), 2), .groups = "drop") %>%
      mutate(interp = get_interpretation(igl)) %>% arrange(desc(igl))

    datatable(df,
      colnames = c("Département","Communes","D1","D2","D3","D4","IGL","Interprétation"),
      options  = list(pageLength = 15, dom = "tip"), rownames = FALSE
    ) %>%
      formatStyle("igl", backgroundColor = styleInterval(c(0.2, 0.4, 0.6, 0.8),
        c("#FFCCCC","#FFE0B2","#FFF9C4","#C8E6C9","#A5D6A7")))
  })

  output$interpretation_regionale <- renderUI({
    df    <- donnees_region()
    score <- round(mean(df$igl_score, na.rm = TRUE), 2)
    interp <- get_interpretation(score)
    moy <- df %>% summarise(d1 = mean(d1_score), d2 = mean(d2_score),
                             d3 = mean(d3_score), d4 = mean(d4_score))
    faibles <- c()
    if (moy$d1 < 0.6) faibles <- c(faibles, paste0("Gouv. Admin. (", round(moy$d1, 2), ")"))
    if (moy$d2 < 0.6) faibles <- c(faibles, paste0("Gouv. Fin. (", round(moy$d2, 2), ")"))
    if (moy$d3 < 0.6) faibles <- c(faibles, paste0("Gouv. Part. (", round(moy$d3, 2), ")"))
    if (moy$d4 < 0.6) faibles <- c(faibles, paste0("Compét. Trans. (", round(moy$d4, 2), ")"))

    tags$div(class = "synthesis-box",
      tags$h4(style = "color:#2D6A4F;", paste("Synthèse —", region_selectionnee())),
      tags$p(tags$b("Score IGL régional : "), format_score(score), " — ", tags$b(interp)),
      tags$p(tags$b("Communes évaluées : "), nrow(df)),
      if (length(faibles) > 0)
        tags$p(tags$b("Domaines à renforcer : "), paste(faibles, collapse = " | "))
    )
  })

  # ── ──────────────────────────────────────────────────────────────────────
  # ONGLET 3 : ANALYSE DÉPARTEMENTALE
  # ── ──────────────────────────────────────────────────────────────────────

  donnees_dept <- reactive({
    igl_data_scoped() %>% filter(division_name == dept_selectionne())
  })

  output$kpi_dept_score <- renderUI({
    df <- donnees_dept()
    if (nrow(df) == 0) return(kpi_box("N/A", "Sélectionnez un département", "map-marker-alt", "blue"))
    score <- round(mean(df$igl_score, na.rm = TRUE), 2)
    col   <- if (score >= 0.6) "green" else if (score >= 0.4) "orange" else "red"
    kpi_box(format_score(score), paste("Département", dept_selectionne()), "map-marker-alt", col)
  })

  output$kpi_dept_nb_com <- renderUI({
    kpi_box(nrow(donnees_dept()), "Communes", "city", "blue")
  })

  output$kpi_dept_meilleure_com <- renderUI({
    df <- donnees_dept() %>% arrange(desc(igl_score))
    if (nrow(df) > 0)
      kpi_box(paste0(df$subdivision_name[1], " (", format_score(df$igl_score[1]), ")"),
              "Meilleure Commune", "arrow-up", "green")
  })

  output$kpi_dept_faible_com <- renderUI({
    df <- donnees_dept() %>% arrange(igl_score)
    if (nrow(df) > 0)
      kpi_box(paste0(df$subdivision_name[1], " (", format_score(df$igl_score[1]), ")"),
              "Commune à Surveiller", "exclamation-triangle", "red")
  })

  output$bar_com_dept <- renderPlotly({
    df <- donnees_dept() %>% arrange(igl_score)
    plot_ly(df, x = ~igl_score, y = ~reorder(subdivision_name, igl_score),
            type = "bar", orientation = "h",
            text = ~format_score(igl_score), textposition = "outside",
            textfont = list(size = 10),
            # FIX jsonlite
            marker = list(color = unname(couleurs_perf[df$igl_interpretation]))) %>%
      layout(xaxis = list(title = "Score IGL", range = c(0, 1.1)),
             yaxis = list(title = "", tickfont = list(size = 9)),
             margin = list(t = 5, b = 30, l = 5, r = 50),
             paper_bgcolor = "transparent", plot_bgcolor = "transparent")
  })

  output$radar_dept <- renderPlotly({
    df <- donnees_dept() %>%
      summarise(d1 = mean(d1_score, na.rm = TRUE), d2 = mean(d2_score, na.rm = TRUE),
                d3 = mean(d3_score, na.rm = TRUE), d4 = mean(d4_score, na.rm = TRUE))
    make_radar(c(df$d1, df$d2, df$d3, df$d4), THETA_DOMAINES,
               dept_selectionne(), "rgba(29,53,87,0.25)", IGL_BLEU)
  })

  output$table_com_dept <- renderDT({
    df <- donnees_dept() %>%
      select(subdivision_name, d1_score, d2_score, d3_score, d4_score,
             igl_score, igl_interpretation) %>%
      arrange(desc(igl_score))

    datatable(df,
      colnames = c("Commune","D1 Admin","D2 Finance","D3 Particip.","D4 Compét.","IGL","Interprétation"),
      options  = list(pageLength = 15, dom = "tip"), rownames = FALSE
    ) %>%
      formatStyle("igl_score", backgroundColor = styleInterval(c(0.2, 0.4, 0.6, 0.8),
        c("#FFCCCC","#FFE0B2","#FFF9C4","#C8E6C9","#A5D6A7"))) %>%
      formatRound(columns = c("d1_score","d2_score","d3_score","d4_score","igl_score"), digits = 2)
  })

  output$interpretation_departementale <- renderUI({
    df <- donnees_dept()
    if (nrow(df) == 0) return(NULL)
    score  <- round(mean(df$igl_score, na.rm = TRUE), 2)
    interp <- get_interpretation(score)
    tags$div(class = "synthesis-box", style = "border-left-color:#1D3557;",
      tags$h4(style = "color:#1D3557;", paste("Synthèse —", dept_selectionne())),
      tags$p(tags$b("Score IGL départemental : "), format_score(score), " — ", tags$b(interp)),
      tags$p(tags$b("Communes évaluées : "), nrow(df))
    )
  })

  # ── ──────────────────────────────────────────────────────────────────────
  # ONGLET 4 : DÉTAIL COMMUNE
  # ── ──────────────────────────────────────────────────────────────────────

  donnees_commune <- reactive({
    com <- commune_selectionnee()
    if (nchar(com) == 0) return(NULL)
    igl_data_scoped() %>% filter(subdivision_name == com)
  })

  output$kpi_com_igl <- renderUI({
    df <- donnees_commune()
    if (is.null(df) || nrow(df) == 0)
      return(kpi_box("N/A", "Sélectionnez une commune", "city", "blue"))
    score <- df$igl_score[1]
    col   <- if (score >= 0.6) "green" else if (score >= 0.4) "orange" else "red"
    kpi_box(paste0(format_score(score), " — ", df$igl_interpretation[1]),
            "Score IGL Global", "tachometer-alt", col)
  })

  output$kpi_com_d1 <- renderUI({
    df <- donnees_commune()
    if (is.null(df) || nrow(df) == 0) return(kpi_box("N/A", "D1 Administrative", "building", "blue"))
    score <- df$d1_score[1]
    col <- if (score >= 0.6) "green" else if (score >= 0.4) "yellow" else "red"
    kpi_box(format_score(score), "D1 — Gouvernance Administrative", "building", col)
  })

  output$kpi_com_d2 <- renderUI({
    df <- donnees_commune()
    if (is.null(df) || nrow(df) == 0) return(kpi_box("N/A", "D2 Financière", "money-bill-alt", "blue"))
    score <- df$d2_score[1]
    col <- if (score >= 0.6) "green" else if (score >= 0.4) "yellow" else "red"
    kpi_box(format_score(score), "D2 — Gouvernance Financière", "money-bill-alt", col)
  })

  output$kpi_com_d3 <- renderUI({
    df <- donnees_commune()
    if (is.null(df) || nrow(df) == 0) return(kpi_box("N/A", "D3 Participative", "users", "blue"))
    score <- df$d3_score[1]
    col <- if (score >= 0.6) "green" else if (score >= 0.4) "yellow" else "red"
    kpi_box(format_score(score), "D3 — Gouvernance Participative", "users", col)
  })

  output$radar_commune <- renderPlotly({
    df <- donnees_commune()
    if (is.null(df) || nrow(df) == 0) return(plotly_empty())
    make_radar(c(df$d1_score[1], df$d2_score[1], df$d3_score[1], df$d4_score[1]),
               THETA_DOMAINES,
               df$subdivision_name[1],
               "rgba(45,106,79,0.28)", IGL_VERT)
  })

  output$bar_domaines_commune <- renderPlotly({
    df <- donnees_commune()
    if (is.null(df) || nrow(df) == 0) return(plotly_empty())

    domaines <- data.frame(
      domaine = c("D1 Administrative","D2 Financière","D3 Participative","D4 Compétences"),
      score   = c(df$d1_score[1], df$d2_score[1], df$d3_score[1], df$d4_score[1]),
      stringsAsFactors = FALSE
    ) %>% mutate(interp = get_interpretation(score))

    plot_ly(domaines, x = ~score, y = ~reorder(domaine, score),
            type = "bar", orientation = "h",
            text = ~format_score(score), textposition = "outside",
            textfont = list(size = 13, color = IGL_BLEU),
            # FIX jsonlite
            marker = list(color = unname(couleurs_perf[domaines$interp]))) %>%
      layout(xaxis  = list(title = "Score", range = c(0, 1.15)),
             yaxis  = list(title = ""),
             margin = list(t = 5, b = 30, l = 5, r = 50),
             paper_bgcolor = "transparent", plot_bgcolor = "transparent")
  })

  output$fiche_commune_complete <- renderUI({
    df <- donnees_commune()
    if (is.null(df) || nrow(df) == 0)
      return(tags$p(style = "padding:20px; color:#666;",
                    "Veuillez sélectionner une commune via les filtres de la barre latérale."))

    r <- df[1, ]
    col_igl <- if (r$igl_score >= 0.6) "#2D6A4F" else if (r$igl_score >= 0.4) "#F77F00" else "#CE1126"

    tags$div(
      # IGL Global
      tags$div(class = "commune-card",
               style = paste0("border-left-color:", col_igl, "; background:#F0FFF4;"),
        tags$h4(style = paste0("color:", col_igl, "; margin-top:0;"),
                paste0(r$subdivision_name, " — ", r$division_name, " / ", r$region_name)),
        fluidRow(
          column(6, tags$p(tags$b("Score IGL : "), format_score(r$igl_score),
                           " — ", tags$b(r$igl_interpretation))),
          column(6, tags$p(tags$b("Date évaluation : "), as.character(r$evaluation_date),
                           " | ", tags$b("Évaluateur : "), r$evaluateur))
        ),
        tags$p(tags$b("Recommandation globale : "), r$igl_recommandation),
        if (nchar(trimws(r$domaines_faibles)) > 0)
          tags$p(tags$b("Domaines à renforcer : "), r$domaines_faibles)
      ),

      # 4 domaines
      lapply(list(
        list(score = r$d1_score, interp = r$d1_interpretation, reco = r$d1_recommandation,
             label = "D1 — Gouvernance Administrative"),
        list(score = r$d2_score, interp = r$d2_interpretation, reco = r$d2_recommandation,
             label = "D2 — Gouvernance Financière"),
        list(score = r$d3_score, interp = r$d3_interpretation, reco = r$d3_recommandation,
             label = "D3 — Gouvernance Participative"),
        list(score = r$d4_score, interp = r$d4_interpretation, reco = r$d4_recommandation,
             label = "D4 — Compétences Transférées")
      ), function(dom) {
        bord_col <- unname(couleurs_perf[get_interpretation(dom$score)])
        tags$div(class = "commune-card",
                 style = paste0("border-left-color:", bord_col, ";"),
          tags$h5(paste0(dom$label, " : ", format_score(dom$score),
                         " (", dom$interp, ")")),
          tags$p(tags$i(dom$reco))
        )
      }),

      # Métadonnées
      tags$div(style = "padding:10px; background:#F5F5F5; border-radius:6px; font-size:12px; color:#666;",
        tags$i(class = "fa fa-file-audio", style = "margin-right:5px;"),
        tags$b("Audio : "), r$commentaire_audio
      )
    )
  })

  # ── ──────────────────────────────────────────────────────────────────────
  # ONGLET 5 : CLASSEMENT
  # ── ──────────────────────────────────────────────────────────────────────

  output$table_classement <- renderDT({
    df <- donnees_filtrees() %>%
      mutate(rang = rank(-igl_score, ties.method = "min")) %>%
      select(rang, subdivision_name, division_name, region_name,
             d1_score, d2_score, d3_score, d4_score, igl_score, igl_interpretation) %>%
      arrange(rang)

    datatable(df,
      colnames   = c("Rang","Commune","Département","Région",
                     "D1 Admin","D2 Finance","D3 Particip.","D4 Compét.","IGL","Interprétation"),
      options    = list(pageLength = 25, dom = "lfrtip", scrollX = TRUE,
                        order = list(list(0, "asc"))),
      rownames   = FALSE, filter = "top"
    ) %>%
      formatStyle("igl_score",
        backgroundColor = styleInterval(c(0.2, 0.4, 0.6, 0.8),
          c("#FFCCCC","#FFE0B2","#FFF9C4","#C8E6C9","#A5D6A7")),
        fontWeight = "bold") %>%
      formatRound(columns = c("d1_score","d2_score","d3_score","d4_score","igl_score"), digits = 2)
  })

  # ── ──────────────────────────────────────────────────────────────────────
  # ONGLET 6 : ANALYTIQUE (NOUVEAU)
  # ── ──────────────────────────────────────────────────────────────────────

  output$kpi_score_moyen <- renderUI({
    s <- round(mean(donnees_filtrees()$igl_score, na.rm = TRUE), 2)
    kpi_box(format_score(s), "Moyenne IGL", "chart-line", "green")
  })
  output$kpi_score_median <- renderUI({
    s <- round(median(donnees_filtrees()$igl_score, na.rm = TRUE), 2)
    kpi_box(format_score(s), "Médiane IGL", "equals", "blue")
  })
  output$kpi_score_max <- renderUI({
    df <- donnees_filtrees() %>% arrange(desc(igl_score))
    kpi_box(paste0(format_score(df$igl_score[1]), " (", df$subdivision_name[1], ")"),
            "Score Maximum", "arrow-up", "green")
  })
  output$kpi_score_min <- renderUI({
    df <- donnees_filtrees() %>% arrange(igl_score)
    kpi_box(paste0(format_score(df$igl_score[1]), " (", df$subdivision_name[1], ")"),
            "Score Minimum", "arrow-down", "red")
  })

  output$histo_igl <- renderPlotly({
    df <- donnees_filtrees()
    plot_ly(df, x = ~igl_score, type = "histogram",
            nbinsx = 20,
            marker = list(color = IGL_VERT, line = list(color = "white", width = 0.5))) %>%
      layout(xaxis  = list(title = "Score IGL", range = c(0, 1)),
             yaxis  = list(title = "Nombre de communes"),
             shapes = list(
               list(type = "line", x0 = mean(df$igl_score), x1 = mean(df$igl_score),
                    y0 = 0, y1 = 1, yref = "paper",
                    line = list(color = IGL_ROUGE, width = 2, dash = "dash"))
             ),
             annotations = list(list(
               x = mean(df$igl_score), y = 1, yref = "paper", xref = "x",
               text = paste0("Moy. ", format_score(mean(df$igl_score))),
               showarrow = FALSE, font = list(color = IGL_ROUGE, size = 11),
               xanchor = "left"
             )),
             paper_bgcolor = "transparent", plot_bgcolor = "transparent")
  })

  output$boxplot_regions <- renderPlotly({
    df <- donnees_filtrees() %>%
      mutate(region_name = factor(region_name, levels = sort(unique(region_name))))

    # Un seul appel plot_ly — pas de add_trace en boucle, pas de colors=setNames()
    # Plotly gère la palette discrète automatiquement par région (axe X uniforme)
    plot_ly(
      data          = df,
      x             = ~region_name,
      y             = ~igl_score,
      type          = "box",
      boxmean       = "sd",
      marker        = list(size = 3, opacity = 0.6),
      line          = list(color = IGL_VERT),
      fillcolor      = "rgba(45,106,79,0.25)",
      hovertemplate = "<b>%{x}</b><br>IGL : %{y:.2f}<extra></extra>"
    ) %>%
      layout(
        xaxis      = list(title = "", tickangle = -25, tickfont = list(size = 9)),
        yaxis      = list(title = "Score IGL", range = c(0, 1)),
        showlegend = FALSE,
        paper_bgcolor = "transparent", plot_bgcolor = "transparent"
      )
  })

  output$heatmap_domaines <- renderPlotly({
    df <- igl_data_scoped() %>%
      group_by(region_name) %>%
      summarise(D1 = round(mean(d1_score), 2), D2 = round(mean(d2_score), 2),
                D3 = round(mean(d3_score), 2), D4 = round(mean(d4_score), 2),
                .groups = "drop") %>%
      arrange(region_name)

    mat <- as.matrix(df[, c("D1","D2","D3","D4")])
    rownames(mat) <- df$region_name

    plot_ly(
      x         = colnames(mat),
      y         = rownames(mat),
      z         = mat,
      type      = "heatmap",
      colorscale = list(
        list(0, "#D62828"), list(0.25, "#F77F00"),
        list(0.5, "#FCBF49"), list(0.75, "#40916C"), list(1, "#2D6A4F")
      ),
      zmin     = 0, zmax = 1,
      text     = matrix(sprintf("%.2f", mat), nrow = nrow(mat)),
      texttemplate = "%{text}",
      hoverongaps  = FALSE
    ) %>%
      layout(xaxis  = list(title = "Domaine"),
             yaxis  = list(title = "Région"),
             margin = list(t = 10, b = 40, l = 130, r = 10),
             paper_bgcolor = "transparent")
  })

  output$bar_perf_stacked <- renderPlotly({
    df_raw      <- donnees_filtrees()
    all_regions <- sort(unique(df_raw$region_name))

    # Grille complète région × niveau (replace_na = 0 pour cellules vides)
    grille <- expand.grid(
      region_name        = all_regions,
      igl_interpretation = niveaux_perf,
      stringsAsFactors   = FALSE
    ) %>%
      left_join(
        df_raw %>%
          group_by(region_name, igl_interpretation) %>%
          summarise(n = n(), .groups = "drop"),
        by = c("region_name", "igl_interpretation")
      ) %>%
      mutate(
        n = replace_na(n, 0L),
        # Facteur pour imposer l'ordre d'empilement
        igl_interpretation = factor(igl_interpretation, levels = niveaux_perf)
      )

    # Un SEUL plot_ly() avec color = ~igl_interpretation → axe X unique et cohérent
    plot_ly(
      data   = grille,
      x      = ~region_name,
      y      = ~n,
      color  = ~igl_interpretation,
      colors = unname(couleurs_perf[niveaux_perf]),   # vecteur non-nommé, ordre = niveaux_perf
      type   = "bar",
      hovertemplate = "<b>%{x}</b> — %{fullData.name}<br>Communes : %{y}<extra></extra>"
    ) %>%
      layout(
        barmode  = "stack",
        xaxis    = list(title = "", tickangle = -25, tickfont = list(size = 9)),
        yaxis    = list(title = "Communes"),
        legend   = list(orientation = "h", y = -0.28, traceorder = "reversed",
                        font = list(size = 11)),
        paper_bgcolor = "transparent", plot_bgcolor = "transparent"
      )
  })

  output$table_top10 <- renderDT({
    df <- donnees_filtrees() %>%
      arrange(desc(igl_score)) %>%
      head(10) %>%
      select(subdivision_name, division_name, region_name, igl_score, igl_interpretation)
    datatable(df, colnames = c("Commune","Départ.","Région","IGL","Interprétation"),
              options = list(dom = "t", pageLength = 10), rownames = FALSE) %>%
      formatStyle("igl_score", backgroundColor = "#C8E6C9", fontWeight = "bold") %>%
      formatRound("igl_score", digits = 2)
  })

  output$table_bottom10 <- renderDT({
    df <- donnees_filtrees() %>%
      arrange(igl_score) %>%
      head(10) %>%
      select(subdivision_name, division_name, region_name, igl_score, igl_interpretation)
    datatable(df, colnames = c("Commune","Départ.","Région","IGL","Interprétation"),
              options = list(dom = "t", pageLength = 10), rownames = FALSE) %>%
      formatStyle("igl_score", backgroundColor = "#FFCCCC", fontWeight = "bold") %>%
      formatRound("igl_score", digits = 2)
  })

  # ── ──────────────────────────────────────────────────────────────────────
  # ONGLET 7 : EXPORT
  # ── ──────────────────────────────────────────────────────────────────────

  output$export_permission_notice <- renderUI({
    if (!isTRUE(user_state$can_download)) {
      tags$div(class = "alert alert-warning",
               style = "margin:10px 0;",
        tags$i(class = "fa fa-lock", style = "margin-right:8px;"),
        tags$b("Accès limité :"),
        " Votre rôle (Visualiseur) ne permet pas de télécharger les données.",
        " Contactez un administrateur pour obtenir les droits Évaluateur ou Administrateur."
      )
    } else NULL
  })

  # Bouton Rapport HTML
  output$btn_dl_rapport <- renderUI({
    req(user_state$ok)
    if (isTRUE(user_state$can_download)) {
      downloadButton("dl_rapport_html",
                     tagList(icon("file-alt"), " Télécharger le Rapport HTML"),
                     class = "btn-success",
                     style = "width:100%;")
    } else {
      tags$button(
        class = "btn btn-default btn-block",
        disabled = "disabled",
        tags$i(class = "fa fa-lock"),
        " Téléchargement non autorisé - Contactez l'administrateur"
      )
    }
  })

  # Bouton CSV
  output$btn_dl_csv <- renderUI({
    req(user_state$ok)

    if (isTRUE(user_state$can_download)) {
      downloadButton("dl_donnees_csv",
                     tagList(icon("file-alt"), " Télécharger les Données CSV"),
                     class = "btn-primary",
                     style = "width:100%;")
    } else {
      tags$button(
        class = "btn btn-default btn-block",
        disabled = "disabled",
        tags$i(class = "fa fa-lock"),
        " Téléchargement non autorisé"
      )
    }
  })

  # Bouton Classement CSV
  output$btn_dl_classement <- renderUI({
    req(user_state$ok)

    if (isTRUE(user_state$can_download)) {
      tagList(
        tags$br(),
        downloadButton("dl_classement_csv",
                       tagList(icon("trophy"), " Télécharger le Classement CSV"),
                       class = "btn-info",
                       style = "width:100%;")
      )
    } else {
      NULL
    }
  })
  
  # Rapport HTML commune
  output$dl_rapport_html <- downloadHandler(
    filename = function() {
      paste0("Rapport_IGL_", gsub(" ", "_", input$export_commune_select),
             "_", Sys.Date(), ".html")
    },
    content = function(file) {
      # Vérification explicite
      if (!isTRUE(user_state$can_download)) {
        stop("Permission non accordée pour télécharger ce rapport")
      }
      # req(isTRUE(user_state$can_download))
      com <- igl_data_scoped() %>% filter(subdivision_name == input$export_commune_select)
      if (nrow(com) == 0) { writeLines("<html><body><h1>Commune non trouvée</h1></body></html>", file); return() }
      r <- com[1, ]

      score_class <- if (r$igl_score >= 0.6) "green" else if (r$igl_score >= 0.4) "orange" else "red"

      html_content <- paste0('
<!DOCTYPE html><html lang="fr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Rapport IGL — ', r$subdivision_name, '</title>
  <style>
    * { box-sizing: border-box; }
    body { font-family: Arial, sans-serif; max-width: 960px; margin: 0 auto; padding: 20px; color: #333; background: #F4F6F9; }
    .header { background: linear-gradient(135deg, #2D6A4F, #1D3557); color: white; padding: 25px; border-radius: 10px; margin-bottom: 25px; }
    .header h1 { margin: 0 0 5px; font-size: 22px; }
    .header p { margin: 4px 0; font-size: 13px; opacity: 0.9; }
    .score-block { display: inline-block; padding: 12px 22px; border-radius: 10px; font-size: 22px; font-weight: bold; color: white; margin: 10px 5px 15px; }
    .score-block.green { background: #2D6A4F; } .score-block.orange { background: #F77F00; } .score-block.red { background: #CE1126; }
    .card { background: white; border-radius: 8px; padding: 18px; margin-bottom: 15px; box-shadow: 0 2px 6px rgba(0,0,0,0.08); border-left: 4px solid #2D6A4F; }
    .card h3 { margin: 0 0 10px; font-size: 15px; color: #1D3557; }
    table { width: 100%; border-collapse: collapse; margin: 15px 0; font-size: 13px; }
    th { background: #2D6A4F; color: white; padding: 10px 12px; text-align: left; }
    td { padding: 8px 12px; border-bottom: 1px solid #E8E8E8; }
    tr:nth-child(even) td { background: #F9F9F9; }
    .footer { text-align: center; margin-top: 30px; padding: 15px; border-top: 2px solid #2D6A4F; color: #888; font-size: 11px; }
    .badge { display: inline-block; padding: 2px 10px; border-radius: 12px; font-size: 12px; font-weight: 600; color: white; }
    .badge.green { background: #2D6A4F; } .badge.orange { background: #F77F00; } .badge.red { background: #CE1126; }
  </style>
</head>
<body>
  <div class="header">
    <h1>Rapport d\'Évaluation — Indice de Gouvernance Locale</h1>
    <p><b>Commune :</b> ', r$subdivision_name, ' &nbsp;|&nbsp; <b>Département :</b> ', r$division_name, ' &nbsp;|&nbsp; <b>Région :</b> ', r$region_name, '</p>
    <p><b>Date :</b> ', as.character(r$evaluation_date), ' &nbsp;|&nbsp; <b>Évaluateur :</b> ', r$evaluateur, ' &nbsp;|&nbsp; <b>Généré le :</b> ', format(Sys.Date(), "%d/%m/%Y"), '</p>
  </div>

  <div class="card">
    <h3>Score Global IGL</h3>
    <div class="score-block ', score_class, '">', sprintf("%.2f", r$igl_score), ' / 1 &nbsp;—&nbsp; ', r$igl_interpretation, '</div>
    <p><b>Recommandation :</b> ', r$igl_recommandation, '</p>',
    if (nchar(trimws(r$domaines_faibles)) > 0) paste0('<p><b>Domaines à renforcer :</b> ', r$domaines_faibles, '</p>') else "",
    '
  </div>

  <div class="card">
    <h3>Résultats par Domaine</h3>
    <table>
      <tr><th>Domaine</th><th>Score</th><th>Interprétation</th></tr>
      <tr><td>D1 — Gouvernance Administrative (35%)</td><td><b>', sprintf("%.2f", r$d1_score), '</b></td><td>', r$d1_interpretation, '</td></tr>
      <tr><td>D2 — Gouvernance Financière (25%)</td><td><b>', sprintf("%.2f", r$d2_score), '</b></td><td>', r$d2_interpretation, '</td></tr>
      <tr><td>D3 — Gouvernance Participative (25%)</td><td><b>', sprintf("%.2f", r$d3_score), '</b></td><td>', r$d3_interpretation, '</td></tr>
      <tr><td>D4 — Compétences Transférées (15%)</td><td><b>', sprintf("%.2f", r$d4_score), '</b></td><td>', r$d4_interpretation, '</td></tr>
    </table>
  </div>

  <div class="card"><h3>D1 — Gouvernance Administrative (', sprintf("%.2f", r$d1_score), ')</h3><p>', r$d1_recommandation, '</p></div>
  <div class="card"><h3>D2 — Gouvernance Financière (', sprintf("%.2f", r$d2_score), ')</h3><p>', r$d2_recommandation, '</p></div>
  <div class="card"><h3>D3 — Gouvernance Participative (', sprintf("%.2f", r$d3_score), ')</h3><p>', r$d3_recommandation, '</p></div>
  <div class="card"><h3>D4 — Compétences Transférées (', sprintf("%.2f", r$d4_score), ')</h3><p>', r$d4_recommandation, '</p></div>

  <div class="footer"><p>MINDDEVEL / PADGOF-GIZ — Indice de Gouvernance Locale | Dashboard v', APP_VERSION, ' | Généré le ', format(Sys.Date(), "%d/%m/%Y"), '</p></div>
</body></html>')

      writeLines(html_content, file)
      log_activity(isolate(user_state$login), "export_html",
                   paste0("Commune: ", input$export_commune_select))
    }
  )

  output$dl_donnees_csv <- downloadHandler(
    filename = function() paste0("Donnees_IGL_", Sys.Date(), ".csv"),
    content  = function(file) {
      # Vérification explicite
      if (!isTRUE(user_state$can_download)) {
        stop("Permission non accordée pour télécharger ce rapport")
      }
      # req(isTRUE(user_state$can_download))
      write.csv(donnees_filtrees(), file, row.names = FALSE, fileEncoding = "UTF-8")
      log_activity(isolate(user_state$login), "export_csv",
                   paste0("Filtres: reg=", input$filtre_region,
                          " dept=", input$filtre_departement))
    }
  )

  output$dl_classement_csv <- downloadHandler(
    filename = function() paste0("Classement_IGL_", Sys.Date(), ".csv"),
    content  = function(file) {
      # Vérification explicite
      if (!isTRUE(user_state$can_download)) {
        stop("Permission non accordée pour télécharger ce rapport")
      }
      # req(isTRUE(user_state$can_download))
      df <- donnees_filtrees() %>%
        mutate(rang = rank(-igl_score, ties.method = "min")) %>%
        select(rang, subdivision_name, division_name, region_name,
               d1_score, d2_score, d3_score, d4_score, igl_score, igl_interpretation) %>%
        arrange(rang)
      write.csv(df, file, row.names = FALSE, fileEncoding = "UTF-8")
      log_activity(isolate(user_state$login), "export_classement_csv", "")
    }
  )

  # ── ──────────────────────────────────────────────────────────────────────
  # ONGLET 8 : ADMINISTRATION
  # ── ──────────────────────────────────────────────────────────────────────

  # Statut synchronisation
  # ── DIAGNOSTIC DE SESSION (visible dans l'onglet Admin) ─────────────────────
  output$admin_session_debug <- renderUI({
    req(isTRUE(user_state$is_admin))
    tags$div(
      style = "background:#FFF8E1; border-left:4px solid #F77F00; padding:12px 16px; border-radius:6px; margin-bottom:15px; font-family:monospace; font-size:11px;",
      tags$div(style = "font-weight:700; color:#E65100; font-size:13px; margin-bottom:8px;",
               tags$i(class = "fa fa-bug", style = "margin-right:6px;"),
               "DIAGNOSTIC DE SESSION"),
      tags$div("user_state$ok           = ",      tags$b(as.character(user_state$ok))),
      tags$div("user_state$login        = ",      tags$b(user_state$login)),
      tags$div("user_state$name         = ",      tags$b(user_state$name)),
      tags$div("user_state$permissions  = ",      tags$b(user_state$permissions)),
      tags$div("user_state$is_admin     = ",      tags$b(as.character(user_state$is_admin))),
      tags$div("user_state$can_download = ",      tags$b(as.character(user_state$can_download))),
      tags$div("user_state$data_regions      = ", tags$b(paste(user_state$data_regions,      collapse = ", "))),
      tags$div("user_state$data_departements = ", tags$b(paste(user_state$data_departements, collapse = ", "))),
      tags$div("user_state$data_communes     = ", tags$b(paste(user_state$data_communes,     collapse = ", "))),
      tags$div(style = "margin-top:6px; color:#666; font-size:10px;",
               "Lignes accessibles via igl_data_scoped : ", tags$b(nrow(igl_data_scoped())),
               " / total ", tags$b(nrow(igl_data)))
    )
  })

  output$admin_sync_status <- renderUI({
    req(isTRUE(user_state$is_admin))
    si <- sync_rv()

    icon_name <- switch(si$status,
      success = "check-circle", demo = "flask", fallback = "exclamation-triangle",
      kobo_error = "times-circle", "redo")
    color <- switch(si$status,
      success = "#2D6A4F", demo = "#1D3557", fallback = "#F77F00",
      kobo_error = "#CE1126", "#546E7A")

    tags$div(
      tags$div(
        style = paste0("padding:15px; background:#F8F9FA; border-radius:8px;",
                       " border-left:4px solid ", color, ";"),
        tags$div(
          style = paste0("font-size:14px; font-weight:700; color:", color, ";"),
          tags$i(class = paste0("fa fa-", icon_name), style = "margin-right:8px;"),
          toupper(si$status)
        ),
        tags$p(style = "margin:8px 0 4px; font-size:13px;", si$message),
        if (!is.null(si$timestamp))
          tags$p(style = "font-size:11px; color:#666; margin:0;",
                 paste0("Dernière vérification : ", format(si$timestamp, "%d/%m/%Y à %H:%M:%S")))
      ),
      tags$div(style = "margin-top:12px;",
        tags$p(style = "font-size:12px; color:#666;",
          "Communes chargées : ", tags$b(nrow(igl_data)),
          " | Régions : ", tags$b(length(liste_regions)),
          " | Départements : ", tags$b(length(liste_departements))
        )
      )
    )
  })

  # Synchronisation KoboToolbox manuelle
  observeEvent(input$btn_sync_kobo, {
    req(isTRUE(user_state$is_admin))
    showNotification("Synchronisation KoboToolbox en cours...", type = "message", duration = NULL,
                     id = "notif_sync")
    tryCatch({
      new_info <- charger_donnees(force_kobo = TRUE)
      sync_rv(new_info)

      # Mettre à jour les listes de filtres
      liste_regions      <<- sort(unique(igl_data$region_name))
      liste_departements <<- sort(unique(igl_data$division_name))
      liste_communes     <<- sort(unique(igl_data$subdivision_name))
      # Re-filtrer selon le périmètre de l'utilisateur courant
      df_scope <- apply_user_scope(igl_data,
                                   user_state$data_regions,
                                   user_state$data_departements,
                                   user_state$data_communes)

      updateSelectInput(session, "filtre_region",
                        choices = c("Toutes les régions" = "",
                                    sort(unique(df_scope$region_name))))
      updateSelectInput(session, "export_commune_select",
                        choices = sort(unique(df_scope$subdivision_name)))

      removeNotification("notif_sync")
      showNotification(paste0("✅ Synchronisation réussie : ", nrow(igl_data), " communes."),
                       type = "message", duration = 5)
      log_activity(user_state$login, "sync_kobo",
                   paste0("Résultat: ", nrow(igl_data), " communes"))

    }, error = function(e) {
      removeNotification("notif_sync")
      showNotification(paste0("❌ Erreur sync: ", conditionMessage(e)),
                       type = "error", duration = 8)
      log_activity(user_state$login, "sync_kobo_error", conditionMessage(e))
    })
  })

  # Tableau utilisateurs (lecture depuis la DB shinymanager)
  admin_users_rv <- reactiveVal(NULL)

  observe({
    req(isTRUE(user_state$is_admin))
    tryCatch({
      conn <- DBI::dbConnect(RSQLite::SQLite(), CREDS_DB)
      on.exit(DBI::dbDisconnect(conn), add = TRUE)
      users_raw <- shinymanager::read_db_decrypt(
        conn       = conn,
        name       = "credentials",
        passphrase = CREDS_PASSPHRASE
      )
      admin_users_rv(users_raw)
    }, error = function(e) {
      admin_users_rv(data.frame(Erreur = conditionMessage(e)))
    })
  })

  output$admin_users_table <- renderDT({
    req(isTRUE(user_state$is_admin))
    df <- admin_users_rv()
    if (is.null(df)) return(NULL)

    # Construction d'un résumé visuel du périmètre
    format_scope <- function(regs, deps, coms) {
      regs <- if (is.na(regs) || nchar(regs) == 0) character(0) else strsplit(regs, ";")[[1]]
      deps <- if (is.na(deps) || nchar(deps) == 0) character(0) else strsplit(deps, ";")[[1]]
      coms <- if (is.na(coms) || nchar(coms) == 0) character(0) else strsplit(coms, ";")[[1]]
      if (length(coms) > 0) return(paste0(length(coms), " commune(s)"))
      if (length(deps) > 0) return(paste0(length(deps), " département(s)"))
      if (length(regs) > 0) return(paste0(length(regs), " région(s)"))
      "Toutes les données"
    }

    # Colonnes à afficher
    display <- df %>%
      mutate(
        perimetre = mapply(format_scope,
                            df$data_regions      %||% rep("", nrow(df)),
                            df$data_departements %||% rep("", nrow(df)),
                            df$data_communes     %||% rep("", nrow(df)))
      ) %>%
      select(any_of(c("user","name","permissions","admin","perimetre","start","expire")))

    col_labels <- c("Identifiant","Nom","Permissions","Admin","Périmètre","Début","Expiration")

    datatable(display,
      colnames  = col_labels[seq_len(ncol(display))],
      options   = list(pageLength = 15, dom = "tip", scrollX = TRUE),
      rownames  = FALSE
    )
  })

  # Ajout d'un utilisateur
  output$admin_user_msg <- renderUI(NULL)

  # ── Cascade des sélecteurs de périmètre du formulaire admin ──────────────
  # Régions choisies → liste des départements disponibles
  observeEvent(input$new_user_regions, {
    regs <- input$new_user_regions
    if (is.null(regs) || length(regs) == 0) {
      # Aucune région → tous les départements
      deps <- sort(unique(igl_data$division_name))
    } else {
      deps <- igl_data %>% filter(region_name %in% regs) %>%
        pull(division_name) %>% unique() %>% sort()
    }
    updateSelectizeInput(session, "new_user_departements",
                         choices  = deps,
                         selected = intersect(input$new_user_departements, deps),
                         options  = list(placeholder = "(Tous les départements)",
                                         plugins = list("remove_button")))
  }, ignoreNULL = FALSE, ignoreInit = TRUE)

  # Régions ou départements choisis → liste des communes disponibles
  observeEvent({ input$new_user_regions; input$new_user_departements }, {
    regs <- input$new_user_regions
    deps <- input$new_user_departements

    df <- igl_data
    if (!is.null(regs) && length(regs) > 0) df <- df %>% filter(region_name   %in% regs)
    if (!is.null(deps) && length(deps) > 0) df <- df %>% filter(division_name %in% deps)
    coms <- sort(unique(df$subdivision_name))

    updateSelectizeInput(session, "new_user_communes",
                         choices  = coms,
                         selected = intersect(input$new_user_communes, coms),
                         options  = list(placeholder = "(Toutes les communes)",
                                         plugins = list("remove_button")))
  }, ignoreNULL = FALSE, ignoreInit = TRUE)

  observeEvent(input$btn_add_user, {
    req(isTRUE(user_state$is_admin))
    output$admin_user_msg <- renderUI(NULL)

    login    <- trimws(input$new_user_name)
    pwd      <- input$new_user_pwd
    fullname <- trimws(input$new_user_fullname)
    role     <- input$new_user_role

    # Validation
    if (nchar(login) < 3) {
      output$admin_user_msg <- renderUI(
        tags$div(class = "alert alert-danger", "L'identifiant doit contenir au moins 3 caractères."))
      return()
    }
    if (nchar(pwd) < 8) {
      output$admin_user_msg <- renderUI(
        tags$div(class = "alert alert-danger", "Le mot de passe doit contenir au moins 8 caractères."))
      return()
    }

    tryCatch({
      conn <- DBI::dbConnect(RSQLite::SQLite(), CREDS_DB)
      on.exit(DBI::dbDisconnect(conn), add = TRUE)

      users_raw <- shinymanager::read_db_decrypt(conn, "credentials", CREDS_PASSPHRASE)

      if (login %in% users_raw$user) {
        output$admin_user_msg <- renderUI(
          tags$div(class = "alert alert-warning",
                   paste0("L'identifiant '", login, "' existe déjà.")))
        return()
      }

      new_row <- data.frame(
        user              = login,
        password          = pwd,
        name              = if (nchar(fullname) > 0) fullname else login,
        start             = as.character(Sys.Date()),
        expire            = as.character(Sys.Date() + 730),
        admin             = role == "admin",
        permissions       = role,
        comment           = paste0("Créé par ", user_state$login, " le ", Sys.Date()),
        # ── Périmètres : concaténation par ";" ──────────────────────────────
        data_regions      = paste(input$new_user_regions      %||% character(0), collapse = ";"),
        data_departements = paste(input$new_user_departements %||% character(0), collapse = ";"),
        data_communes     = paste(input$new_user_communes     %||% character(0), collapse = ";"),
        stringsAsFactors  = FALSE
      )

      # S'assurer que les colonnes existent côté DB (gestion bases pré-migration)
      for (col in c("data_regions","data_departements","data_communes")) {
        if (!col %in% names(users_raw)) users_raw[[col]] <- ""
      }

      updated <- dplyr::bind_rows(users_raw, new_row)
      shinymanager::write_db_encrypt(conn, updated, "credentials", CREDS_PASSPHRASE)

      admin_users_rv(updated)

      updateTextInput(session,       "new_user_name",         value = "")
      updateTextInput(session,       "new_user_fullname",     value = "")
      updateTextInput(session,       "new_user_pwd",          value = "")
      updateSelectizeInput(session,  "new_user_regions",      selected = character(0))
      updateSelectizeInput(session,  "new_user_departements", selected = character(0))
      updateSelectizeInput(session,  "new_user_communes",     selected = character(0))

      # Résumé du périmètre dans le message de succès
      n_reg <- length(input$new_user_regions      %||% character(0))
      n_dep <- length(input$new_user_departements %||% character(0))
      n_com <- length(input$new_user_communes     %||% character(0))
      scope_msg <- if (n_reg + n_dep + n_com == 0) " — Accès à toutes les données"
                   else paste0(" — Périmètre : ",
                               if (n_com > 0) paste0(n_com, " commune(s)")
                               else if (n_dep > 0) paste0(n_dep, " département(s)")
                               else paste0(n_reg, " région(s)"))

      output$admin_user_msg <- renderUI(
        tags$div(class = "alert alert-success",
                 paste0("✅ Utilisateur '", login, "' créé avec le rôle '", role, "'.",
                        scope_msg)))

      log_activity(user_state$login, "create_user", paste0("Nouvel utilisateur: ", login, " (", role, ")"))

    }, error = function(e) {
      output$admin_user_msg <- renderUI(
        tags$div(class = "alert alert-danger", paste0("Erreur : ", conditionMessage(e))))
    })
  })

  # Journal d'activité
  output$admin_activity_log <- renderDT({
    req(isTRUE(user_state$is_admin))
    df <- if (file.exists(ACTIVITY_LOG)) readRDS(ACTIVITY_LOG) else data.frame()
    if (nrow(df) == 0) return(datatable(data.frame(Message = "Aucun événement enregistré.")))

    df %>%
      arrange(desc(timestamp)) %>%
      head(100) %>%
      mutate(timestamp = format(timestamp, "%d/%m/%Y %H:%M:%S")) %>%
      datatable(colnames = c("Horodatage","Utilisateur","Action","Détail"),
                options  = list(pageLength = 20, dom = "tip", scrollX = TRUE),
                rownames = FALSE)
  })

}  # fin server
