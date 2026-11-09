# Prompt : créer une app iPhone pour apprendre l'anglais (style Quinze)

Tu vas concevoir, coder et livrer une app iPhone complète pour apprendre l'anglais, de A1 à B2, pour un francophone. Le nom de travail est **Quinze** (modifiable). L'idée centrale : **les apps qui distraient restent bloquées tant que la leçon du créneau n'est pas faite**. Tout ce qui suit est le cahier des charges. Lis-le en entier avant d'écrire du code.

Mes trois mots d'ordre, à appliquer partout : **ludique, compréhension, logique**. On comprend d'abord, on s'entraîne ensuite, et rien n'avance tant que ce n'est pas acquis.

---

## 1. Ce que vit l'utilisateur

1. **Premier lancement :**
   - prénom ;
   - niveau ressenti, puis un court test de positionnement adaptatif qui place dans le parcours ;
   - choix des horaires des trois créneaux (par défaut 9 h, 14 h, 20 h) ;
   - autorisation Temps d'écran et choix des apps à bloquer.
2. **Chaque jour, trois créneaux** (matin, après-midi, soir). À l'heure du créneau, les apps choisies sont bloquées. L'utilisateur ouvre l'app, fait sa séance (5 min par défaut, réglable), et les apps se débloquent dès la séance validée.
3. **Les trois séances de la journée sont différentes :**

   | Séance | Contenu |
   |---|---|
   | Matin | Rappel de mémoire de la veille, puis une nouvelle leçon |
   | Après-midi | Rappel de la leçon du matin, puis une nouvelle leçon |
   | Soir | Bilan du jour et révisions espacées. Nouvelle leçon seulement si rien n'a été appris dans la journée. |

   Au plus 2 nouvelles leçons par jour.
4. **Accueil :**
   - le créneau en cours et son état (à faire, en cours, fait) ;
   - la prochaine leçon ;
   - l'heure du prochain blocage ;
   - la série de jours ;
   - un bouton « Entraînement libre » pour une séance de plus quand on veut.
5. **Onglets :** Accueil, Parcours (modules et leçons, cadenas, contrôles), Mots & jeux (dictionnaire, séries de mots, petits jeux), Progrès (leçons validées, maîtrise par notion, erreurs fréquentes, révisions à venir).

---

## 2. Pédagogie : règles non négociables

- **Apprendre avant d'être interrogé.** Chaque leçon commence par de courtes cartes de cours :
  - la règle expliquée simplement, avec le pourquoi ;
  - 3 ou 4 exemples traduits ;
  - les erreurs classiques des francophones ;
  - une astuce ;
  - une carte par mot nouveau (mot, traduction, exemple, audio).

  Les questions ne portent **que** sur ce qui a été enseigné, dans cette leçon ou avant.
- **Une erreur ne passe jamais.** Après une mauvaise réponse :
  1. on montre l'explication et la bonne réponse ;
  2. la même question revient deux questions plus loin ;
  3. puis une question semblable sur la même notion, jusqu'à 2 essais supplémentaires.

  Répondre au hasard ne suffit pas pour finir.
- **Validation d'une leçon à 80 %** de bonnes réponses du premier coup. Sinon, la leçon est reprise à la séance suivante, cours compris, et on ne passe pas à la suite.
- **Contrôle de fin de module (80 %)**, qui ouvre le module suivant. En cas d'échec, la séance suivante est une révision ciblée du module, puis on repasse le contrôle.
- **Répétition espacée FSRS.** Chaque notion et chaque mot ont un état mémoire. Ils reviennent quand ils risquent d'être oubliés : environ 1 jour, 3 jours, 1 semaine, 1 mois. Le lendemain on revoit la veille, et à J+7 on revoit la semaine passée.
- **Le haut de l'écran dit toujours où on en est :** Cours, Rappel, Nouvelle leçon, Révision, On réessaie, Contrôle du module, Bilan du jour.
- **Fin de séance :** un écran de verdict clair (leçon validée ou à reprendre, contrôle réussi ou raté), les erreurs revues et ce qui arrive ensuite.

---

## 3. Le programme

Il compte 12 modules, environ 90 leçons, au moins 1 200 exercices et 700 fiches de dictionnaire. Tu écris toi-même tout le contenu.

