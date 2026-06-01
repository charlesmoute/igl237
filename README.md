# Tableau de Bord IGL — Indice de Gouvernance Locale

> Application R Shiny de visualisation et d'analyse des évaluations communales dans le cadre du programme **PADGOF**, développée pour le **MINDDEVEL** en partenariat avec la **GIZ** — Cameroun.

**🌐 Démo en ligne : [charlesmoute.shinyapps.io/igl_dashboard](https://charlesmoute.shinyapps.io/igl_dashboard/)**

---

## Présentation

L'**Indice de Gouvernance Locale (IGL)** est un outil de mesure de la qualité de gouvernance des communes camerounaises. Il couvre 360 communes sur quatre domaines : gouvernance administrative, financière, participative et exercice des compétences transférées.

Ce tableau de bord permet aux équipes terrain, aux délégations régionales et aux responsables de programme de consulter, filtrer et exporter les résultats des évaluations — le tout depuis une interface sécurisée, sans compétences techniques particulières.

**Ce que vous pouvez faire avec l'application :**

- Visualiser les scores IGL à l'échelle nationale, régionale, départementale et communale sur une carte interactive
- Comparer les communes et identifier les domaines à renforcer en priorité
- Générer des rapports HTML individuels par commune, prêts à partager
- Synchroniser automatiquement les données depuis KoboToolbox au démarrage
- Gérer les accès utilisateurs avec des périmètres de données restreints par région, département ou commune

---

## Aperçu de l'application

```
┌─────────────────────────────────────────────────────────────────────┐
│  IGL Dashboard v2                      [sync: 18/05 14:32] [Admin ▾]│
├───────────────┬─────────────────────────────────────────────────────┤
│               │  Score IGL   │  Communes  │  Meilleure  │  À surveiller│
│  Navigation   │    0,62      │    360     │  Centre     │  Extrême-Nord│
│               ├─────────────────────────────────────────────────────┤
│  Vue Nationale│                                                      │
│  Analytique   │           [Carte interactive]                        │
│  Classement   │                                                      │
│  Export       │  [Répartition]          [Scores par région]          │
│  Admin        │                                                      │
│               │  [Tableau de synthèse régional]                      │
│  ─────────    │                                                      │
│  Filtres      │                                                      │
│  Région ▾     │                                                      │
│  Département ▾│                                                      │
│  Commune ▾    │                                                      │
└───────────────┴─────────────────────────────────────────────────────┘
```

---

## Fonctionnalités

### Tableaux de bord multi-niveaux

Cinq vues complémentaires pour analyser les données à n'importe quelle échelle :

| Vue | Ce qu'elle montre |
|-----|-------------------|
| **Nationale** | Carte interactive, KPIs nationaux, répartition de la performance par région |
| **Régionale** | Profil radar de la région, classement des départements |
| **Départementale** | Classement des communes, profil de gouvernance du département |
| **Commune** | Fiche complète avec scores, radar, recommandations par domaine |
| **Classement** | Tableau interactif trié et filtrable de toutes les communes |

### Onglet Analytique

- Distribution des scores (histogramme) avec repère de la moyenne
- Boîtes à moustaches pour comparer la dispersion entre régions
- Carte de chaleur Domaines × Régions pour repérer les points faibles systémiques
- Barres empilées par niveau de performance
- Top 10 / Bottom 10 dynamiques selon les filtres actifs

### Gestion des accès

Trois rôles distincts avec des droits progressifs :

| Fonctionnalité | Visualiseur | Évaluateur | Administrateur |
|---|:---:|:---:|:---:|
| Consultation des tableaux de bord | ✅ | ✅ | ✅ |
| Filtres géographiques | ✅ | ✅ | ✅ |
| Téléchargement CSV | ❌ | ✅ | ✅ |
| Génération de rapports HTML | ❌ | ✅ | ✅ |
| Synchronisation KoboToolbox | ❌ | ❌ | ✅ |
| Gestion des utilisateurs | ❌ | ❌ | ✅ |
| Journal d'activité | ❌ | ❌ | ✅ |

Chaque utilisateur peut avoir un **périmètre de données restreint** (régions, départements ou communes spécifiques) défini par l'administrateur à la création du compte.

### Intégration KoboToolbox

Les données sont chargées selon une logique en cascade au démarrage :

1. **KoboToolbox** — synchronisation directe via l'API (package `robotoolbox`)
2. **Cache local** — dernier jeu de données sauvegardé sur le disque
3. **Démonstration** — 360 communes fictives générées automatiquement

Un badge dans le header indique en permanence quelle source est active.

---

## Installation

### Prérequis

- **R** ≥ 4.2 — [cran.r-project.org](https://cran.r-project.org)
- **RStudio** ≥ 2023.06 (recommandé) — [posit.co](https://posit.co/download/rstudio-desktop)

### Étape 1 — Cloner le dépôt

```bash
git clone https://github.com/votre-organisation/igl-dashboard.git
cd igl-dashboard
```

### Étape 2 — Installer les dépendances R

```r
install.packages(c(
  "shiny", "shinydashboard", "shinyWidgets", "shinymanager",
  "plotly", "leaflet", "DT", "dplyr", "tidyr", "scales",
  "htmltools", "waiter", "DBI", "RSQLite"
))

# Optionnel : pour la connexion KoboToolbox
install.packages("robotoolbox")
```

### Étape 3 — Configurer l'environnement

Copiez `.Renviron.example` en `.Renviron` et renseignez vos identifiants :

```bash
cp .Renviron.example .Renviron
```

```ini
# Connexion KoboToolbox
KOBO_URL=https://kf.kobotoolbox.org
KOBO_TOKEN=votre_token_api
KOBO_ASSET_UID=identifiant_du_formulaire

# Passphrase de chiffrement de la base utilisateurs
IGL_CREDS_PASSPHRASE=une_phrase_longue_et_unique_2025
```

> **Comment trouver votre token KoboToolbox ?**
> Connectez-vous sur KoboToolbox → Profil → Paramètres du compte → API → copiez le token.

### Étape 4 — Lancer l'application

```r
# Depuis RStudio : ouvrir app.R et cliquer sur "Run App"
# Ou depuis la console :
shiny::runApp(".")
```

L'application crée automatiquement le dossier `data/` et initialise la base des utilisateurs au premier lancement.

---

## Structure du projet

```
igl-dashboard/
├── app.R               # Point d'entrée
├── global.R            # Config, chargement des données, utilitaires
├── ui.R                # Interface utilisateur
├── server.R            # Logique serveur
├── generate_data.R     # Générateur de données de démonstration
├── www/
│   ├── style.css       # Charte graphique
│   └── logo_igl.svg    # Logo
├── data/               # Créé automatiquement
│   ├── credentials.sqlite   # Base des utilisateurs (chiffrée)
│   ├── igl_data.RData        # Cache des données
│   └── activity_log.rds     # Journal d'activité
├── .Renviron.example   # Modèle de configuration
└── logs/               # Logs applicatifs
```

---

## Comptes par défaut

Trois comptes sont créés automatiquement au premier lancement.

| Identifiant | Mot de passe | Rôle |
|-------------|-------------|------|
| `admin` | `Admin@IGL2025!` | Administrateur |
| `evaluateur` | `Eval@IGL2025!` | Évaluateur |
| `visualiseur` | `View@IGL2025!` | Visualiseur |

> ⚠️ **Ces mots de passe sont publics.** Changez-les immédiatement après le premier lancement. L'interface d'administration complète est accessible en ajoutant `?admin` à l'URL de l'application.

---

## Périmètres de données par utilisateur

L'administrateur peut restreindre les données visibles pour chaque utilisateur. La logique suit une cascade : si des communes sont définies, elles priment sur tout ; sinon les départements priment sur les régions.

```
Communes définies  →  ces communes uniquement
       ↓ sinon
Départements définis  →  toutes leurs communes
       ↓ sinon
Régions définies  →  toutes leurs communes et départements
       ↓ sinon
Aucun filtre  →  toutes les données
```

Le périmètre est configuré dans l'onglet **Administration** lors de la création du compte, avec des sélecteurs en cascade qui se mettent à jour automatiquement.

---

## Déploiement en production

### Sur un serveur Shiny

```bash
# Déposer l'application dans le dossier des apps Shiny Server
cp -r igl-dashboard /srv/shiny-server/igl/

# Le fichier .Renviron doit être dans le dossier de l'app
cp .Renviron /srv/shiny-server/igl/.Renviron
```

Puis accéder à `http://votre-serveur/igl/`.

### Avec Posit Connect (recommandé pour la production)

Publier directement depuis RStudio via le bouton **Publish** ou avec `rsconnect` :

```r
rsconnect::deployApp(
  appDir   = ".",
  appName  = "igl-dashboard",
  account  = "votre-compte"
)
```

> Les variables d'environnement doivent être configurées dans l'interface de Posit Connect, pas dans le `.Renviron` local.

---

## Architecture technique

```
┌─────────────────────────────────────────────────┐
│                   global.R                      │
│  - Chargement données (KoboToolbox / cache /    │
│    démo) avec logique en cascade                │
│  - Initialisation base utilisateurs SQLite      │
│  - Migration automatique des DBs existantes     │
│  - apply_user_scope() pour les périmètres       │
└────────────────┬────────────────────────────────┘
                 │
        ┌────────┴─────────┐
        ▼                  ▼
   ┌─────────┐        ┌──────────┐
   │  ui.R   │        │ server.R │
   │         │        │          │
   │secure_  │        │secure_   │
   │app()    │        │server()  │
   │         │        │          │
   │sidebarM │        │observe() │
   │enuOutput│        │user_state│
   │         │        │reactiveV.│
   └─────────┘        └──────────┘
```

Les éléments clés de l'implémentation :

- **Authentification** via `shinymanager` avec base SQLite chiffrée
- **Gestion des rôles** via `reactiveValues` peuplé dans un `observe()` sur `res_auth$user_info` — la seule approche fiable pour lire les infos utilisateur sans bloquer le rendu
- **Menu conditionnel** via `sidebarMenuOutput` / `renderMenu` (méthode officielle shinydashboard — `hideTab`/`showTab` ne fonctionne pas sur les `menuItem`)
- **Périmètre de données** via `igl_data_scoped()`, un réactif qui applique `apply_user_scope()` à chaque render
- **Radar plots** : `mode = "lines+markers"` explicite pour éviter les warnings plotly
- **Couleurs plotly** : `unname()` systématique pour éviter le warning jsonlite sur les vecteurs nommés

---

## Données et indicateurs

L'IGL est calculé à partir de **26 indicateurs** répartis sur 4 domaines :

```
IGL = D1 × 0,35 + D2 × 0,25 + D3 × 0,25 + D4 × 0,15
```

| Domaine | Poids | Indicateurs couverts |
|---------|-------|---------------------|
| D1 — Gouvernance Administrative | 35% | Sessions du conseil, délégations du maire, ressources humaines, contentieux |
| D2 — Gouvernance Financière | 25% | Exécution budgétaire, recouvrement fiscal, investissements, dette |
| D3 — Gouvernance Participative | 25% | Comités de quartier, participation citoyenne, information, réclamations |
| D4 — Compétences Transférées | 15% | Écoles, centres de santé, eau potable, voiries, éclairage, environnement |

Chaque score est interprété selon l'échelle officielle du Guide Méthodologique IGL (MINDDEVEL, 2026) :

| Score | Niveau |
|-------|--------|
| > 0,85 | Très bonne gouvernance |
| 0,70 – 0,85 | Bonne gouvernance |
| 0,50 – 0,70 | Gouvernance moyenne |
| 0,25 – 0,50 | Gouvernance faible |
| < 0,25 | Gouvernance critique |

---

## Contribuer

Les contributions sont les bienvenues, notamment pour :

- La traduction de l'interface en anglais
- L'ajout de visualisations supplémentaires (évolution temporelle, comparaisons inter-cycles)
- L'intégration avec d'autres plateformes de collecte de données (ODK, CommCare)
- L'amélioration du générateur de rapports HTML

Pour contribuer : forkez le dépôt, créez une branche descriptive (`feature/evolution-temporelle`), puis ouvrez une Pull Request avec une description claire des changements.

---

## Licence

Ce projet est développé dans le cadre d'un programme de coopération technique public. Tout usage à des fins commerciales sans accord préalable du MINDDEVEL est interdit.

---

## Crédits

Développé pour le programme **PADGOF** (Programme d'Appui à la Décentralisation et à la Gouvernance des Finances publiques locales) dans le cadre de la coopération technique **MINDDEVEL / GIZ** au Cameroun.

---

*Pour toute question technique, ouvrez une issue. Pour les questions relatives à l'IGL et à son interprétation, contactez directement la Direction de la Décentralisation au MINDDEVEL.*
