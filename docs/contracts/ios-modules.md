# Organisation du code iOS

Projet généré par **XcodeGen** (`project.yml`) : aucun `.xcodeproj` n'est versionné.

## Cibles

| Cible | Type | Bundle ID | Sources |
|---|---|---|---|
| `Quinze` | app iOS | `$(BUNDLE_ID_PREFIX).quinze` | `App/Sources`, `Shared/` |
| `QuinzeMonitor` | extension DeviceActivityMonitor | `$(BUNDLE_ID_PREFIX).quinze.monitor` | `Extensions/DeviceActivityMonitor`, `Shared/` |
| `QuinzeShieldConfiguration` | extension ShieldConfiguration | `$(BUNDLE_ID_PREFIX).quinze.shieldconfig` | `Extensions/ShieldConfiguration`, `Shared/` |
| `QuinzeShieldAction` | extension ShieldAction | `$(BUNDLE_ID_PREFIX).quinze.shieldaction` | `Extensions/ShieldAction`, `Shared/` |
| `QuinzeTests` | tests unitaires de l'app | — | `App/Tests` |

- App Group : `group.$(BUNDLE_ID_PREFIX).quinze` (constante `AppGroup.identifier` dans `Shared/`).
- Entitlements Family Controls sur l'app **et** les trois extensions.
- Cible iOS minimale : **17.0** (SwiftData). Swift 6, mode de langage Swift 6, concurrence stricte.
- Paquets SPM : `Packages/LearningCore` (local ; produits `LearningCore` pour l'app, `LearningPrimitives` pour les extensions) et `supabase-swift` (≥ 2.5.0, produit `Supabase`, app uniquement).
- Configuration (URL Supabase, clé anon, schéma d'URL) : `Config/*.xcconfig` → clés `Info.plist` `SUPABASE_URL`, `SUPABASE_ANON_KEY`. Aucune clé de fournisseur IA dans l'app.

## Répartition des dossiers

| Dossier | Contenu | Responsable |
|---|---|---|
| `App/Sources/App/` | `QuinzeApp` (@main), `RootView` (routage chargement → auth → onboarding → accueil) | B1 |
| `App/Sources/Core/` | `AppEnvironment`, `LearningStore`, `LessonController`, `TutorService`, `SpeechService` (fichiers contrat) | B1 |
| `App/Sources/Services/` | Supabase, auth, persistance SwiftData, synchronisation, contenu, file IA, réglages | B1 |
| `App/Sources/Features/Onboarding/` | bienvenue, compte, langue, niveau, diagnostic, horaires, apps à restreindre, première leçon | B1 |
| `App/Sources/Features/Auth/` | connexion, inscription, Apple, mot de passe oublié | B1 |
| `App/Sources/Features/Settings/` | horaires, notifications, restrictions, compte, confidentialité, suppression | B1 |
| `App/Sources/Features/Home/` | accueil | B2 |
| `App/Sources/Features/Lesson/` | déroulé de session, 6 vues d'exercice, cartes règle/mot, correction, fin de session | B2 |
| `App/Sources/Features/Tutor/` | feuille « Explique-moi » | B2 |
| `App/Sources/Features/Dictionary/` | recherche, fiche mot, mots cliquables | B2 |
| `App/Sources/Features/Progress/` | tableau de progression | B2 |
| `App/Sources/DesignSystem/` | `Theme.swift` (fourni) + composants | B2 (B1 utilise) |
| `App/Sources/ScreenTime/` | `RestrictionManager`, `AppSelectionView`, stockage App Group côté app | A |
| `App/Sources/Notifications/` | `NotificationScheduler` | A |
| `Shared/` | état partagé App Group app ↔ extensions | A |
| `Extensions/` | les trois extensions Screen Time | A |
| `project.yml`, `Config/`, `.github/workflows/`, entitlements, `Info.plist` | projet | A |

## Vues publiques entre équipes (noms et initialiseurs figés)

Fournies par **B2** :
- `HomeView()` — racine de l'app connectée (dans un `NavigationStack` fourni par B2).
- `LessonFlowView(controller: LessonController, onClose: @escaping () -> Void)` — plein écran.
- `ExerciseInputView(exercise: Exercise, presentation: PresentationMode, onSubmit: @escaping (AnswerSubmission) -> Void)` — zone de réponse réutilisable (aussi utilisée par le diagnostic de l'onboarding).
- `TappableSentenceView(text: String, languageCode: String)` — phrase dont chaque mot ouvre sa fiche.
- `WordSheet(item: DictionaryItem)`, `DictionaryView()`, `ProgressDashboardView()`.
- `TutorSheet(subject: TutorSubject)`.

Fournies par **B1** :
- `RootView()`, `SettingsView()`, `PrivacyPolicyView()`.

Fournies par **A** :
- `AppSelectionView(onDone: @escaping () -> Void)` — explication + `FamilyActivityPicker` + choix du mode + enregistrement. Utilisée par l'onboarding (étape 7) et les réglages.

Les vues lisent les services via `@Environment(AppEnvironment.self) private var env`.

## Règles communes

- Textes d'interface **en français**, tutoiement, phrases courtes. Une seule action principale par écran (`.buttonStyle(.primary)`).
- Accessibilité : Dynamic Type (aucune taille de police fixe), `accessibilityLabel` sur les icônes, cibles ≥ 44 pt, `@Environment(\.accessibilityReduceMotion)` respecté, contrastes du `Theme`.
- Mode sombre via les couleurs du `Theme`.
- Pas de `!` de déverrouillage forcé sur des données externes, pas de `try!`.
- Concurrence : services et contrôleurs `@MainActor @Observable` ; types de données `Sendable` ; pas de `DispatchQueue` sauf nécessité.
- Journalisation avec `os.Logger` (sous-système `$(PRODUCT_BUNDLE_IDENTIFIER)`), sans données personnelles.