| Module | Titre | Contenu |
|---|---|---|
| m01 | Fondations | pronoms, be, articles, salutations, chiffres |
| m02 | Verbes essentiels | have, do, can, like, want, impératif |
| m03 | Présent | présent simple, présent continu, fréquence, questions et négations |
| m04 | Passé | prétérit régulier et irrégulier, was/were, used to |
| m05 | Futur | will, going to, présent pour le futur |
| m06 | Vocabulaire courant | maison, travail, ville, nourriture, temps, corps, émotions |
| m07 | Construction de phrases | ordre des mots, questions en wh-, connecteurs, comparatifs et superlatifs |
| m08 | Consolidation | révision active de m01 à m07 |
| m09 | Expériences et récits | present perfect (for/since, just, already, yet), past continuous, récit |
| m10 | Hypothèses et conditions | conditionnels 0, 1, 2, 3 ; wish ; modaux de déduction |
| m11 | Passif, relatives, discours rapporté | passif, propositions relatives, reported speech |
| m12 | Anglais pro et nuances | e-mails, réunions, phrasal verbs, faux amis, registres |

**Règles d'écriture**
- Explications en français, simples, courtes, au tutoiement.
- Anglais britannique par défaut ; l'orthographe américaine est acceptée.
- Prénoms simples (Tom, Anna, Sam, Lucy, Ben, Emma) et lieux connus.
- Les exemples réutilisent le vocabulaire déjà vu.
- Pour chaque leçon :
  - 5 à 9 cartes de cours ;
  - 18 à 24 exercices variés ;
  - 3 à 5 exercices qui révisent les leçons précédentes ;
  - un `hint`, une `explanation` et un `tip` par exercice ;
  - les erreurs typiques prévues avec un retour ciblé.

**Format et identifiants**
- Le contenu est écrit en JSON source : `Content/en/source/mNN/` contient `outline.json`, `units.json`, `dictionary.json`, `course/lNN.json` et `lessons/lNN.json`. Il est compilé en un seul fichier `en.json` lu par l'app.
- Identifiants stables, jamais renommés une fois publiés :

  | Objet | Format |
  |---|---|
  | Notion | `en.gNN.slug` |
  | Mot | `en.v.slug` |
  | Fiche de dictionnaire | `en.d.slug` |
  | Leçon | `en.lNN` |
  | Exercice | `en.lNN.eKK` |

**Validateur obligatoire** : un script `tools/build_content.py` refuse tout contenu invalide.
- Il refuse :
  - un champ manquant ;
  - un identifiant en double ou inconnu ;
  - une réponse absente des options ;
  - une bonne réponse qui n'a pas été enseignée avant (ni dans le cours ni dans le vocabulaire) ;
  - deux exercices avec le même énoncé ;
  - un nombre de cartes ou d'exercices hors limites ;
  - un mot introduit deux fois.
- Il valide un module à la fois (`--module m03`) ou tout le contenu.
- Si tu délègues l'écriture à des sous-agents, donne-leur un brief commun et un module chacun. Un mot appartient au module de plus petit numéro qui l'introduit ; les autres le réutilisent par son identifiant.

---

## 4. Exercices et correction

**Types d'exercices**
- `mcq` : QCM ;
- `fill_blank` : trou à compléter, tapé ou avec options ;
- `translation` : FR → EN et EN → FR ;
- `reorder` : remettre les mots dans l'ordre ;
- `match` : associer des paires ;
- `free_answer` : phrase libre avec contraintes, par exemple « doit contenir went ».

**Correction de niveau 1 : déterministe, hors ligne, dans le moteur**
- **Normalisation :**
  - Unicode NFC, minuscules, apostrophes et guillemets unifiés, ponctuation finale ignorée ;
  - contractions développées en variantes (he's = he is ou he has, can't = cannot) ;
  - chiffres = lettres ;
  - orthographe britannique ou américaine ;
  - traits d'union ignorés.
- **Ordre de décision :**
  1. réponse acceptée ;
  2. erreur prévue, avec son retour ;
  3. tolérance d'accents et d'apostrophes ;
  4. contraintes de la réponse libre ;
  5. mêmes mots dans un autre ordre ;
  6. alignement mot à mot.

  Pendant l'alignement :
  - **Variante grammaticale** du même mot (goes/go, went/go, a/an, in/on) : c'est une erreur de conjugaison, de temps, de préposition ou de grammaire, jamais une faute de frappe.
  - **Faute de frappe** acceptée avec remarque si la distance d'édition est de 1 ou 2 et que le mot tapé n'existe pas dans le lexique.
  - **Réponse partielle** si au moins 60 % des mots attendus sont là, dans l'ordre.
- **Retour toujours en français et concret :** « Le mot "goes" ne convient pas ici : on attend "go". », « Il manque "to". »
- Une option touchée est comparée à la lettre près.

**Correction de niveau 2 : l'IA, facultative.** Une traduction ou une réponse libre qui ne correspond à rien de prévu est peut-être juste mais formulée autrement. On la marque « en attente », puis on demande son avis à Claude. Sans réseau ou sans clé, l'app montre la réponse attendue et demande à l'utilisateur si la sienne était juste.

---

## 5. Blocage des apps (Temps d'écran)

