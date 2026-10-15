# 07 — CI/CD et TestFlight sans Mac

Ce guide s'adresse à une personne qui **n'a pas de Mac**. Tout se passe dans un navigateur : GitHub compile, signe et envoie l'app sur TestFlight depuis des machines macOS hébergées. Il faut suivre les étapes dans l'ordre ; l'étape 4 (demande Apple) est la plus longue, la lancer dès que possible.

## Vue d'ensemble

| Workflow | Fichier | Quand | Ce qu'il fait |
|---|---|---|---|
| Moteur pédagogique | `.github/workflows/engine.yml` | à chaque modification de `Packages/LearningCore` | `swift build` et `swift test` sur Linux (Swift 6.0) et sur macOS |
| iOS | `.github/workflows/ios.yml` | à chaque `push` sur `main`, à chaque pull request, à la demande | XcodeGen, compilation pour iOS Simulator sans signature, tests `QuinzeTests` |
| TestFlight | `.github/workflows/testflight.yml` | à la demande, ou quand on pousse un tag `vX.Y.Z` | XcodeGen, archive signée automatiquement, export de l'IPA, envoi sur TestFlight |

Le projet Xcode n'est pas versionné : il est généré par XcodeGen à partir de `project.yml`. Le numéro de build est le numéro d'exécution du workflow (plus un décalage facultatif).

## 1. Compte Apple Developer

1. Créer ou utiliser un identifiant Apple avec l'authentification à deux facteurs.
2. S'inscrire à l'Apple Developer Program (abonnement annuel payant) sur `https://developer.apple.com/programs/`. L'inscription en tant qu'organisation demande des vérifications supplémentaires et prend plus de temps.
3. Une fois le compte actif, noter l'**identifiant d'équipe (Team ID)** : developer.apple.com > Compte > Adhésion > « Identifiant d'équipe » (10 caractères). C'est le secret `DEVELOPMENT_TEAM`.

## 2. Identifiants d'app (App IDs) et App Group

Sur `https://developer.apple.com/account/resources/identifiers/list` :

1. **Créer l'App Group** : filtre « App Groups » > `+` > identifiant `group.fr.elmdigitalagency.quinze` (le préfixe doit être le même que `BUNDLE_ID_PREFIX`).
2. **Créer les 4 App IDs** (« App IDs » > `+` > « App ») avec ces identifiants explicites (Bundle ID) :
   - `fr.elmdigitalagency.quinze`
   - `fr.elmdigitalagency.quinze.monitor`
   - `fr.elmdigitalagency.quinze.shieldconfig`
   - `fr.elmdigitalagency.quinze.shieldaction`
3. Activer les capacités :
   - sur les **quatre** : « App Groups » (Configurer > cocher `group.fr.elmdigitalagency.quinze`) et « Family Controls (Development) » ;
   - sur l'app `fr.elmdigitalagency.quinze` seulement : « Sign in with Apple ».
4. Si vous changez de préfixe, remplacez-le partout de la même façon (secret `BUNDLE_ID_PREFIX`, App Group, App IDs).

> La signature automatique de la CI peut créer elle-même les identifiants manquants, mais les créer à la main permet de voir les erreurs tout de suite.

## 3. Pourquoi Family Controls bloque tout tant qu'Apple n'a pas répondu

L'app utilise Family Controls (Temps d'écran) pour restreindre des apps. En développement la capacité s'active seule, mais **pour TestFlight il faut une autorisation spéciale d'Apple, par identifiant**. Sans elle, l'étape « Archiver » de `testflight.yml` échoue avec un message du type « Provisioning profile … doesn't include the com.apple.developer.family-controls entitlement ». C'est normal et attendu.

## 4. Demande « Family Controls (Distribution) »

1. Ouvrir `https://developer.apple.com/contact/request/family-controls-distribution` avec le compte titulaire.
2. Faire **une demande par Bundle ID** (les quatre ci-dessus), avec le texte suggéré dans `docs/02-faisabilite-apple.md` §3.
3. Attendre la réponse d'Apple (aucun délai garanti ; prévoir de quelques jours à plusieurs semaines). Une fois accordée, la capacité « Family Controls (Distribution) » apparaît dans la configuration de l'App ID.
4. En attendant, les workflows `engine.yml` et `ios.yml` fonctionnent déjà, et on peut valider tout le reste de l'app. Si Apple refuse, l'app reste utilisable sans blocage (repli décrit dans `docs/02-faisabilite-apple.md` §6).

## 5. Fiche de l'app dans App Store Connect

