# ==============================================================================
# IGL Dashboard v2  |  MINDDEVEL / PADGOF-GIZ
# app.R — Point d'entrée principal de l'application Shiny
#
# Structure :
#   app.R       → Point d'entrée
#   global.R    → Configuration, bibliothèques, chargement des données
#   ui.R        → Interface utilisateur (avec secure_app shinymanager)
#   server.R    → Logique serveur
#   www/        → Ressources statiques (CSS, images)
#   data/       → Cache local des données + base d'identifiants
#
# Variables d'environnement (fichier .Renviron) :
#   KOBO_URL          = https://kf.kobotoolbox.org
#   KOBO_TOKEN        = <votre_token_API_KoboToolbox>
#   KOBO_ASSET_UID    = <identifiant_du_formulaire_IGL>
#   IGL_CREDS_PASSPHRASE = <phrase_secrete_base_identifiants>
#
# Comptes par défaut (à changer après 1ère connexion) :
#   admin       / Admin@IGL2025!   (Administrateur — accès complet)
#   evaluateur  / Eval@IGL2025!    (Évaluateur — vue + téléchargement)
#   visualiseur / View@IGL2025!    (Visualiseur — vue uniquement)
# ==============================================================================

source("global.R")
source("ui.R")
source("server.R")

shinyApp(ui = ui, server = server)
