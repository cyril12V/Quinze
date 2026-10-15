# Rapport de tests — V1

Livrable n° 14 du cahier des charges (§26). Il recense ce qui a été réellement exécuté pendant le développement, les résultats obtenus, et ce qui reste à exécuter sur un Mac (en CI) ou sur un iPhone.

Environnement d'exécution : Linux (Ubuntu 24.04), Swift 6.0.3, PostgreSQL 16, Node 22, Deno (via npm).

## 1. Résultats

| Domaine | Commande | Résultat |
|---|---|---|
| Corpus anglais : structure, références, répartition des exercices | `python3 tools/build_content.py --lang en` | 0 erreur, 1 avertissement (même consigne générique « Quelle phrase est correcte ? » dans deux exercices aux options différentes) |
| Moteur pédagogique (`Packages/LearningCore`) | `swift test` | **78 tests, 0 échec** |
| Cohérence corpus ↔ moteur (inclus ci-dessus) | `RealContentTests` | 2 273 réponses modèles et acceptées sur 680 exercices : toutes acceptées. 784 pièges `equals` : aucun accepté. Toutes les références résolues |
| Simulation 30 jours, 3 sessions par jour, plusieurs profils d'apprenants (incluse ci-dessus) | `SimulationTests` | Progression régulière dans les leçons, révisions effectuées, aucune notion ne bloque durablement, sessions de 8 à 12 exercices |
| App iOS : partie indépendante d'Apple (état partagé avec les extensions, moteur des créneaux de restriction, statut des créneaux, DTO de synchronisation, modèles IA, réponses de secours du professeur) | `python3 tools/linux_app_check.py` | **72 tests, 0 échec** |
| App iOS : syntaxe des 65 fichiers Swift (app, extensions, tests), après la refonte visuelle | `tools/check_swift_syntax.sh` | 0 erreur |
| Base de données : migrations, RLS, synchronisation, contenu réel, suppression de compte, stockage | `supabase/tests/run_sql_tests.sh` | **180 assertions, 0 échec** |
| Edge Functions : logique (prompts, cache, quotas, validation, parsing, export) | `npx deno test --allow-read --allow-env supabase/functions/_tests/` | **46 tests, 0 échec** (dont 41 également exécutables avec `node --test`) |
| Edge Functions : vérification de types | `npx deno check ai/index.ts account/index.ts` | 0 erreur |

## 2. Couverture des tests exigés (§22)

### 22.1 Tests pédagogiques — couverts par `LearningCore`

| Exigence | Où |
|---|---|
| Progression des difficultés | `PlannerTests`, `SimulationTests` |
| Respect des prérequis (et déblocage après N jours) | `PlannerTests` |
| Réintroduction des notions anciennes | `PlannerTests`, `SimulationTests` |
| Correction des réponses, acceptation des variantes | `EvaluatorTests`, `NormalizerTests`, `RealContentTests` |
| Détection et catégorisation des erreurs | `EvaluatorTests` |
| Mise à jour des états de mémorisation (FSRS) | `SchedulingTests` (valeurs de référence calculées indépendamment) |
| Génération de sessions pertinentes | `PlannerTests`, `SessionRunnerTests` |
| Diagnostic adaptatif et placement | `DiagnosticDictionaryTests` |

### 22.2 Tests fonctionnels

Les règles métier sous-jacentes sont testées. C'est le cas du statut des créneaux, de la reprise de session, des formats de synchronisation et du placement. Les parcours complets à l'écran ne le sont pas encore. Ils se testent dans l'app : inscription, connexion, déconnexion, récupération du compte, diagnostic, leçon complète, interruption et reprise, synchronisation entre deux iPhone, réglages, suppression du compte.

Ils sont à dérouler sur TestFlight. La liste de contrôle est l'ordre des étapes de l'onboarding et les critères d'acceptation du §23.

### 22.3 Tests Screen Time