1. Aller sur `https://appstoreconnect.apple.com/apps` > `+` > « Nouvelle app ».
2. Plateforme iOS ; nom « Quinze » (ou le nom définitif) ; langue principale : français ; **ID de l'app** : choisir `fr.elmdigitalagency.quinze` ; SKU : `quinze` ; accès complet.
3. Les trois extensions n'ont pas de fiche : elles voyagent dans l'app.
4. Dans « Confidentialité de l'app », renseigner l'URL de la politique de confidentialité (le texte est dans `PrivacyPolicy.md`).

## 6. Clé d'API App Store Connect

1. App Store Connect > Utilisateurs et accès > Intégrations > « API App Store Connect » > « Clés d'équipe » > `+`.
2. Nom : `GitHub CI`. Accès : **Admin** (nécessaire pour que Xcode puisse créer les certificats et profils de distribution gérés dans le cloud).
3. **Télécharger le fichier `AuthKey_XXXXXXXXXX.p8` immédiatement** : Apple ne le propose qu'une fois. Noter :
   - l'**ID de la clé** (`XXXXXXXXXX`) : secret `ASC_KEY_ID` ;
   - l'**ID de l'émetteur** (Issuer ID, un UUID affiché en haut de la page) : secret `ASC_ISSUER_ID`.
4. **Encoder le fichier en base64** (sans Mac, sans site web : ne jamais coller une clé privée dans un site tiers) :
   - Windows PowerShell : `[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\chemin\AuthKey_XXXXXXXXXX.p8"))`
   - Linux ou WSL : `base64 -w0 AuthKey_XXXXXXXXXX.p8`
   Copier la longue chaîne obtenue : secret `ASC_KEY_P8`.
