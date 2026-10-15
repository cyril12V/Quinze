# Limites connues

## Vérifications qui restent à faire

1. **L'app iOS n'a jamais été compilée pour iOS.** Le code a été écrit sans Mac. Ce qui a été vérifié :
   - la syntaxe de tous les fichiers ;
   - les services non graphiques, compilés sous Linux contre des simulations des frameworks Apple ;
   - une relecture ligne à ligne.

   La première vraie compilation se fait dans la CI GitHub (`ios.yml`). Il faut s'attendre à quelques erreurs de type à corriger au premier passage, en particulier sur les signatures exactes du SDK Supabase, SwiftData et la concurrence stricte de Swift 6.
2. **Le blocage Screen Time n'a pas été testé sur un iPhone.** C'est la phase 0 bloquante de ton cahier des charges (§6.8). Le protocole est prêt : [02-faisabilite-apple.md](02-faisabilite-apple.md) et [tests/screen-time-test-plan.md](tests/screen-time-test-plan.md). Points à confirmer en priorité :
   - le déclenchement du moniteur app fermée, et son retard éventuel ;
   - le comportement après redémarrage ;
   - la notification envoyée depuis l'écran de blocage ;
   - les apps système qui restent ouvertes en mode « tout bloquer sauf » ;
   - le changement de fuseau horaire ou d'heure.
3. **L'autorisation « Family Controls (Distribution) » d'Apple est nécessaire** pour TestFlight et l'App Store, pour les 4 identifiants. Le délai n'est pas garanti. Sans elle, l'app fonctionne en développement sur un iPhone enregistré, mais ne peut pas être distribuée.
4. **Le corpus doit être relu par un humain** avant publication (§7.3) : voir [08-contenus.md](08-contenus.md).

## Points que seule une compilation Xcode tranchera

La relecture « compilateur » a corrigé toutes les erreurs certaines. Les points ci-dessous sont **probablement acceptés** par le compilateur. S'ils échouent dans la CI, la correction est indiquée.

- **Archive TestFlight.** Elle se fait avec Xcode 26 (Swift 6.2), alors que la compilation locale de vérification a été faite en Swift 6.0. La CI compile aussi avec Xcode 26 pour couvrir cet écart.
- **`RestrictionManager.swift`.** `AuthorizationCenter` (non `Sendable`) est appelé avec `await` depuis l'acteur principal.
- **`RootView.swift`, `SettingsView.swift`, `OnboardingScheduleScreenTimeView.swift`.** Des closures `Binding(get:set:)` lisent l'état de la vue. Au pire, Xcode émet des avertissements.
- **`LessonCorrectionView.swift` (`DiffTokenView`).** La chaîne de modificateurs est longue. Si Xcode signale « unable to type-check in reasonable time », extraire les booléens dans des propriétés.
- **`HomeComponents.swift`.** `Text("\(slot.scheduledTime)")` : si Xcode refuse, écrire `Text(slot.scheduledTime.description)`.
- **`LessonController`** (`@MainActor`, `let id`) et sa conformité à `Identifiable` : si Xcode refuse, déclarer `nonisolated let id`.
- **`Persistence.swift`.** Les `#Predicate` sur des champs `@Attribute(.unique)` sont conformes à la documentation, mais SwiftData n'a pas pu être compilé ici.

## Direction artistique : points à valider à l'écran

