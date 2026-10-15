# Aide-mémoire API (à jour iOS 17/18, Swift 6)

Ces notes résument les API à utiliser, pour éviter les recherches longues. En cas de doute réel sur une signature, vérifie ponctuellement sur developer.apple.com ou supabase.com/docs/reference/swift (une recherche ciblée, pas une exploration).

## Outils disponibles dans cet espace

- Swift 6.0.3 pour **Linux** : `source /opt/swiftlang/env.sh`. Il compile et teste `Packages/LearningCore` (`swift build`, `swift test`). Il **ne connaît pas** SwiftUI, SwiftData, FamilyControls, UIKit, etc.
- Pour le code iOS : `swiftc -parse fichier.swift …` vérifie la **syntaxe** (sans résolution des types). À lancer sur tous les fichiers que tu écris. Le reste (types, API) doit être relu avec soin : la compilation iOS réelle se fera dans la CI GitHub Actions (macOS).

## FamilyControls

- `AuthorizationCenter.shared.requestAuthorization(for: .individual) async throws` (iOS 16+).
- `AuthorizationCenter.shared.authorizationStatus` : `.notDetermined`, `.denied`, `.approved` (AuthorizationCenter est un `ObservableObject`, `$authorizationStatus` est publié).
- `FamilyActivitySelection` : `Codable`, `Equatable`. `applicationTokens: Set<ApplicationToken>`, `categoryTokens: Set<ActivityCategoryToken>`, `webDomainTokens: Set<WebDomainToken>`. `FamilyActivitySelection(includeEntireCategory: true)` (iOS 15.2+).
- Vue : `FamilyActivityPicker(selection: $selection)` ou modificateur `.familyActivityPicker(isPresented:selection:)`. `Label(token)` affiche l'icône et le nom d'une app ou d'une catégorie à partir d'un jeton.
- Les jetons sont opaques et propres à l'appareil : stockage local uniquement (App Group), jamais sur le serveur.
- Simulateur : l'autorisation échoue, à traiter comme `.unavailable`.

## ManagedSettings

- `ManagedSettingsStore(named: .init("quinze.morning"))` (iOS 16+), ou `extension ManagedSettingsStore.Name { static let morning = Self("quinze.morning") }`. Un store nommé par créneau : les boucliers de chaque store se cumulent, et vider un store ne touche pas les autres.
- `store.shield.applications = Set<ApplicationToken>?`
- `store.shield.applicationCategories = .specific(categoryTokens, except: allowedAppTokens)` ou `.all(except: allowedAppTokens)` (type `ShieldSettings.ActivityCategoryPolicy<Application>`).
- `store.shield.webDomains = Set<WebDomainToken>?` ; `store.shield.webDomainCategories = .specific(…)` / `.all(except:)`.
- `store.clearAllSettings()`.
- Non restrictible : Téléphone, appels d'urgence, et les réglages système eux-mêmes. L'utilisateur peut toujours retirer l'autorisation dans Réglages > Temps d'écran.
- `ManagedSettingsStore` n'est pas `Sendable` : l'utiliser depuis le `@MainActor` dans l'app et directement dans les méthodes des extensions.

## DeviceActivity

- `DeviceActivityName("quinze.slot.morning")`.
- `DeviceActivitySchedule(intervalStart: DateComponents(hour:minute:), intervalEnd: DateComponents(hour:minute:), repeats: true, warningTime: nil)`.
- `let center = DeviceActivityCenter()` ; `try center.startMonitoring(name, during: schedule)` ; `center.stopMonitoring([names])` ; `center.activities`.
- Erreurs `DeviceActivityCenter.MonitoringError` : `.excessiveActivities`, `.intervalTooLong`, `.intervalTooShort` (minimum 15 min), `.invalidDateComponents`, `.unauthorized`.
- Si on démarre la surveillance alors que l'heure courante est **dans** l'intervalle, `intervalDidStart` est en général appelé aussitôt. **À confirmer sur appareil** : l'app doit de toute façon appliquer elle-même le bouclier dans ce cas (réconciliation).
- Extension : `class QuinzeMonitor: DeviceActivityMonitor { override func intervalDidStart(for activity: DeviceActivityName) {…} override func intervalDidEnd(for activity: DeviceActivityName) {…} }` (appeler `super`). Limite mémoire d'environ 6 Mo : rien de lourd.
- Info.plist de l'extension : `NSExtensionPointIdentifier = com.apple.deviceactivity.monitor-extension`, `NSExtensionPrincipalClass = $(PRODUCT_MODULE_NAME).QuinzeMonitor`.

