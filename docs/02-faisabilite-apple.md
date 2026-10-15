# 02 — Faisabilité Apple du blocage d'applications (Phase 0, §6.8 et §24)

Rapport de la phase 0 « validation technique préalable » du système de blocage. Il dit précisément ce que les API publiques d'Apple permettent, ce qu'elles ne permettent pas, comment le code de Quinze s'appuie dessus, et ce qui **doit encore être confirmé sur un iPhone physique**. Le code décrit ici est écrit et compile en CI ; son comportement réel n'est pas encore prouvé : cette phase est bloquante tant que le protocole du §5 n'a pas été passé.

Statut au moment de la rédaction : **implémentation prête, validation sur appareil non faite**. Rien dans ce document ne doit être lu comme une garantie de fonctionnement.

## 1. Architecture retenue

| Besoin | Mécanisme | Où dans le code |
|---|---|---|
| Autorisation Temps d'écran (individuelle) | `FamilyControls` — `AuthorizationCenter.shared.requestAuthorization(for: .individual)` | `RestrictionManager.requestAuthorization()` |
| Choix des apps, catégories, sites | `FamilyActivityPicker` ; jetons opaques (`ApplicationToken`, `ActivityCategoryToken`, `WebDomainToken`) | `AppSelectionView` |
| Activation automatique sans ouvrir l'app | `DeviceActivity` : une surveillance quotidienne répétée par créneau (`quinze.slot.morning`, `.afternoon`, `.evening`) + extension `DeviceActivityMonitor` | `RestrictionManager.apply(schedule:)`, `Extensions/DeviceActivityMonitor` |
| Restriction | `ManagedSettings` : un `ManagedSettingsStore` **nommé par créneau** (`quinze.store.<slot>`), si bien que lever A ne lève jamais B | `Shared/ShieldController.swift` |
| Écran de restriction | `ManagedSettingsUI` : extensions `ShieldConfiguration` et `ShieldAction` | `Extensions/ShieldConfiguration`, `Extensions/ShieldAction` |
| État partagé app ↔ extensions | `UserDefaults` de l'App Group `group.<préfixe>.quinze`, JSON versionné, lecture-modification-écriture protégée par un verrou de fichier | `Shared/SharedState.swift`, `Shared/SharedStateStore.swift` |
| Logique de créneau (démarrage, fin, validation, secours, récupération) | Une seule machine à états, partagée par l'app et les extensions | `Shared/SlotEngine.swift` |

Les jetons ne quittent jamais l'appareil : ils sont stockés dans l'App Group, jamais synchronisés ni envoyés au serveur.

## 2. Ce que les API publiques permettent, et ce qu'elles ne permettent pas

Légende : **Confirmé** = documenté par Apple et utilisé tel quel ; **À confirmer** = comportement dépendant du système, à observer sur appareil (protocole §5).

### Exigences du §6 de la spécification