- **Icônes.** Nucleo est une bibliothèque payante : les icônes affichées sont des SF Symbols au trait fin. Pour passer à Nucleo, ajouter les SVG au catalogue d'assets sous le nom `nucleo-<nom>` (liste dans `QIcon`, `DAComponents.swift`) : ils remplacent automatiquement les symboles, sans toucher aux écrans.
- **Photos.** Les personnes détourées ne sont pas fournies. Les emplacements affichent un visuel pastel abstrait tant que les images manquent (noms dans `docs/design/direction-artistique.md`).
- **Carrousel de l'accueil.** La card suivante doit dépasser légèrement. Si ce n'est pas le cas à l'écran, ajuster la constante `carouselPeek` dans `HomeView.swift`.
- **Taille des illustrations d'onboarding.** Elle est calculée pour l'iPhone SE. Si le bouton est poussé hors de l'écran, ajuster `reservedHeight` dans `FlowHero` (`FlowComponents.swift`).
- **Interlignage des gros titres.** SwiftUI sous iOS 17 ne permet pas un interlignage de 1,05 : les titres utilisent l'interlignage natif de la police, avec l'approche resserrée du brief.
- **Feuilles du bas.** Elles ont le fond gris de l'app, et non un fond blanc, pour que les cards blanches qu'elles contiennent restent visibles.
- **Contrastes.** Les gris du brief sont légèrement assombris (#6E6A65 pour le petit texte, #8C8883 pour la navigation inactive). Sur les cards pastel, le texte secondaire est presque noir, pour respecter le ratio de 4,5:1.
- **Mode sombre.** Le brief décrit le mode clair. Le mode sombre, exigé par le cahier des charges (§14.6), reprend la même structure avec des pastels assourdis.

## Limites imposées par iOS (non contournables)

- Le blocage **n'est pas inviolable**. L'utilisateur peut retirer l'autorisation Temps d'écran dans Réglages à tout moment, et l'app l'affiche honnêtement (§6.7).
- Les API publiques **ne permettent pas de bloquer tout l'iPhone avec une liste d'exceptions arbitraire**. Téléphone, appels d'urgence et Réglages ne sont jamais bloqués, et c'est voulu. Le mode « tout bloquer sauf les apps autorisées » s'appuie sur les catégories d'apps.
- **Un écran de blocage ne peut pas ouvrir l'app Quinze.** Le bouton « Compris » ferme l'app bloquée et envoie une notification qui invite à ouvrir Quinze.
- **Les choix d'apps ne se transfèrent pas** d'un iPhone à l'autre : ce sont des jetons opaques propres à l'appareil, donc à refaire sur un nouvel iPhone (§3.3).
- **Le serveur ne peut ni déclencher ni lever un blocage** : tout se passe sur l'appareil.
- **Les notifications peuvent être désactivées** par l'utilisateur ; elles ne servent que de rappel.

## Limites fonctionnelles de la V1

- **Répétitions d'exercices dans la journée.** Avec 10 exercices par leçon, trois sessions par jour en consomment environ 33. Le moteur évite d'abord les exercices déjà faits dans la journée mais, faute de stock (surtout les premiers jours et pour un apprenant en difficulté), il en répète parfois un : de 0 à 18 répétitions par jour d'après la simulation. Solution : passer à 20 à 30 exercices par leçon.
- **Correction des réponses libres.** Hors ligne, une réponse libre correcte mais formulée autrement que les réponses prévues reste « en attente ». Elle est alors notée par l'IA au retour du réseau, et l'utilisateur en est informé à l'écran. En ligne, l'IA peut rarement se tromper : son verdict est contraint par le contenu validé, et un verdict incertain n'est pas compté comme une erreur.
- **Prononciation.** Elle utilise la synthèse vocale d'iOS, dont la qualité dépend des voix installées sur l'iPhone. Les enregistrements validés sont prévus pour plus tard (§11.4).
- **Niveau estimé.** Le diagnostic donne un niveau indicatif (« Débutant » à « Pré-intermédiaire »), jamais un niveau CECRL certifié (§4).
- **Suppression d'un compte créé avec Apple.** La révocation du jeton Apple, recommandée par Apple, n'est pas encore implémentée : voir [06-deploiement-backend.md](06-deploiement-backend.md).
- **Politique de confidentialité.** Elle contient des champs à compléter : nom de l'éditeur, adresse, contact et région d'hébergement.
- **Paramètres du moteur.** Les seuils de maîtrise, les intervalles FSRS et la composition des sessions ont été calibrés par simulation. Ils devront être ajustés avec des données réelles (§12.3).

## Hors périmètre V1 (§25)

Réseau social, classement, compétition, boutique, paiements, abonnements, vidéos, conversation vocale IA, reconnaissance vocale avancée, parcours arabe complet, Android, version web, administration pédagogique complexe.