**Frameworks Apple utilisés**
- `FamilyControls` : autorisation `.individual` et `FamilyActivityPicker`.
- `ManagedSettings` : un `ManagedSettingsStore` nommé par créneau, pour que lever un créneau ne lève jamais l'autre.
- `DeviceActivity` : une surveillance quotidienne par créneau, avec une extension `DeviceActivityMonitor` qui pose le blocage même app fermée.
- Extensions `ShieldConfiguration` et `ShieldAction` : l'écran de blocage avec un message, et un bouton « Déblocage de secours » journalisé.

**État partagé et logique de créneau**
- L'état est partagé entre l'app et les extensions dans un App Group : JSON versionné, protégé par un verrou de fichier.
- Une seule machine à états de créneau, partagée par l'app et les extensions, gère démarrage, validation, expiration, secours et récupération.

**Robustesse**
- Une fonction `reconcile()` s'exécute au lancement et au retour au premier plan. Elle efface les blocages périmés ou déjà validés et réapplique celui de la fenêtre active.
- Les changements de fuseau horaire sont gérés.
- Chaque blocage a une durée maximale.
- Si l'autorisation Temps d'écran est retirée, l'app le détecte et affiche une alerte.

**Honnêteté envers l'utilisateur.** Le blocage n'est pas infranchissable : l'autorisation est révocable, et Téléphone et Réglages ne sont pas bloquables. L'interface le dit.

**Notifications locales**
- Avant chaque créneau.
- Au blocage : « Ouvre Quinze pour faire ta leçon ». Un écran de blocage ne peut pas ouvrir l'app.

**Sans autorisation** (simulateur, refus), l'app fonctionne sans blocage.

---

## 6. Voix, professeur IA, dictionnaire, réglages

**Voix**
- Lecture de l'anglais par `AVSpeechSynthesizer` (en-GB).
- Un bouton haut-parleur sur les énoncés, les exemples et les mots.
- Choix de la voix (les voix Premium et Améliorées si elles sont installées), aperçu, vitesse.
- Un mot touché dans une phrase anglaise affiche sa fiche.

**Professeur IA**
- Un bouton « Explique-moi » après une erreur, l'explication d'un mot, et la correction des réponses libres (niveau 2).
- Appels directs à l'API Claude depuis l'iPhone, sans serveur, avec un petit modèle rapide (famille Haiku).
- La clé API est collée par l'utilisateur dans les réglages, gardée **uniquement dans le trousseau iOS** (Keychain), avec boutons tester, remplacer et supprimer.
- Sans clé, les explications intégrées au contenu suffisent.

**Dictionnaire**
- Recherche FR ↔ EN avec les formes fléchies (went → go).
- Fiche complète : traduction, exemples, prononciation audio, notes, mots liés.
- Bouton « Apprendre ce mot », qui l'ajoute aux révisions.

**Mots & jeux**
- Séries de mots par thème.
- Petits jeux : associer, retrouver le mot, vrai ou faux, mot manquant. Ils nourrissent la répétition espacée.

**Réglages**
- Horaires des créneaux, minutes par séance, apps bloquées.
- Apparence : clair par défaut, sombre ou automatique.
- Voix, clé IA.
- Réinitialisation de la progression, avec confirmation.

**Pas de compte** : tout est stocké en local sur l'iPhone.

---

## 7. Design

Le style est doux et moderne, ludique sans être enfantin :
- cartes pastel (jaune, bleu, rose, vert), grands titres, coins très arrondis, ombres légères ;
- une police arrondie lisible, par exemple Plus Jakarta Sans embarquée (licence OFL) ;
- une barre d'onglets en bas avec des icônes maison ;
- des animations sobres : apparition des cartes, bouton qui s'enfonce, confettis discrets à la validation ;
- un retour haptique sur juste et faux.

L'accessibilité est obligatoire : Dynamic Type, VoiceOver sur chaque contrôle, contrastes suffisants, compatibilité avec l'iPhone SE. Toute l'interface est en français, au tutoiement.

---

## 8. Technique

- **Langage et versions :** SwiftUI, Swift 6 en concurrence stricte, iOS 17 minimum.
- **Projet :** généré par **XcodeGen** (`project.yml`). Aucun `.xcodeproj` versionné.
- **Persistance :** SwiftData pour les séances, les tentatives et l'état mémoire. `UserDefaults` sert seulement aux réglages, et l'App Group à l'état partagé avec les extensions.
- **Moteur pédagogique : un package Swift séparé `LearningCore`.**
  - Il est pur et déterministe : seulement Foundation, aucune API dépendante de la locale, aléatoire avec une graine (SplitMix64), aucun état caché.
  - Il prend un instantané de l'apprenant et le contenu, et renvoie des plans de séance, des évaluations et des états mis à jour. L'app persiste le résultat.
  - Il compile sur iOS, macOS **et Linux** pour être testé partout.
  - Composants :
    - `ContentIndex` ;
    - `AnswerEvaluator` et `TextNormalizer` ;
    - `FSRS` et `MemoryUpdater` ;
    - `MasteryCalculator` ;
    - `LessonSelector` ;
    - `SessionPlanner` : séances matin, après-midi et soir, contrôles de module, retours d'erreurs ;
    - `SessionRunner` : machine à états d'une séance ;
    - `Diagnostic` : test de placement ;
    - `Dictionary` ;
    - `registerCompletion` : décide si une leçon ou un contrôle est validé.
