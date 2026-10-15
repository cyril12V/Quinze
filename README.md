# Quinze — apprendre l'anglais 15 minutes par jour

Application iPhone d'apprentissage des langues : trois sessions de cinq minutes par jour, un moteur pédagogique à répétition espacée, un professeur IA et, à chaque horaire de leçon, la restriction des applications distrayantes jusqu'à ce que la leçon soit faite.

> **Design** : direction artistique « éditoriale pastel » (Plus Jakarta Sans, cards pastel, boutons noirs en pilule), décrite dans [docs/design/direction-artistique.md](docs/design/direction-artistique.md). Les photos de personnes détourées sont à déposer dans `App/Resources/Assets.xcassets` sous les noms listés dans ce document ; d'ici là, un visuel abstrait les remplace.
>
> « Quinze » est un nom de travail. Pour le changer, modifie `CFBundleDisplayName` dans `project.yml` et les textes qui le mentionnent.

## Ce que contient le dépôt

| Dossier | Contenu | État |
|---|---|---|
| `Packages/LearningCore/` | Moteur pédagogique en Swift pur : correction, FSRS, maîtrise, planification des sessions, diagnostic, dictionnaire | Compilé et testé : 78 tests sous Linux, Swift 6.0.3 |
| `Content/` | Programme et corpus anglais : 60 leçons, 600 exercices, 397 fiches, diagnostic, évaluations, plus les outils de validation | Validé par script et par le moteur |
| `App/` | App iOS SwiftUI : onboarding, comptes, leçons, correction, professeur IA, dictionnaire, progrès, réglages, synchronisation | Syntaxe vérifiée ; **première compilation iOS à faire en CI** |
| `Shared/`, `Extensions/` | Restrictions Screen Time : état partagé, moniteur DeviceActivity, écran de blocage, actions du bouclier | Idem ; **à valider sur iPhone** |
| `supabase/` | Base de données (7 migrations, RLS), RPC de synchronisation, Edge Functions `ai` (Claude) et `account` | 180 assertions SQL et 46 tests TypeScript passent |
| `.github/workflows/` | CI du moteur, build et tests iOS sur macOS, envoi TestFlight | Prête, s'exécute sur GitHub |
| `docs/` | Documentation technique et rapports | — |

## Usage perso : installer sur ton iPhone

Le chemin le plus court, sans App Store ni validation d'Apple, blocage des apps compris : [docs/12-installer-sur-mon-iphone.md](docs/12-installer-sur-mon-iphone.md). Il faut un compte Apple Developer, GitHub et Diawi. Sans serveur Supabase, l'app tourne en **mode local** : pas de compte, tout reste sur l'iPhone.

## Démarrage complet (distribution, sans Mac)

Tout se construit dans GitHub Actions, sur des machines macOS fournies par GitHub. Le guide pas à pas est dans [docs/07-ci-testflight-sans-mac.md](docs/07-ci-testflight-sans-mac.md). En résumé :

1. **Pousse ce dépôt sur GitHub.** Le workflow `ios.yml` compile l'app et lance les tests à chaque push. C'est la première vérification de compilation iOS réelle : corrige ce qu'il signale avant d'aller plus loin.
2. **Crée le backend Supabase.** Suis [docs/06-deploiement-backend.md](docs/06-deploiement-backend.md) : migrations, secrets (`ANTHROPIC_API_KEY`), fonctions, envoi du corpus.
3. **Inscris-toi au programme Apple Developer** (99 $/an).
   - Crée les identifiants : app, 3 extensions et App Group.
   - **Demande tout de suite l'autorisation « Family Controls (Distribution) » pour les 4 identifiants.** C'est le délai le plus long et le plus incertain du projet.
4. **Renseigne les secrets GitHub** : clé API App Store Connect, équipe, URL et clé Supabase. Lance ensuite `testflight.yml`, puis installe l'app sur ton iPhone via TestFlight.
5. **Déroule le protocole de test Screen Time** sur l'iPhone : [docs/tests/screen-time-test-plan.md](docs/tests/screen-time-test-plan.md). Ton cahier des charges l'impose comme étape bloquante (phase 0).

## Commandes utiles

```bash
# Contenu : valider un module, puis tout reconstruire (bundle app + seed SQL)
python3 tools/build_content.py --lang en --module m03
python3 tools/build_content.py --lang en

# Moteur pédagogique (macOS ou Linux avec Swift 6)
cd Packages/LearningCore && swift test

# App iOS sans Mac : syntaxe de tous les fichiers, puis compilation + tests de la partie Foundation
tools/check_swift_syntax.sh
python3 tools/linux_app_check.py

# Backend : tests SQL sur un Postgres jetable, et tests TypeScript
supabase/tests/run_sql_tests.sh
node --test supabase/functions/_tests/

# App iOS (sur un Mac, ou laisser faire la CI)
brew install xcodegen && cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
xcodegen generate && open Quinze.xcodeproj
```

## Documentation

| Document | Sujet |
|---|---|
| [01-architecture](docs/01-architecture.md) | Vue d'ensemble, modules, flux de données, choix techniques |
| [02-faisabilite-apple](docs/02-faisabilite-apple.md) | Rapport de faisabilité Screen Time (phase 0), entitlements, protocole de prototype, risques |
| [03-base-de-donnees](docs/03-base-de-donnees.md) | Schéma, RLS, contraintes, synchronisation, conservation |
| [04-api](docs/04-api.md) | RPC, PostgREST et Edge Functions |
| [05-moteur-pedagogique](docs/05-moteur-pedagogique.md) | Correction, FSRS, maîtrise, sessions, diagnostic, calcul des pourcentages |
| [06-deploiement-backend](docs/06-deploiement-backend.md) | Mise en production Supabase |
| [07-ci-testflight-sans-mac](docs/07-ci-testflight-sans-mac.md) | Compiler, signer et distribuer sans Mac |
| [08-contenus](docs/08-contenus.md) | Organisation, modification et publication du corpus |
| [09-ajouter-une-langue](docs/09-ajouter-une-langue.md) | Ajouter l'arabe (ou une autre langue) |
| [10-dependances-et-couts](docs/10-dependances-et-couts.md) | Services externes, dépendances, coûts récurrents |
| [11-limites-connues](docs/11-limites-connues.md) | Ce qui n'est pas garanti, ce qui reste à faire |
| [12-installer-sur-mon-iphone](docs/12-installer-sur-mon-iphone.md) | Usage perso : compiler et installer sur ton iPhone, sans Mac |
| [design/direction-artistique](docs/design/direction-artistique.md) | Direction artistique : jetons, composants, règles par écran, photos à fournir |
| [reports/rapport-de-tests](docs/reports/rapport-de-tests.md) | Tests exécutés, résultats, tests restant à faire sur iPhone |
| [tests/screen-time-test-plan](docs/tests/screen-time-test-plan.md) | Plan de test Screen Time sur appareil |
| [politique-confidentialite](docs/politique-confidentialite.md) | Politique de confidentialité (à compléter : éditeur, contact) |
| `contracts/` | Contrats internes entre modules (format du contenu, API du moteur, contrat backend) |