| Exigence | Ce qu'Apple permet | Ce qu'Apple ne permet pas / réserves | Statut |
|---|---|---|---|
| §6.1 Restreindre les apps choisies à l'heure du créneau, sans lancer l'app | Une extension `DeviceActivityMonitor` est lancée par le système au début de l'intervalle, même app fermée, et peut écrire dans un `ManagedSettingsStore` | Le système ne garantit pas la seconde près ; l'extension peut être retardée ou tuée (limite mémoire d'environ 6 Mo) | À confirmer |
| §6.1 L'app pédagogique reste accessible | En mode « apps choisies », seules les apps choisies sont masquées | En mode « tout sauf », l'utilisateur doit autoriser Quinze lui-même (le jeton de Quinze est opaque, on ne peut pas l'ajouter automatiquement) ; sans cela, Quinze serait bloquée. Garde-fou : refus d'appliquer le mode « tout sauf » sans au moins une app autorisée | Confirmé (limite documentée) |
| §6.1 Levée à la fin de la leçon | `store.clearAllSettings()` depuis l'app au moment de la validation | — | Confirmé |
| §6.2 Trois créneaux indépendants | Un nom de `DeviceActivity` et un `ManagedSettingsStore` par créneau | Les boucliers de plusieurs stores se cumulent ; si deux créneaux se chevauchent, une app reste bloquée tant qu'**un** des deux est actif (comportement voulu) | Confirmé / à confirmer pour le cumul |
| §6.3 Mécanismes système, pas seulement des notifications | `FamilyControls`, `ManagedSettings`, `DeviceActivity`, extension de moniteur, stores nommés : tous utilisés | — | Confirmé |
| §6.4 Sélection étendue, « autant d'apps distrayantes que possible » | `FamilyActivityPicker` permet de choisir des catégories entières ; mode `.all(except:)` pour « tout sauf les apps autorisées » | **Pas de verrouillage universel avec liste d'exceptions arbitraire** : les exceptions du mode « tout » sont des apps (pas des catégories) ; Téléphone, appels d'urgence et Réglages ne sont pas restreignables ; la liste exacte du périmètre réellement restreint doit être relevée sur appareil | À confirmer (périmètre) |
| §6.4 Ne pas promettre un contrôle total | L'interface le dit : essentiel toujours disponible, Temps d'écran révocable | — | Fait dans `AppSelectionView` |
| §6.5 Déblocage à la validation | `RestrictionManager.sessionCompleted(slot:day:)` lève le store du créneau et enregistre la validation pour que le moniteur ne restreigne pas | La validation avant l'heure (départ anticipé) marque le créneau comme fait : le moniteur ne le restreindra pas | Confirmé (logique) |
| §6.6 Déblocage de secours | Bouton secondaire du bouclier (extension `ShieldAction`) + `RestrictionManager.emergencyUnlock(reason:)` ; journal dans l'état partagé | Si l'extension `ShieldAction` n'est pas exécutée par le système, le secours depuis l'app reste disponible | À confirmer |
| §6.6 Expiration maximale | Chaque intervalle a une fin (`intervalDidEnd` efface le store) ; chaque enregistrement actif porte une échéance (`expiresAt`) ; `reconcile` efface tout ce qui est périmé | Si `intervalDidEnd` n'est pas livré (extension tuée, redémarrage), l'effacement attend le prochain `reconcile` (ouverture de l'app) ou la fin du créneau suivant. **Cas non couvert à 100 %** : voir risque R2 | À confirmer |
| §6.6 Récupération après plantage | `reconcile(now:)` au lancement et au retour au premier plan : efface les boucliers périmés, validés, ou sans enregistrement ; réapplique le bouclier si on est dans une fenêtre active | — | Confirmé (logique) |
| §6.6 Changements d'heure et de fuseau | Les intervalles `DeviceActivity` sont en heure murale ; l'app relance la surveillance quand le fuseau change (`NSSystemTimeZoneDidChange`, `significantTimeChangeNotification`, vérification à chaque `reconcile`) | Si l'app est fermée au moment du changement, la correction attend la prochaine ouverture ; les échéances absolues déjà posées restent valables | À confirmer |
| §6.6 Détection de révocation | `authorizationStatus` relu au lancement et au retour au premier plan ; comparaison avec le dernier état « approuvé » mémorisé ; alerte locale | Apple ne notifie pas l'app d'une révocation : la détection se fait à la prochaine ouverture. Les boucliers disparaissent d'eux-mêmes à la révocation (à confirmer) | À confirmer |
| §6.6 Conflits entre plusieurs sessions | Un store et un enregistrement par créneau ; `reconcile` traite chaque créneau séparément | — | Confirmé (logique) |
| §6.6 Synchronisation app ↔ extensions | App Group + verrou de fichier `flock` + verrou de processus ; les appels `ManagedSettings` se font dans la section critique | Pas de notification inter-processus : l'app relit l'état à l'ouverture | Confirmé |
| §6.7 Ne pas bloquer l'essentiel ni l'aide | Téléphone et appels d'urgence ne sont pas restreignables par ces API ; bouton de secours sur chaque bouclier | La liste précise des apps système restreignables est à relever sur appareil | À confirmer |
| §6.7 Autorisations gérables par l'utilisateur | Réglages > Temps d'écran > Apps avec accès à Temps d'écran | — | Confirmé |

### Ce qui n'est pas possible (à ne pas promettre)

- Bloquer « toutes les apps » avec des exceptions choisies librement : le mode « tout sauf » existe mais n'accepte que des apps en exception, et certaines fonctions système restent hors de portée.
- Ouvrir Quinze depuis le bouclier : un bouclier ne peut qu'afficher deux boutons et se fermer. Quinze envoie donc une notification locale « Ouvre Quinze pour faire ta leçon ».
- Lire quelles apps l'utilisateur a choisies : les jetons sont opaques ; on affiche leur nom et icône via `Label(token)` uniquement.
- Synchroniser la sélection entre deux appareils : les jetons sont propres à l'appareil.
- Empêcher l'utilisateur de retirer l'autorisation ou de supprimer l'app : le blocage n'est **pas** infranchissable et ne doit jamais être présenté comme tel.
- Garantir l'heure d'exécution des callbacks à la seconde.
- Planifier des intervalles de moins de 15 minutes (`intervalTooShort`) ; la fenêtre de sécurité minimale de Quinze est de 15 minutes.
- Tester dans le simulateur : l'autorisation échoue, l'app traite ce cas comme `.unavailable` et fonctionne sans restriction.

## 3. Droits (entitlements) et demande de distribution

### Droits déclarés

| Cible | Bundle ID (préfixe par défaut `fr.elmdigitalagency`) | Family Controls | App Group | Sign in with Apple |
|---|---|---|---|---|
| Quinze | `fr.elmdigitalagency.quinze` | oui | oui | oui |
| QuinzeMonitor | `fr.elmdigitalagency.quinze.monitor` | oui | oui | non |
| QuinzeShieldConfiguration | `fr.elmdigitalagency.quinze.shieldconfig` | oui | oui | non |
| QuinzeShieldAction | `fr.elmdigitalagency.quinze.shieldaction` | oui | oui | non |

- `com.apple.developer.family-controls = true` sur les quatre cibles.
- `com.apple.security.application-groups = [group.fr.elmdigitalagency.quinze]` sur les quatre cibles.
- `com.apple.developer.applesignin = [Default]` sur l'app seulement.
- Les fichiers sont générés par XcodeGen (`project.yml`) ; le préfixe vient de `BUNDLE_ID_PREFIX`.

### Ce qui change entre développement et distribution

- En développement (profil de développement, appareil enregistré), la capacité Family Controls s'active avec un compte Apple Developer payant.
- **Pour TestFlight et l'App Store, Apple exige l'autorisation « Family Controls (Distribution) », demandée séparément pour chaque bundle ID** (l'app et les trois extensions). Tant qu'elle n'est pas accordée, l'archivage signé échoue avec une erreur de profil d'approvisionnement qui ne contient pas l'entitlement.
- Sans Mac, l'installation sur iPhone passe par TestFlight : **cette demande est donc sur le chemin critique**. Elle doit être envoyée dès le premier jour. Aucun délai n'est garanti par Apple, et un refus est possible.

### Où et comment demander

1. Se connecter avec le compte du titulaire (Account Holder) sur `https://developer.apple.com/contact/request/family-controls-distribution`.
2. Remplir le formulaire une fois par bundle ID (4 demandes), en reprenant l'argumentaire ci-dessous.
3. Conserver les accusés de réception ; une fois accordée, la capacité « Family Controls (Distribution) » apparaît sur l'identifiant dans Certificates, Identifiers & Profiles.

### Texte suggéré (à coller en anglais, adapter les noms)

> **App name:** Quinze — English in 15 minutes a day  
> **Bundle ID:** fr.elmdigitalagency.quinze (repeat for .monitor, .shieldconfig, .shieldaction)  
> **Team:** ELM Digital Agency  
>
> **Why does the app need the Family Controls capability?**  
> Quinze is a language-learning app for adults and teenagers. The user practises English with three five-minute lessons per day, at times the user chooses. The user can opt in to a feature that temporarily shields the distracting apps they select until the current lesson is completed. It uses the individual authorization (`.individual`) only: the user restricts their own device, never someone else's.
>
> **How are the APIs used?**  
> FamilyControls: individual authorization and FamilyActivityPicker so the user chooses the apps. DeviceActivity: one daily repeating schedule per lesson slot and a DeviceActivityMonitor extension that applies the shield when a lesson is due. ManagedSettings: one named store per slot; the shield is lifted when the lesson is completed, after a maximum duration (safety window), or through an always-available emergency unlock. ManagedSettingsUI: shield configuration and action extensions that show a calm message and an emergency unlock button.
>
> **Data handling:** Selection tokens stay on the device (App Group), are never transmitted, and are never used for analytics or advertising. The feature is optional, off by default, explained before authorization, and can be revoked at any time in Settings > Screen Time. Essential functions (phone, emergency calls) remain available and restrictions never last beyond the safety window.

Ne pas présenter Quinze comme une app de contrôle parental : c'est une app d'auto-discipline, ce qui correspond à l'autorisation `.individual`.

## 4. Conséquences sur le planning

| Étape | Dépend de | Remarque |
|---|---|---|
| Compilation et tests unitaires en CI | rien | Déjà possible (`ios.yml`) |
| Envoi de la demande « Distribution » (4 bundle IDs) | compte développeur payant | **À faire en premier** |
| Archive signée / TestFlight | accord d'Apple | `testflight.yml` échoue avant, avec une erreur de profil |
| Prototype sur appareil (§5) | build TestFlight | Pas d'accès à la console Xcode : s'appuyer sur les écrans de diagnostic et le plan de test |

## 5. Protocole de prototype sur appareil physique

À passer sur au moins **deux iPhones** (iOS 17 et iOS 18 si possible), avec un build TestFlight. Pour chaque étape, noter la date, l'appareil, la version d'iOS, le numéro de build, le résultat (réussi, échoué, partiel) et une capture d'écran ou un enregistrement d'écran. Le détail des cas et des résultats attendus est dans `docs/tests/screen-time-test-plan.md`.

Préparation : régler les créneaux à des heures proches (par exemple dans 20, 40 et 60 minutes) avec une fenêtre de sécurité de 15 à 30 minutes ; choisir 2 ou 3 apps distrayantes et une catégorie entière.

1. **Autorisation Temps d'écran (§6.8 point 1).** Ouvrir l'écran de sélection, toucher « Autoriser Temps d'écran », valider avec le code ou Face ID. Attendu : état « autorisé ». Refaire en refusant (état « refusée », bouton « Ouvrir les Réglages »).
2. **Sélection d'applications (point 2).** Ouvrir le sélecteur, choisir apps, une catégorie et un site, enregistrer, quitter et relancer l'app. Attendu : la sélection est conservée (récapitulatif et aperçu).
3. **Programmation d'un horaire (point 3).** Activer la fonctionnalité avec le planning de test. Attendu : les trois créneaux apparaissent dans la liste des activités surveillées (`monitoredSlots`) et aucune erreur n'est affichée. Vérifier le comportement avec une fenêtre de 15 minutes (minimum accepté) et refus propre en dessous.
4. **Activation automatique (point 4).** Fermer l'app (la retirer du sélecteur d'apps), utiliser une app choisie, attendre l'heure du créneau. Attendu : l'app est restreinte à l'heure, sans ouvrir Quinze. Noter le retard éventuel (en secondes).
5. **Écran de restriction (point 5).** Ouvrir une app restreinte. Attendu : message « Leçon de HH:mm en attente », sous-titre, boutons « Compris » et « Déblocage d'urgence ». Appuyer sur « Compris » : le bouclier se ferme et une notification « Ouvre Quinze pour faire ta leçon » arrive. Noter si la notification est bien livrée depuis l'extension.
6. **Validation d'une leçon (point 6).** Ouvrir Quinze, terminer la leçon avec des erreurs (100 % non exigé), voir l'écran de fin. Attendu : la leçon passe à « terminée ».
7. **Levée des restrictions (point 7).** Revenir à l'app restreinte. Attendu : accessible immédiatement ; les autres créneaux non validés ne sont pas levés.
8. **Fonctionnement app fermée (point 8).** Refaire les étapes 4 et 5 après avoir forcé la fermeture de Quinze et verrouillé l'iPhone 5 minutes avant l'heure.
9. **Redémarrage (point 9).** Redémarrer l'iPhone avant un créneau, puis pendant un créneau actif. Attendu : l'activation a lieu quand même ; un bouclier actif au redémarrage est levé au plus tard à l'échéance. Noter si `intervalDidEnd` a bien été livré sans ouvrir l'app.
10. **Autorisation retirée (point 10).** Réglages > Temps d'écran > Apps avec accès à Temps d'écran > Quinze : retirer l'accès, pendant et hors créneau actif. Attendu : plus aucune restriction ; à la réouverture de Quinze, détection, message et notification « Les restrictions ne fonctionnent plus… ».
11. **Déblocage de secours.** Depuis le bouclier puis depuis l'app. Attendu : levée en moins de 5 secondes, entrée dans le journal de secours, pas de réapplication le même jour.
12. **Échéance de sécurité.** Ne pas faire la leçon et ne pas ouvrir l'app jusqu'à la fin de la fenêtre. Attendu : levée à l'heure de fin (± 2 minutes), état « expirée » à la réouverture.
13. **Mode « tout sauf les apps autorisées ».** Autoriser Quinze et deux apps ; vérifier qu'une app non autorisée est bloquée et que Quinze, Téléphone et Réglages restent accessibles. Relever la liste exacte des apps système qui restent ouvertes.
14. **Fuseau horaire et changement d'heure.** Changer le fuseau dans Réglages (et la date vers un passage à l'heure d'été), puis rouvrir Quinze. Attendu : surveillance relancée aux mêmes heures murales.
15. **Conflits.** Activer Temps de repos et une limite d'app Apple sur une app déjà choisie. Attendu : les deux coexistent ; lever Quinze ne lève pas la limite d'Apple.

## 6. Limites connues et alternatives

| Limite | Alternative ou parade |
|---|---|
| Le système peut retarder ou ne pas livrer un callback du moniteur | `reconcile` à chaque ouverture ; échéance absolue `expiresAt` ; la fin d'intervalle efface toujours le store |
| Pas d'ouverture de Quinze depuis le bouclier | Notification locale ; ou raccourci iOS (automatisation personnelle « à telle heure, ouvrir Quinze ») proposé en option dans l'aide |
| Périmètre restrictible incertain | Relevé sur appareil, puis texte d'aide ajusté ; sélection large par catégories |
| Autorisation non accordée (ou Family Controls refusé par Apple) | **Repli sans blocage** : notifications de rappel, streaks et suivi de progression ; guide pour configurer soi-même un Temps de repos ou un Mode de concentration (Focus) aux heures des leçons ; automatisation Raccourcis. L'app reste utilisable à 100 % sans la restriction |
| Utilisateur peut tout désactiver | Assumé et expliqué : Quinze est un outil d'aide, pas un verrou parental |
| Pas de Mac : pas de console ni de débogueur | Écran de diagnostic (état partagé, journal de secours, activités surveillées) à ajouter aux réglages, et captures datées pendant le protocole |

## 7. Risques

| Id | Risque | Probabilité | Impact | Parade |
|---|---|---|---|---|
| R1 | Apple refuse ou retarde Family Controls (Distribution) | moyenne | bloquant pour TestFlight avec restriction | Demande immédiate ; texte du §3 ; repli sans blocage du §6 |
| R2 | `intervalDidEnd` non livré et app jamais ouverte : le bouclier reste après la fenêtre | faible à moyenne | élevé (« jamais indéfiniment ») | Test 9 et 12 du protocole ; si observé, ajouter une surveillance de secours (second intervalle plus court, événement de seuil) ; à défaut, documenter et déclarer le no-go |
| R3 | Extension tuée par la limite mémoire (≈ 6 Mo) | faible | moyen | Extension minimale (état JSON, trois stores) ; pas de dépendance lourde |
| R4 | Retard d'activation important | moyenne | moyen | Mesure au protocole ; réconciliation à l'ouverture |
| R5 | Mode « tout sauf » sans Quinze autorisé : l'app est bloquée | moyenne | élevé | Refus d'appliquer sans app autorisée ; texte d'avertissement ; secours en un geste |
| R6 | Notification de l'extension `ShieldAction` non livrée | moyenne | faible | Vérifier au protocole ; le bouclier reste informatif |
| R7 | Revue App Store : usage de Family Controls jugé non conforme | faible à moyenne | élevé | Fonction optionnelle, désactivée par défaut, expliquée avant l'autorisation ; pas de collecte ; texte de confidentialité à jour |
| R8 | Manifeste de confidentialité incomplet (UserDefaults de l'App Group, raison `1C8F.1`) | moyenne | rejet à l'envoi | Les extensions l'embarquent ; **le manifeste de l'app doit aussi déclarer `NSPrivacyAccessedAPICategoryUserDefaults` avec `1C8F.1`** (en plus de `CA92.1` si utilisé) |
| R9 | Changement d'API dans une future version d'iOS | faible | moyen | Test sur chaque nouvelle version majeure ; CI sur Xcode 26 et Xcode 16 |

## 8. Critères go / no-go

**Go** (le blocage est conservé dans le périmètre de la version 1) si, sur deux appareils :

- les 10 points du §6.8 sont réussis au moins une fois, et l'activation automatique app fermée est reproduite 10 fois sur 10 ;
- l'activation a lieu à moins de 2 minutes de l'heure prévue dans au moins 90 % des essais sur 7 jours ;
- **aucun** bouclier ne dépasse l'échéance de sécurité de plus de 5 minutes sans intervention, y compris après redémarrage (R2) ;
- le déblocage de secours fonctionne depuis le bouclier et depuis l'app en moins de 5 secondes ;
- la révocation de l'autorisation est détectée à la première ouverture suivante, avec message ;
- Téléphone, appels d'urgence et Réglages restent accessibles dans tous les modes ;
- Apple a accordé Family Controls (Distribution) pour les quatre bundle IDs.

**No-go partiel** (basculer vers le repli du §6) si l'un des critères sur l'échéance de sécurité, le secours ou l'accord d'Apple échoue : une restriction qui peut rester indéfiniment est inacceptable (§6.6). Dans ce cas, le développement continue sans blocage, la limite est documentée précisément et une alternative est proposée avant de poursuivre, comme l'exige la spécification.
