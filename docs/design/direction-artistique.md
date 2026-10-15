# Direction artistique — « éditoriale pastel »

L'app est **moderne, rassurante, facile, pédagogique et premium accessible**. Elle n'est ni « Duolingo enfantin », ni « dashboard corporate », ni « app IA futuriste ».

Ses ingrédients :
- fond gris-blanc légèrement froid ;
- gros titres noirs ;
- grandes cards pastel (rose, bleu, jaune, vert doux) ;
- boutons noirs en pilule ;
- icônes au trait fin ;
- personnes détourées sur des formes pastel ;
- graphiques plats à grosses barres arrondies ;
- énormément d'espace.

Le code de référence est dans `App/Sources/DesignSystem/`. Tous les écrans utilisent ces jetons et composants, jamais de valeurs en dur.

## Règle de composition

Chaque écran comporte **un élément fort**, un ou deux blocs secondaires, et beaucoup de vide. On ne met jamais plusieurs dizaines de cards, de menus, d'alertes ou de tableaux sur le même écran. Peu de texte : un titre de 2 à 3 lignes au maximum, un sous-titre court.

## Jetons (`Theme.swift`)

| Rôle | Jeton | Valeur claire |
|---|---|---|
| Fond de page | `Theme.background` | #F6F7FA |
| Cards blanches, champs, boutons ronds | `Theme.surface` | #FFFFFF |
| Encre (titres, boutons, état actif) | `Theme.ink` / texte posé dessus : `Theme.onInk` | #181818 / blanc |
| Gros titres | `Theme.primaryText` | #171717 |
| Sous-titres | `Theme.secondaryText` | #66635F |
| Petit texte | `Theme.tertiaryText` | #6E6A65 |
| Texte secondaire sur une card pastel | `Theme.onPastelSecondary` | #4A4547 (le gris serait illisible) |
| Navigation inactive | `Theme.inactive` | #8C8883 |
| Pastels | `Theme.pink` #E8B5EF, `pinkSoft` #F3D8F5, `blue` #C7DDF6, `yellow` #F6DEA0, `yellowStrong` (barres) #E5BE5A, `green` #93D76E, `greenSoft`, `peach` #F6C6A8 | |
| Rayons | `Radius.small` 16 (champs, petits blocs), `medium` 22 (cards secondaires), `mediumLarge` 24 (mini stats, portraits), `large` 28 (grandes cards, feuilles), `xl` 30 (cards de cours et de graphique) ; pilules : `Capsule()` | |
| Espacements | `Spacing.page` 20 (marges latérales), `section` 28 (en-tête → titre, entre sections), `titleToContent` 26, `card` 14 (entre cards) | |

**Polices** : Plus Jakarta Sans, en 4 graisses seulement (`Theme.Font`).

| Usage | Jeton |
|---|---|
| Titre d'onboarding (38) | `display` |
| Titre d'écran (34) | `largeTitle` |
| Titre de card (22) | `title` |
| Grosse valeur (28) | `statValue` |
| Valeur de mini stat (20) | `miniStatValue` |
| Question (22) | `prompt` |
| Titre de bloc (17) | `headline` |
| Texte courant (16) | `body` |
| Sous-titre (15, medium) | `callout` |
| Bouton (14, semibold) | `button` |
| Petit texte (12) | `caption` |
| Pilules (11, semibold) | `badge` |
| Libellé d'en-tête (10) | `micro` |

Pour une autre graisse, écrire `Theme.Font.body(.semibold)` : jamais `.weight()` sur une police Jakarta. Jamais `.font(.system…)` ni `.font(.headline)` dans un écran.