## ManagedSettingsUI (extensions de bouclier)

- Configuration : `class ShieldConfigurationExtension: ShieldConfigurationDataSource`. Surcharges : `configuration(shielding application: Application) -> ShieldConfiguration`, `configuration(shielding application: Application, in category: ActivityCategory)`, `configuration(shielding webDomain: WebDomain)`, `configuration(shielding webDomain: WebDomain, in category: ActivityCategory)`.
- `ShieldConfiguration(backgroundBlurStyle: UIBlurEffect.Style?, backgroundColor: UIColor?, icon: UIImage?, title: ShieldConfiguration.Label?, subtitle: ShieldConfiguration.Label?, primaryButtonLabel: ShieldConfiguration.Label?, primaryButtonBackgroundColor: UIColor?, secondaryButtonLabel: ShieldConfiguration.Label?)` ; `ShieldConfiguration.Label(text: String, color: UIColor)`.
- `NSExtensionPointIdentifier = com.apple.ManagedSettingsUI.shield-configuration-service`.
- Action : `class ShieldActionExtension: ShieldActionDelegate`. Surcharges : `handle(action: ShieldAction, for application: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void)`, puis la même avec `for webDomain: WebDomainToken` et `for category: ActivityCategoryToken`. `ShieldAction` : `.primaryButtonPressed`, `.secondaryButtonPressed`. `ShieldActionResponse` : `.none`, `.close`, `.defer`.
- `NSExtensionPointIdentifier = com.apple.ManagedSettings.shield-action-service`.
- Un bouclier **ne peut pas ouvrir une autre app**. Pour inviter à ouvrir Quinze, on envoie une notification locale depuis l'extension d'action.

## Entitlements et distribution

- `com.apple.developer.family-controls = true` sur l'app **et** sur chaque extension.
- `com.apple.security.application-groups = [group.<prefix>.quinze]` sur les quatre cibles.
- `com.apple.developer.applesignin = [Default]` sur l'app.
- Family Controls fonctionne en développement. Pour TestFlight et l'App Store, il faut l'autorisation « Family Controls (Distribution) », demandée via developer.apple.com/contact/request/family-controls-distribution, **pour chaque bundle ID** (app et extensions).

## XcodeGen (project.yml)