La logique est testée sous Linux (`SlotEngineTests`, `SharedStateTests`) :
- indépendance des créneaux ;
- prévalidation ;
- expiration de sécurité ;
- déblocage d'urgence ;
- changements d'horaire ;
- réconciliation.

Le comportement réel d'iOS ne peut être vérifié que sur un iPhone : autorisation, moniteur en arrière-plan, écran de blocage, redémarrage, révocation. Le protocole pas à pas est dans [../tests/screen-time-test-plan.md](../tests/screen-time-test-plan.md). C'est la phase 0 bloquante du cahier des charges.

### 22.4 Tests de sécurité — couverts par les tests SQL et Edge Functions

| Exigence | Où |
|---|---|
| Accès non autorisé aux données (RLS entre deux utilisateurs) | `supabase/tests/sql/10_rls_isolation.sql` |
| Manipulation des identifiants | `10_rls_isolation.sql`, `20_sync.sql` |
| Tentatives de validation frauduleuse des leçons | `20_sync.sql` : `validated = false` |
| Requêtes répétées, synchronisation idempotente | `20_sync.sql` |
| Appels IA abusifs (quotas, tailles maximales, JWT) | `_tests/logic.test.ts`, `_tests/validation_http.test.ts` |
| Suppression et restauration de données | `30_content_cascade.sql` ; restauration complète via `sync_pull` dans `20_sync.sql` |
| Sessions expirées | Gérées par Supabase Auth (jetons à durée limitée), à vérifier en recette |

## 3. Corrections issues des vérifications

- **`Shared/SlotEngine.swift`.** Treize appels `clear(slot)` ne correspondaient pas au protocole `clear(slot:)`. L'erreur aurait bloqué la compilation de l'app et des extensions ; elle a été détectée par la compilation Linux.
- **Relecture « compilateur » du code iOS** (concurrence stricte Swift 6, SDK Supabase 2.55.4 vérifié dans son code source) :
  - six corrections dans les services (synchronisation, contenu, authentification, persistance, notifications) ;
  - trois corrections dans les écrans : conflit de nom `PresentationMode` avec SwiftUI, appels d'une mise en page personnalisée, initialiseurs devenus privés.
- **Ergonomie et accessibilité** :
  - l'écran de connexion s'ouvre en mode connexion pour un utilisateur existant ;
  - la touche Entrée envoie la question au professeur ;
  - le message « notifications désactivées » s'affiche bien ;
  - « Apprendre ce mot » est masqué pour les mots non suivis ;
  - les mots touchables mesurent au moins 44 pt.
- **CI.** Les simulateurs sont choisis selon la version d'Xcode. L'archive TestFlight est faite avec Xcode 26, car l'App Store exige le SDK iOS 26. La compilation est vérifiée avec Xcode 26 et Xcode 16.

## 4. Reste à exécuter

1. **Première compilation iOS réelle.** Pousser le dépôt sur GitHub : `ios.yml` compile l'app et les trois extensions avec Xcode 26 et Xcode 16, puis lance `QuinzeTests` sur simulateur. La syntaxe et une large partie des types ont été vérifiées ici, mais une compilation Apple peut encore signaler des points mineurs. La liste des doutes connus est dans [../11-limites-connues.md](../11-limites-connues.md).
2. **Protocole Screen Time sur iPhone** (phase 0) : [../tests/screen-time-test-plan.md](../tests/screen-time-test-plan.md).
3. **Recette fonctionnelle sur TestFlight** (§22.2), avec un vrai projet Supabase et une vraie clé Anthropic.
4. **Relecture linguistique humaine du corpus**, exigée par le §7.3 avant publication. Le corpus a été rédigé puis relu module par module, et validé automatiquement : structure, réponses acceptées, pièges. Un relecteur anglophone reste nécessaire.
5. **Réglage des paramètres** du moteur avec des données réelles (§12.3) : seuils de maîtrise et poids FSRS.