- **Cibles :**
  - l'app ;
  - les extensions `DeviceActivityMonitor`, `ShieldConfiguration` et `ShieldAction` ;
  - un dossier `Shared/` pour le code commun (machine à états des créneaux, état partagé, contrôle des blocages).
- **Tests (XCTest sur `LearningCore`) :**
  - la normalisation et toutes les règles de correction ;
  - FSRS et la planification ;
  - la logique de créneau ;
  - le chargement du vrai `en.json`, avec trois vérifications :
    - toutes les références se résolvent ;
    - chaque bonne réponse est acceptée et chaque erreur prévue est refusée ;
    - deux semaines simulées de trois séances par jour progressent sans séance vide.

---

## 9. Compiler et installer sans Mac

L'utilisateur n'a pas de Mac. Tout passe par **GitHub Actions** (runner `macos-15`, Xcode récent).

**Workflows**
1. `compile.yml` : compile sans signature à chaque push.
2. `engine-tests.yml` : `swift test` sur `LearningCore` et le build du contenu.
3. `iphone.yml` : lancé à la main. Il compile une version **signée** (certificat et profil de développement fournis en secrets GitHub, Family Controls de développement), envoie l'`.ipa` sur **Diawi** avec le jeton `DIAWI_TOKEN` en secret, et affiche le lien d'installation dans le journal.

**Guide pas à pas en français** (`docs/installer-sur-mon-iphone.md`) pour un débutant :
- compte Apple Developer (obligatoire pour Temps d'écran) ;
- secrets GitHub ;
- enregistrement de l'iPhone (UDID) ;
- mode développeur sur l'iPhone ;
- installation par le lien.

Une nouvelle version s'installe **par-dessus** l'ancienne et garde la progression : ne jamais changer l'identifiant de l'app ni effacer les données sans migration.

---

## 10. Sécurité et vie privée

- Le dépôt GitHub peut être public. Aucun secret dans le code ni dans l'historique : pas de clé API, pas de certificat, pas de jeton. Tout secret passe par les secrets GitHub ou le trousseau de l'iPhone.
- Les jetons d'apps de Temps d'écran ne quittent jamais l'appareil.
- Aucune donnée n'est envoyée ailleurs que vers l'API Claude, et seulement quand la clé est fournie et que l'IA est sollicitée.

---

## 11. Méthode de travail

Avance par phases. À la fin de chacune, tout compile, les tests passent, et tu fais un commit et un push.

1. **Socle :** `project.yml`, app vide, CI de compilation, package `LearningCore` avec ses modèles et tests.
2. **Moteur :** normalisation, correction, FSRS, planification, séances, contrôles, avec des tests à chaque étape.
3. **Contenu :** brief d'écriture, validateur, puis les modules l'un après l'autre (m01 d'abord, testé de bout en bout, puis le reste).
4. **App :** onboarding, accueil, séance (cours, exercices, retours, verdict), parcours, progrès, dictionnaire et jeux, réglages, voix.
5. **Blocage :** Temps d'écran, extensions, créneaux, notifications, récupération.
6. **IA :** client Claude direct, gestion de la clé dans le trousseau.
7. **Livraison :** workflow signé et Diawi, guide d'installation, documentation dans `docs/` (architecture, moteur, contenu, limites connues).

**Règles de travail**
- Code et commentaires en anglais, interface et documentation en français.
- Pas de dépendance externe sauf nécessité réelle.
- Quand un comportement d'Apple n'est pas garanti (heure exacte des extensions, périmètre du blocage), écris-le dans `docs/limites-connues.md` au lieu de le promettre.
- Avant de dire qu'une phase est finie, vérifie : compilation verte, tests verts, contenu validé sans erreur.

**Critère de réussite final.** Je mets l'app sur mon iPhone par le lien Diawi. À 9 h, Instagram est bloqué. J'ouvre l'app, je lis le cours, je fais la leçon : chaque erreur revient jusqu'à être juste. Je valide à 80 %, Instagram se débloque. Le lendemain matin, la séance commence par un rappel de la veille.
