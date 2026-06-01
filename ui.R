# ==============================================================================
# IGL Dashboard v2  |  MINDDEVEL / PADGOF-GIZ
# ui.R — Interface utilisateur complète avec authentification shinymanager
# ==============================================================================

# ── CONTENU DU TABLEAU DE BORD (enveloppé par secure_app ci-dessous) ─────────

dashboard_ui <- dashboardPage(
  skin = "green",

  # ── HEADER ──────────────────────────────────────────────────────────────────
  dashboardHeader(
    title = tags$span(
      tags$img(src = "logo_igl.svg", height = "28px",
               style = "vertical-align:middle; margin-right:8px;"),
      tags$b("IGL"), " Dashboard"
    ),
    titleWidth = 300,

    # Statut de synchronisation
    tags$li(class = "dropdown", id = "sync_badge_li",
      uiOutput("sync_badge")
    ),

    # Infos utilisateur connecté
    tags$li(class = "dropdown",
      uiOutput("user_info_header")
    ),

    # Date
    tags$li(class = "dropdown",
      tags$a(href = "#",
             style = "color:white; font-size:11px; padding:15px 12px;",
        tags$i(class = "fa fa-calendar", style = "margin-right:5px;"),
        format(Sys.Date(), "%d %B %Y")
      )
    )
  ),

  # ── SIDEBAR ─────────────────────────────────────────────────────────────────
  dashboardSidebar(
    width = 300,

    # Branding
    tags$div(style = "text-align:center; padding:15px 10px 8px;",
      tags$div(style = "font-size:15px; font-weight:700; color:#FCD116;",
               "MINDDEVEL / PADGOF-GIZ"),
      tags$div(style = "font-size:11px; color:#B0BEC5; margin-top:4px;",
               "Indice de Gouvernance Locale"),
      tags$div(style = "font-size:10px; color:#546E7A; margin-top:2px;",
               paste0("v", APP_VERSION))
    ),

    tags$hr(style = "border-color:rgba(255,255,255,0.08); margin:5px 15px;"),

    # Menu entier rendu côté serveur → permet d'ajouter l'onglet Admin dynamiquement
    # uiOutput("sidebar_menu_ui"), #MOUTE-todelete
    
    # Menu rendu côté serveur (sidebarMenuOutput + renderMenu = méthode officielle
    # shinydashboard pour les menus dynamiques, contrairement à uiOutput qui ne
    # gère pas correctement le routage des tabName)
    sidebarMenuOutput("sidebar_menu"),

    tags$hr(style = "border-color:rgba(255,255,255,0.08); margin:5px 15px;"),

    # Filtres en cascade
    tags$div(style = "padding:0 15px 15px;",
      tags$div(style = "color:#FCD116; font-weight:700; margin-bottom:10px; font-size:12px;",
        tags$i(class = "fa fa-filter", style = "margin-right:5px;"), "FILTRES"
      ),
      selectInput("filtre_region", "Région",
                  choices = c("Toutes les régions" = "", liste_regions), selected = ""),
      selectInput("filtre_departement", "Département",
                  choices = c("Tous les départements" = ""), selected = ""),
      selectInput("filtre_commune", "Commune",
                  choices = c("Toutes les communes" = ""), selected = ""),
      actionButton("btn_reinitialiser", "Réinitialiser", icon = icon("undo"),
                   style = "width:100%; background:transparent; border:1px solid #FCD116;
                            color:#FCD116; border-radius:6px; font-size:12px; margin-top:4px;")
    )
  ),

  # ── BODY ────────────────────────────────────────────────────────────────────
  dashboardBody(

    tags$head(
      tags$link(rel = "stylesheet", type = "text/css", href = "style.css"),
      tags$link(rel = "stylesheet",
        href = "https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css")
    ),
    useWaiter(),

    tabItems(

      # ================================================================
      # ONGLET 1 : VUE NATIONALE
      # ================================================================
      tabItem(tabName = "national",
        tags$div(class = "info-bar",
          tags$i(class = "fa fa-globe", style = "margin-right:8px; font-size:18px;"),
          tags$b("Vue d'ensemble nationale"), " - Indice de Gouvernance Locale"
        ),
        fluidRow(
          column(3, uiOutput("kpi_igl_national")),
          column(3, uiOutput("kpi_nb_communes")),
          column(3, uiOutput("kpi_meilleure_region")),
          column(3, uiOutput("kpi_region_attention"))
        ),
        fluidRow(
          column(7,
            box(title = tagList(icon("map"), " Score IGL par Région"), width = 12,
                solidHeader = FALSE, status = "success",
                leafletOutput("carte_nationale", height = "480px"))
          ),
          column(5,
            box(title = tagList(icon("chart-pie"), " Répartition de la Performance"), width = 12,
                solidHeader = FALSE, status = "success",
                plotlyOutput("pie_perf_nationale", height = "220px")),
            box(title = tagList(icon("chart-bar"), " Score Moyen par Région"), width = 12,
                solidHeader = FALSE, status = "success",
                plotlyOutput("bar_regions", height = "220px"))
          )
        ),
        fluidRow(
          column(12,
            box(title = tagList(icon("table"), " Synthèse par Région"), width = 12,
                solidHeader = FALSE, status = "success",
                DTOutput("table_regions"),
                tags$br(),
                uiOutput("interpretation_nationale"))
          )
        )
      ),

      # ================================================================
      # ONGLET 2 : ANALYSE RÉGIONALE
      # ================================================================
      tabItem(tabName = "regional",
        tags$div(class = "info-bar",
          tags$i(class = "fa fa-map", style = "margin-right:8px; font-size:18px;"),
          tags$b("Analyse Régionale"), " - Détail par département"
        ),
        fluidRow(
          column(3, uiOutput("kpi_region_score")),
          column(3, uiOutput("kpi_region_nb_dept")),
          column(3, uiOutput("kpi_region_meilleur_dept")),
          column(3, uiOutput("kpi_region_faible_dept"))
        ),
        fluidRow(
          column(6,
            box(title = tagList(icon("chart-bar"), " Score IGL par Département"), width = 12,
                solidHeader = FALSE, status = "success",
                plotlyOutput("bar_dept_region", height = "400px"))
          ),
          column(6,
            box(title = tagList(icon("sitemap"), " Profil de Gouvernance Régional"), width = 12,
                solidHeader = FALSE, status = "success",
                plotlyOutput("radar_region", height = "400px"))
          )
        ),
        fluidRow(
          column(12,
            box(title = tagList(icon("table"), " Détail des Départements"), width = 12,
                solidHeader = FALSE, status = "success",
                DTOutput("table_dept_region"),
                tags$br(),
                uiOutput("interpretation_regionale"))
          )
        )
      ),

      # ================================================================
      # ONGLET 3 : ANALYSE DÉPARTEMENTALE
      # ================================================================
      tabItem(tabName = "departemental",
        tags$div(class = "info-bar",
          tags$i(class = "fa fa-map-marker-alt", style = "margin-right:8px; font-size:18px;"),
          tags$b("Analyse Départementale"), " - Détail par commune"
        ),
        fluidRow(
          column(3, uiOutput("kpi_dept_score")),
          column(3, uiOutput("kpi_dept_nb_com")),
          column(3, uiOutput("kpi_dept_meilleure_com")),
          column(3, uiOutput("kpi_dept_faible_com"))
        ),
        fluidRow(
          column(6,
            box(title = tagList(icon("chart-bar"), " Score IGL par Commune"), width = 12,
                solidHeader = FALSE, status = "success",
                plotlyOutput("bar_com_dept", height = "400px"))
          ),
          column(6,
            box(title = tagList(icon("sitemap"), " Profil de Gouvernance Départemental"), width = 12,
                solidHeader = FALSE, status = "success",
                plotlyOutput("radar_dept", height = "400px"))
          )
        ),
        fluidRow(
          column(12,
            box(title = tagList(icon("table"), " Classement des Communes du Département"), width = 12,
                solidHeader = FALSE, status = "success",
                DTOutput("table_com_dept"),
                tags$br(),
                uiOutput("interpretation_departementale"))
          )
        )
      ),

      # ================================================================
      # ONGLET 4 : DÉTAIL COMMUNE
      # ================================================================
      tabItem(tabName = "communal",
        tags$div(class = "info-bar",
          tags$i(class = "fa fa-city", style = "margin-right:8px; font-size:18px;"),
          tags$b("Fiche d'évaluation communale"), " - Détail complet"
        ),
        fluidRow(
          column(3, uiOutput("kpi_com_igl")),
          column(3, uiOutput("kpi_com_d1")),
          column(3, uiOutput("kpi_com_d2")),
          column(3, uiOutput("kpi_com_d3"))
        ),
        fluidRow(
          column(6,
            box(title = tagList(icon("sitemap"), " Profil de Gouvernance (Spider)"), width = 12,
                solidHeader = FALSE, status = "success",
                plotlyOutput("radar_commune", height = "360px"))
          ),
          column(6,
            box(title = tagList(icon("chart-bar"), " Scores par Domaine"), width = 12,
                solidHeader = FALSE, status = "success",
                plotlyOutput("bar_domaines_commune", height = "360px"))
          )
        ),
        fluidRow(
          column(12,
            box(title = tagList(icon("clipboard"), " Interprétation et Recommandations"), width = 12,
                solidHeader = FALSE, status = "success",
                uiOutput("fiche_commune_complete"))
          )
        )
      ),

      # ================================================================
      # ONGLET 5 : CLASSEMENT
      # ================================================================
      tabItem(tabName = "classement",
        tags$div(class = "info-bar",
          tags$i(class = "fa fa-list-ol", style = "margin-right:8px; font-size:18px;"),
          tags$b("Classement des Communes"), " - Ordre décroissant du score IGL"
        ),
        fluidRow(
          column(12,
            box(title = tagList(icon("trophy"), " Classement Général"), width = 12,
                solidHeader = FALSE, status = "success",
                DTOutput("table_classement"))
          )
        )
      ),

      # ================================================================
      # ONGLET 6 : ANALYTIQUE (NOUVEAU)
      # ================================================================
      tabItem(tabName = "analytique",
        tags$div(class = "info-bar",
          tags$i(class = "fa fa-chart-line", style = "margin-right:8px; font-size:18px;"),
          tags$b("Tableau de Bord Analytique"), " - Statistiques et distribution"
        ),

        # Statistiques descriptives
        fluidRow(
          column(3, uiOutput("kpi_score_moyen")),
          column(3, uiOutput("kpi_score_median")),
          column(3, uiOutput("kpi_score_max")),
          column(3, uiOutput("kpi_score_min"))
        ),

        fluidRow(
          column(6,
            box(title = tagList(icon("chart-bar"), " Distribution des Scores IGL"), width = 12,
                solidHeader = FALSE, status = "success",
                plotlyOutput("histo_igl", height = "300px"))
          ),
          column(6,
            box(title = tagList(icon("cube"), " Comparaison Régionale (Boîtes à moustaches)"), width = 12,
                solidHeader = FALSE, status = "success",
                plotlyOutput("boxplot_regions", height = "300px"))
          )
        ),

        fluidRow(
          column(6,
            box(title = tagList(icon("th"), " Carte de Chaleur Domaines × Régions"), width = 12,
                solidHeader = FALSE, status = "success",
                plotlyOutput("heatmap_domaines", height = "340px"))
          ),
          column(6,
            box(title = tagList(icon("chart-bar"), " Répartition par Niveau de Performance"), width = 12,
                solidHeader = FALSE, status = "success",
                plotlyOutput("bar_perf_stacked", height = "340px"))
          )
        ),

        fluidRow(
          column(6,
            box(title = tagList(icon("arrow-up"), " Top 10 - Meilleures Communes"), width = 12,
                solidHeader = FALSE, status = "success",
                DTOutput("table_top10"))
          ),
          column(6,
            box(title = tagList(icon("arrow-down"), " Bottom 10 - Communes à Surveiller"), width = 12,
                solidHeader = FALSE, status = "success",
                DTOutput("table_bottom10"))
          )
        )
      ),

      # ================================================================
      # ONGLET 7 : EXPORT
      # ================================================================
      tabItem(tabName = "export",
        tags$div(class = "info-bar",
          tags$i(class = "fa fa-file-download", style = "margin-right:8px; font-size:18px;"),
          tags$b("Export des Résultats"), " - Rapports et données"
        ),
        uiOutput("export_permission_notice"),
        fluidRow(
          column(6,
            box(title = tagList(icon("file-alt"), " Rapport Communal HTML"), width = 12,
                solidHeader = FALSE, status = "success",
                tags$p("Sélectionnez une commune pour générer un rapport HTML complet."),
                selectInput("export_commune_select", "Commune :",
                            choices = sort(unique(igl_data$subdivision_name))),
                uiOutput("btn_dl_rapport"))
          ),
          column(6,
            box(title = tagList(icon("table"), " Export des Données CSV"), width = 12,
                solidHeader = FALSE, status = "success",
                tags$p("Exportez les données (filtrées ou complètes) au format CSV."),
                uiOutput("btn_dl_csv"),
                tags$br(),
                uiOutput("btn_dl_classement"))
          )
        )
      ),

      # ================================================================
      # ONGLET 8 : ADMINISTRATION (Visible admins seulement)
      # ================================================================
      tabItem(tabName = "admin",
        tags$div(class = "info-bar admin-bar",
          tags$i(class = "fa fa-cog", style = "margin-right:8px; font-size:18px;"),
          tags$b("Administration"), " - Synchronisation et gestion des utilisateurs"
        ),

        # Diagnostic de session (debug)
        fluidRow(column(12, uiOutput("admin_session_debug"))),

        # Statut des données
        fluidRow(
          column(12,
            box(title = tagList(icon("database"), " Statut des Données"), width = 12,
                solidHeader = FALSE, status = "danger",
                fluidRow(
                  column(8, uiOutput("admin_sync_status")),
                  column(4,
                    tags$div(style = "padding-top:10px;",
                      tags$p(tags$b("Source KoboToolbox :")),
                      tags$p(style = "font-size:12px; color:#666;",
                        "Configurez les variables d'environnement dans le fichier",
                        tags$code(".Renviron"), ":"
                      ),
                      tags$pre(style = "font-size:11px; background:#F5F5F5; padding:10px; border-radius:6px;",
"KOBO_URL=https://kf.kobotoolbox.org
KOBO_TOKEN=votre_token_api
KOBO_ASSET_UID=identifiant_du_formulaire
IGL_CREDS_PASSPHRASE=phrase_securisee"),
                      if (HAS_ROBOTOOLBOX) {
                        actionButton("btn_sync_kobo", tagList(icon("redo"), " Synchroniser depuis KoboToolbox"),
                                     class = "btn-warning btn-block",
                                     style = "font-weight:600; margin-top:10px;")
                      } else {
                        tags$div(class = "alert alert-warning", style = "font-size:12px;",
                          tags$b("Package robotoolbox non installé."),
                          tags$br(),
                          tags$code('install.packages("robotoolbox")')
                        )
                      }
                    )
                  )
                )
            )
          )
        ),

        # Gestion des utilisateurs
        fluidRow(
          column(12,
            box(title = tagList(icon("users"), " Gestion des Utilisateurs"), width = 12,
                solidHeader = FALSE, status = "warning",
                fluidRow(
                  column(12,
                    tags$div(class = "alert alert-info", style = "font-size:12px;",
                      tags$i(class = "fa fa-info-circle"),
                      " La gestion complète des utilisateurs est disponible via l'interface admin shinymanager.",
                      tags$br(),
                      "Accédez à : ",
                      tags$code(paste0(getOption("shiny.host", "localhost"), ":",
                                       getOption("shiny.port", 3838), "?admin"))
                    )
                  )
                ),
                tags$br(),
                DTOutput("admin_users_table"),
                tags$br(),

                # Formulaire d'ajout rapide
                tags$h5(tags$b("Ajouter un utilisateur")),
                fluidRow(
                  column(3, textInput("new_user_name", "Identifiant", placeholder = "ex: jean.dupont")),
                  column(3, passwordInput("new_user_pwd", "Mot de passe")),
                  column(3, textInput("new_user_fullname", "Nom complet")),
                  column(3, selectInput("new_user_role", "Rôle",
                                        choices = c("Visualiseur" = "visualiseur",
                                                    "Évaluateur"  = "evaluateur",
                                                    "Admin"       = "admin")))
                ),

                # ── Périmètre des données accessibles ───────────────────────
                tags$div(style = "background:#F8F9FA; border-left:4px solid #1D3557; padding:12px 15px; border-radius:6px; margin:10px 0;",
                  tags$h6(style = "margin-top:0; color:#1D3557;",
                          tags$i(class = "fa fa-filter"), tags$b(" Périmètre des données accessibles")),
                  tags$p(style = "font-size:11px; color:#666; margin-bottom:10px;",
                    "Définissez les régions, départements ou communes auxquels cet utilisateur aura accès. ",
                    tags$b("Cascade :"),
                    " si vous précisez des communes, seules celles-ci seront accessibles. ",
                    "Si vous précisez uniquement des régions, toutes leurs communes seront accessibles. ",
                    tags$b("Tout laisser vide = accès à toutes les données."),
                    " Si vous ne précisez aucun filtre l'utilisateur aura accès à toutes les données du tableau de bord."
                  ),
                  fluidRow(
                    column(4,
                      selectizeInput("new_user_regions", "Régions",
                                     choices  = liste_regions,
                                     multiple = TRUE,
                                     options  = list(placeholder = "(Toutes les régions)",
                                                     plugins = list("remove_button")))
                    ),
                    column(4,
                      selectizeInput("new_user_departements", "Départements",
                                     choices  = NULL,
                                     multiple = TRUE,
                                     options  = list(placeholder = "(Tous les départements)",
                                                     plugins = list("remove_button")))
                    ),
                    column(4,
                      selectizeInput("new_user_communes", "Communes",
                                     choices  = NULL,
                                     multiple = TRUE,
                                     options  = list(placeholder = "(Toutes les communes)",
                                                     plugins = list("remove_button")))
                    )
                  )
                ),

                actionButton("btn_add_user", tagList(icon("user-plus"), " Ajouter l'utilisateur"),
                             class = "btn-success"),
                uiOutput("admin_user_msg")
            )
          )
        ),

        # Journal d'activité
        fluidRow(
          column(12,
            box(title = tagList(icon("history"), " Journal d'Activité (100 derniers événements)"), width = 12,
                solidHeader = FALSE, status = "success",
                DTOutput("admin_activity_log"))
          )
        )
      )  # fin tabItem admin

    ),  # fin tabItems

    # Footer
    tags$footer(
      style = paste0("text-align:center; padding:12px; background:#1A2332;",
                     " color:#B0BEC5; font-size:11px; border-top:3px solid ", IGL_VERT, ";",
                     " margin-top:20px;"),
      HTML(paste0("&copy; ", APP_YEAR, " ", APP_ORG,
                  " — Indice de Gouvernance Locale v", APP_VERSION,
                  " | Tous droits réservés"))
    )
  )  # fin dashboardBody
)  # fin dashboardPage

# ── ENVELOPPEMENT AVEC SHINYMANAGER ───────────────────────────────────────────

ui <- secure_app(
  dashboard_ui,
  enable_admin = TRUE,
  language     = "fr",
  # Personnalisation de la page de connexion
  tags_top = tags$div(
    style = "text-align:center; padding:20px 0 10px;",
    tags$div(
      style = paste0("display:inline-block; background:linear-gradient(135deg,",
                     IGL_VERT, ",", IGL_VERT_CLAIR, "); padding:15px 25px;",
                     " border-radius:12px; color:white; margin-bottom:20px;",
                     " box-shadow:0 4px 20px rgba(0,0,0,0.3);"),
      tags$div(style = "font-size:28px; font-weight:800; letter-spacing:2px;", "IGL"),
      tags$div(style = "font-size:12px; opacity:0.9;", "Dashboard"),
    ),
    tags$h3(style = "color:#1A2332; font-weight:700; margin:10px 0 5px;",
            "Tableau de Bord IGL"),
    tags$p(style = "color:#546E7A; font-size:13px; margin:0;", APP_ORG),
    tags$p(style = "color:#90A4AE; font-size:12px;",
           "Indice de Gouvernance Locale — Cameroun"),
    tags$hr(style = "border-color:#E0E0E0; margin:15px 0;")
  ),
  tags_bottom = tags$div(
    style = "text-align:center; padding-top:15px;",
    tags$p(
      style = "color:#90A4AE; font-size:11px;",
      HTML(paste0("&copy; ", APP_YEAR, " MINDDEVEL / PADGOF-GIZ &mdash; v", APP_VERSION,
                  "<br>Accès réservé aux personnes autorisées"))
    )
  )
)