- `options: { bundleIdPrefix, deploymentTarget: { iOS: "17.0" }, developmentLanguage: fr }`.
- `packages: { LearningCore: { path: Packages/LearningCore }, Supabase: { url: https://github.com/supabase/supabase-swift, from: 2.5.0 } }`.
- Cible : `type: application` / `app-extension` / `bundle.unit-test`, `platform: iOS`, `sources`, `dependencies: [{target: QuinzeMonitor}, {package: LearningCore, product: LearningCore}]` (une dépendance de cible vers une extension l'**intègre** automatiquement).
- `info: { path: App/Info.plist, properties: {…} }` génère l'Info.plist ; `entitlements: { path: …, properties: {…} }` génère le fichier d'entitlements.
- `configFiles: { Debug: Config/Base.xcconfig, Release: Config/Base.xcconfig }`.
- `settings: { base: { SWIFT_VERSION: "6.0", SWIFT_STRICT_CONCURRENCY: complete } }`.
- Dans un xcconfig, `//` démarre un commentaire : écrire `SUPABASE_URL = https:/$()/xxx.supabase.co`.

## Supabase Swift v2 (`import Supabase`)

- `SupabaseClient(supabaseURL: URL, supabaseKey: String, options: SupabaseClientOptions(auth: .init(redirectToURL: URL(string: "quinze://auth-callback"), flowType: .pkce)))`. La session est stockée dans le Keychain par défaut.
- Auth :
  - `try await client.auth.signUp(email:password:redirectTo:)` → `AuthResponse` (`.session` facultative, `.user`) ;
  - `try await client.auth.signIn(email:password:)` → `Session` ;
  - `try await client.auth.signInWithIdToken(credentials: OpenIDConnectCredentials(provider: .apple, idToken: token, nonce: rawNonce))` ;
  - `try await client.auth.signOut()` ;
  - `try await client.auth.resetPasswordForEmail(email, redirectTo: URL(string: "quinze://reset-password"))` ;
  - `try await client.auth.session(from: url)` traite un lien profond ;
  - `try await client.auth.update(user: UserAttributes(password: new))` ;
  - `client.auth.currentSession`, `client.auth.currentUser` ;
  - `for await (event, session) in client.auth.authStateChanges { … }` (`.initialSession`, `.signedIn`, `.signedOut`, `.tokenRefreshed`, `.userUpdated`, `.passwordRecovery`).
- PostgREST :
  - `try await client.from("daily_schedules").upsert(row, onConflict: "user_id").execute()` ;
  - `let p: ProfileRow = try await client.from("profiles").select().eq("id", value: uid).single().execute().value`.
- RPC : `let r: SyncPushResponse = try await client.rpc("sync_push", params: SyncPushParams(payload: …)).execute().value`. Les clés des paramètres correspondent aux noms des arguments SQL : `payload`, `p_language_id`, `p_since`.
- Edge Functions : `let r: T = try await client.functions.invoke("ai/explain-answer", options: FunctionInvokeOptions(method: .post, body: requestEncodable))`. Erreurs : `FunctionsError.httpError(code: Int, data: Data)`, `FunctionsError.relayError`.
- Définis des `CodingKeys` explicites en snake_case dans les DTO, et encode les dates toi-même en chaînes ISO 8601 : ne dépends pas des réglages de l'encodeur du SDK.

## Divers iOS

- Sign in with Apple : `SignInWithAppleButton(.continue, onRequest: { $0.requestedScopes = [.email]; $0.nonce = sha256(rawNonce) }, onCompletion: { result in … })`. On récupère `ASAuthorizationAppleIDCredential.identityToken` (Data → String UTF-8). SHA-256 via CryptoKit.
- SwiftData : `@Model final class …` ; `@Attribute(.unique) var id: String`. Pour les structures complexes (MemoryState, SessionRunner, AttemptRecord), stocker un `Data` JSON plutôt qu'un type composite Codable : c'est plus fiable. Ajouter à côté des champs scalaires pour les requêtes (unitId, day, slot, dirty, updatedAt). `ModelContainer(for: A.self, B.self)` ; `container.mainContext` (MainActor).
- UserNotifications : `UNUserNotificationCenter.current()`.
  - `requestAuthorization(options: [.alert, .sound, .badge]) async throws -> Bool` ;
  - `add(UNNotificationRequest(identifier:content:trigger: UNCalendarNotificationTrigger(dateMatching:repeats: false))) async throws` ;
  - `removePendingNotificationRequests(withIdentifiers:)` ;
  - `pendingNotificationRequests() async` ;
  - `notificationSettings() async` → `.authorizationStatus`.
  - Limite : 64 notifications en attente.
- Synthèse vocale : `AVSpeechSynthesizer`, `AVSpeechUtterance(string:)`, `.voice = AVSpeechSynthesisVoice(language: "en-GB")`, `.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85`. Les méthodes du délégué sont appelées hors acteur principal : déclarer `nonisolated func speechSynthesizer(_:didFinish:)` puis `Task { @MainActor in … }`.
- Réseau : `NWPathMonitor()` ; `pathUpdateHandler` est `@Sendable` (revenir sur le MainActor) ; `start(queue: DispatchQueue(label: "net"))`.
- Changement de fuseau : `NotificationCenter.default.notifications(named: .NSSystemTimeZoneDidChange)` ou `UIApplication.significantTimeChangeNotification`.