5. Ne jamais ajouter le `.p8` au dépôt (le `.gitignore` l'exclut). S'il fuite : révoquer la clé dans App Store Connect et en créer une autre.

## 7. Secrets GitHub

Dépôt GitHub > Settings > Secrets and variables > Actions > « New repository secret ». Créer ces sept secrets :

| Secret | Valeur | Où la trouver |
|---|---|---|
| `ASC_KEY_ID` | ID de la clé API | Étape 6 |
| `ASC_ISSUER_ID` | ID de l'émetteur | Étape 6 |
| `ASC_KEY_P8` | Contenu du `.p8` en base64 | Étape 6 |
| `DEVELOPMENT_TEAM` | Team ID (10 caractères) | Étape 1 |
| `BUNDLE_ID_PREFIX` | `fr.elmdigitalagency` | Le préfixe choisi à l'étape 2 |
| `SUPABASE_URL` | `https://xxxx.supabase.co` | Supabase > Project Settings > API > Project URL |
| `SUPABASE_ANON_KEY` | clé « anon public » | Supabase > Project Settings > API. **Jamais** la clé `service_role` |

Facultatif, dans l'onglet « Variables » : `BUILD_NUMBER_OFFSET` (un nombre entier). Le numéro de build envoyé à Apple est `numéro d'exécution + décalage` ; il doit toujours augmenter. À utiliser si le dépôt est recréé ou si Apple répond « le numéro de build doit être supérieur au précédent ».

Le workflow vérifie d'abord que les sept secrets existent et signale ceux qui manquent.

## 8. Lancer les workflows

- **Moteur et iOS** : ils démarrent seuls à chaque `push` sur `main` et pour chaque pull request. Résultat dans l'onglet « Actions » (pastille verte = réussi).
- **TestFlight, à la main** : onglet « Actions » > « TestFlight » > « Run workflow ». On peut renseigner la version (par exemple `1.0.0`) et choisir l'outil d'envoi (`fastlane`, par défaut, ou `altool` en secours).
- **TestFlight, par tag** : créer un tag `v1.0.0` (GitHub > Releases > « Draft a new release » > créer le tag) ; le workflow part tout seul et prend `1.0.0` comme version.
- Durée : de 15 à 30 minutes. Le traitement chez Apple ajoute de 5 à 30 minutes après l'envoi.

> **Coût** : sur un dépôt privé, les minutes macOS comptent plus (facteur 10 sur les offres incluses). Quelques exécutions TestFlight et iOS peuvent consommer le quota mensuel gratuit ; vérifier la page de facturation de GitHub et fixer une limite de dépense. Les workflows annulent les exécutions en double (`concurrency`) pour limiter la consommation.

## 9. Installer l'app avec TestFlight

1. App Store Connect > Utilisateurs et accès : ajouter votre identifiant Apple comme testeur interne (il peut être le titulaire du compte).
2. Sur l'iPhone, installer l'app « TestFlight » depuis l'App Store et se connecter avec le même identifiant.
3. Quand le traitement est terminé (e-mail d'Apple, ou App Store Connect > TestFlight > Builds : « Prêt à tester »), ouvrir TestFlight, accepter l'invitation, toucher « Installer ».
4. Si le build reste sur « Conformité à l'exportation manquante », ce n'est pas le cas ici : la clé `ITSAppUsesNonExemptEncryption` est déjà à `false` dans l'Info.plist.
5. Pour tester le blocage, suivre `docs/tests/screen-time-test-plan.md`.

## 10. Lire une erreur de CI

1. Onglet « Actions » > cliquer sur l'exécution en échec > cliquer sur l'étape en rouge. Les erreurs de compilation contiennent `error:` avec le nom du fichier et la ligne.
2. Le **résumé** de l'exécution (page de l'exécution, en bas) liste les lignes d'erreur principales.
3. L'artefact `ios-logs` ou `testflight-build` (en bas de la page, conservé 7 jours) contient les journaux complets.
4. Pour demander de l'aide : copier les lignes contenant `error:` (pas le journal entier) et le nom de l'étape.

| Message ou symptôme | Cause probable | Que faire |
|---|---|---|
| « Le secret GitHub X est absent ou vide » | Secret oublié ou mal nommé | Étape 7 ; respecter la casse |
| `No profiles for 'fr…' were found` ou `doesn't include the com.apple.developer.family-controls entitlement` | Family Controls (Distribution) pas encore accordée pour cet identifiant | Étapes 3 et 4 ; vérifier les quatre identifiants |
| `Communication with Apple failed` / `Authentication credentials are missing or invalid` | Clé API incorrecte : `ASC_KEY_P8` mal encodé, mauvais `ASC_KEY_ID` ou `ASC_ISSUER_ID` | Refaire l'étape 6 (encodage sur une seule ligne) |
| `Your session has expired` / `forbidden` / `Cloud signing permission error` | Rôle de la clé insuffisant | Créer une clé avec l'accès « Admin » |
| `There is no profile for … in team` / `Failed to register bundle identifier` | App ID absent ou mauvais préfixe | Étape 2 ; vérifier `BUNDLE_ID_PREFIX` |
| `The bundle version must be higher than the previously uploaded version` | Numéro de build déjà utilisé | Variable `BUILD_NUMBER_OFFSET` supérieure |
| `ITMS-91053: Missing API declaration` ou `ITMS-91061` | Manifeste de confidentialité incomplet | Le manifeste de l'app doit déclarer `UserDefaults` avec les raisons `CA92.1` et `1C8F.1` |
| `Unable to find a destination matching…` (tests) | Simulateur introuvable | Relancer ; l'étape « Choisir un simulateur iPhone » détecte normalement un iPhone iOS 17+ |
| `Spec validation error` / `Could not find` (XcodeGen) | Erreur dans `project.yml` ou dossier manquant | Lire la ligne indiquée ; corriger `project.yml` |
| `error: ... cannot find 'X' in scope` / erreurs Swift | Erreur de code | Copier les lignes `error:` et corriger le fichier indiqué |
| Étape macOS très longue puis annulée | Dépassement du délai ou quota | Relancer ; vérifier la facturation |

## 11. Sécurité

- Aucun secret n'est écrit dans le dépôt : `Config/Secrets.xcconfig` et les `.p8` sont ignorés par git ; la CI recrée le fichier de configuration à partir des secrets, puis supprime la clé en fin d'exécution.
- La clé « anon » Supabase est publique par conception (elle est dans l'app) ; la protection vient des règles RLS de la base. Ne jamais mettre la clé `service_role` dans l'app ni dans les secrets de ce workflow.
- Limiter l'accès au dépôt : les secrets GitHub ne sont pas fournis aux pull requests venant de forks.

## 12. Résumé de la check-list de lancement

1. Compte Apple Developer actif, Team ID noté.
2. App Group et 4 App IDs créés avec les capacités.
3. Demande « Family Controls (Distribution) » envoyée pour les 4 identifiants.
4. Fiche de l'app créée dans App Store Connect.
5. Clé API créée (rôle Admin), `.p8` encodé en base64.
6. 7 secrets GitHub créés.
7. `ios.yml` vert sur `main`.
8. Accord d'Apple reçu, puis « Run workflow » sur `TestFlight`.
9. Installation par TestFlight, puis plan de test sur appareil.