**Mode sombre** : chaque jeton a une variante sombre (fond #111214, pastels assourdis, boutons « encre » inversés). Les écrans n'ont rien à faire de particulier.

## Composants (`DAComponents.swift`, `Components.swift`, `MainTabView.swift`)

| Besoin | Composant |
|---|---|
| Page défilante standard (fond, marges de 20, largeur max de 720 sur iPad) | `QScreen { … }` |
| En-tête des écrans internes | `AppHeader(label:title:initials:avatarAction:trailingIcon:trailingLabel:trailingAction:)` |
| Gros titre / sous-titre | `ScreenTitle("…")` (`display: true` en onboarding), `ScreenSubtitle("…")` |
| Titre de card | `CardTitle("…")` |
| Bouton principal (noir, 58 pt) | `Button(…).buttonStyle(.primary)` |
| Bouton secondaire (pilule blanche) | `.buttonStyle(.secondary)` |
| Bouton noir dans une card (44 pt + rond play) | `CardCTA(title:icon:action:)` |
| Bouton rond blanc 42 pt | `RoundIconButton(icon:label:action:)` |
| Icônes | `QIconView(icon: .bell, size: 20)`. Le jeu `QIcon` est compatible Nucleo : déposer `nucleo-<nom>` dans les Assets |
| Grande card pastel | `PastelCard(.pink) { … }` (alternance : `Pastel.cycle(i)`) |
| Card blanche secondaire | `.card()` |
| Pilule (niveau, type, statut) | `QPill(text:icon:)` |
| Filtres | `FilterChip(title:icon:iconFill:isSelected:action:)` |
| Avatars superposés + badge vert | `AvatarStack(initials:ring:badge:)` ; avatar seul : `QAvatar` |
| Illustration d'onboarding | `HeroIllustration(imageName:pastel:accent:diameter:)`, qui découpe un cercle pastel en diagonale |
| Portrait dans une card | `PortraitSlot(imageName:)` (140 × 180, rayon 24) |
| Graphique | `ChartCard(icon:detail:value:caption:) { RoundedBarChart(data:highlighted:) }` |
| Mini statistiques | `StatGrid { StatMiniCard(icon:value:label:pastel:) … }` |
| Champs de saisie | `TextField(…).qField(isFocused:)` + `QFieldLabel("…")` |
| Feuille du bas | `.qSheet()` sur le contenu de la feuille (rayon 28, poignée) |
| Chargement | `SkeletonCard()`, `SkeletonBlock()` (shimmer) ; jamais de spinner seul |
| État vide | `EmptyStateView(icon:pastel:message:actionTitle:action:)` |
| Apparition | `.qAppear(index)` (fondu + translation de 8 pt, 50 ms entre cards) |
| Encadré doux (astuce, info) | `QCallout(systemImage:tint:fill:)` ; `fill` pastel doux, `tint` `Theme.ink` |
| Choix (QCM, mots) | `.buttonStyle(QChipButtonStyle(isSelected:))` : pilule blanche, noire une fois sélectionnée |
| Navigation du bas | `MainTabView` / `QBottomNav` : Accueil, Parcours, Dictionnaire, Progrès |

Interdits :
- bordures dures ;
- ombres, sauf `.floatingShadow()` sur une card réellement flottante ;
- rayons de 4 à 10 ;
- dégradés ;
- bleu SaaS ;
- tableaux ;
- plus de deux pastels sur un même bloc ;
- icônes pleines, sauf pour l'onglet actif.

## Navigation

`RootView` affiche `MainTabView` une fois l'utilisateur connecté. Chaque onglet est enveloppé dans **sa propre** `NavigationStack` par `MainTabView`. Les vues racines des onglets ne créent donc pas de `NavigationStack`. Elles masquent la barre système (`.toolbar(.hidden, for: .navigationBar)`) et dessinent `AppHeader`.

Sur chaque onglet :
- l'avatar de l'en-tête ouvre `SettingsView`, en `navigationDestination` ou en lien ;
- le bouton rond de droite dépend de l'écran.

Les écrans poussés gardent la barre système (déjà stylée par `QAppearance`), avec un titre court.

## Photos

Les vraies personnes détourées sont des PNG à fond transparent, de 1 200 px de haut minimum. Les règles :
- lumière naturelle ;
- vêtements pastel ;
- pas d'image corporate ;
- rendu « éditorial », pas banque d'images scolaire.

Elles s'ajoutent dans `App/Resources/Assets.xcassets` comme jeux d'images, sous les noms suivants. Tant qu'une image manque, un visuel abstrait pastel la remplace automatiquement.

| Nom | Emplacement |
|---|---|
| `onboarding-welcome` | Bienvenue (forme rose) |
| `onboarding-level` | Choix du niveau (forme bleue) |
| `onboarding-schedule` | Horaires (forme jaune) |
| `onboarding-focus` | Temps d'écran (forme verte) |
| `lesson-cover` | Portrait de la card « prochaine leçon » de l'accueil |
| `module-1` … `module-8` | Portraits des cards du parcours |
| `session-done` | Fin de session |

## Écrans

**Onboarding**
- Structure : grande illustration, gros titre (`display`, 2 à 3 lignes), grand espace, bouton principal.
- Les étapes de saisie (compte, horaires) remplacent l'illustration par des blocs blancs et des champs `qField`.

**Accueil** (modèle « dashboard »)
- En-tête : « Bonjour » + prénom ; à droite, un bouton calendrier qui ouvre la feuille des 3 leçons du jour.
- Titre court et dynamique.
- Rangée de 3 `FilterChip` : les créneaux du jour avec leur heure, l'état visible par l'icône et la couleur.
- Carrousel horizontal de grandes cards pastel, la card suivante partiellement visible. La première est la prochaine leçon : pilule de type, titre, durée, `PortraitSlot`, `CardCTA` « Commencer ».
- Puis deux mini stats : série et révisions.
- Une card jaune si le test de consolidation est dû.
- Si les apps sont restreintes : une card avec « Déblocage d'urgence » en bouton secondaire.

**Parcours** (`PathView`, nouvel onglet)
- En-tête + titre « Ton parcours », filtres Tous / En cours / Terminés.
- Grandes cards de module en couleurs alternées : pilule « Module 3 », titre, « 9 leçons · 4 faites », barre de progression, `PortraitSlot`.
- Une card ouvre la liste des leçons du module, en lecture seule. Le système choisit toujours la leçon : aucun bouton pour en lancer une précise.

**Progrès** (modèle « statistiques »)
- En-tête + titre.
- `ChartCard` jaune : temps d'apprentissage des 7 derniers jours, en minutes calculées à partir des tentatives, barre du jour en noir avec infobulle rose.
- Deux `StatMiniCard` rose et bleu (mots maîtrisés, règles maîtrisées), puis deux autres vert et jaune (réussite, série).
- Les catégories en cards blanches avec barre de progression, puis « Comment c'est calculé ? ».
- Le détail des notions dans un écran poussé.

**Leçon**
- Une question par écran : barre de progression noire en haut, bouton rond de fermeture.
- Grande card pastel pour la question, couleur selon le type d'exercice. Réponses en pilules blanches, sélection en noir.
- « Vérifier » en bouton principal.
- Correction : card verte « Bonne réponse » ou card rose « À revoir », chacune avec son icône dans un rond noir. Puis la réponse attendue, l'explication en card blanche, l'astuce dans un encadré jaune doux, « Explique-moi » en secondaire et « Continuer » en principal.

**Fin de session**
- Forme verte et icône de validation, gros titre.
- Deux mini stats.
- Notions travaillées en pilules.
- État des restrictions dans une card noire, texte blanc.
- Bouton principal « Terminer ».

**Dictionnaire**
- En-tête + titre, champ de recherche `qField` avec icône.
- Résultats en lignes blanches (rayon 16), mots suivis en pilules pastel.
- État vide illustré.
- Fiche mot en feuille `.qSheet()` : le mot en `display`, la prononciation et le bouton d'écoute rond, les exemples en card bleue, « Ne pas confondre » en card jaune.
- « Apprendre ce mot » en noir.

**Professeur IA** : feuille `.qSheet()`, réponses en cards blanches ou bleues, suggestions en `FilterChip`, champ `qField` avec un bouton rond noir d'envoi.

**Réglages** : sections en cards blanches (rayon 22), libellés de section en `caption(.semibold)`. Le déblocage d'urgence est un bouton secondaire, le changement d'horaire passe par des champs blancs.

## Accessibilité (non négociable)

- Dynamic Type partout : les polices sont `relativeTo:`, aucune hauteur fixe sur du texte.
- Cibles d'au moins 44 pt et contrastes AA (d'où `onPastelSecondary` et les gris légèrement assombris).
- VoiceOver : libellés sur les boutons-icônes, graphiques résumés en une phrase.
- Reduce Motion respecté par tous les composants animés.
- Aucune information portée par la seule couleur : une icône ou un texte l'accompagne toujours.
