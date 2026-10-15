# 05 — Moteur pédagogique (LearningCore)

Ce document décrit le fonctionnement du package Swift `Packages/LearningCore` : évaluation des réponses, répétition espacée, maîtrise, progression, planification des sessions, adaptation, diagnostic et dictionnaire. Le contrat d'interface est dans `docs/contracts/engine-spec.md` ; ce document explique **comment** il est réalisé, avec quelles valeurs, et ce qui a été mesuré.

Principes de conception :

- **Pur et déterministe.** Aucune dépendance autre que Foundation (pas de `NaturalLanguage`, pas de littéraux `Regex`, aucune API dépendante de la locale : `lowercased()` et `folding(options: .diacriticInsensitive, locale: nil)` uniquement). Le package compile sur iOS 17, macOS 14 et Linux, en Swift 6 (concurrence stricte).
- **Reproductible.** Toute décision aléatoire passe par un générateur SplitMix64 initialisé avec `seed ^ hash stable(sel)` (FNV-1a, jamais `hashValue`). Les identifiants des éléments de session (UUID) sont eux aussi tirés de ce générateur : deux plans construits avec la même graine et le même état sont strictement égaux.
- **Sans état caché.** Le moteur ne stocke rien : il lit un `LearnerSnapshot` (Codable) et renvoie des plans, des évaluations et des états mis à jour. L'application persiste le snapshot.
- **Hors ligne.** Le niveau 1 d'évaluation, la planification, le calcul de maîtrise et le diagnostic fonctionnent sans réseau.

## 1. Architecture

```
Sources/LearningPrimitives/Primitives.swift   types partagés avec les extensions (créneaux, jours, horaires)
Sources/LearningCore/
  Content/        ContentModels (contrat), ContentIndex + ContentIndexTables (index construits une fois)
  Learner/        LearnerModels (contrat) : MemoryState, AttemptRecord, LearnerSnapshot, EngineConfiguration
  Evaluation/     Normalizer, WordClassifier, AnswerEvaluator (niveau 1)
  Scheduling/     FSRS (formules), MemoryUpdater (notes, poids, compteurs, intervalles)
  Mastery/        MasteryCalculator, statistiques d'erreurs, progression
  Planning/       LessonSelector (leçon suivante, prérequis), SessionPlanner (plans de session)
  Session/        SessionRunner (machine à états d'une session)
  Diagnostic/     test adaptatif, placement échelonné
  Dictionary/     recherche, lemmatisation, « Apprendre ce mot »
  API/            EngineAPI : façade publique (ContentIndex, LearningEngine, SessionRunner, DiagnosticSession)
  Support/        SplitMix64, stableHash, EngineTuning (constantes internes)
```

`LearningEngine` est une structure immuable : `init(bundle:configuration:)` construit l'index (`ContentIndexTables` : unités, leçons, exercices par unité, par leçon, banque de diagnostic et d'évaluation, formes fléchies du dictionnaire, mots connus, recherche) puis délègue à des composants sans état (`AnswerEvaluator`, `MemoryUpdater`, `MasteryCalculator`, `SessionPlanner`, `LessonSelector`). La façade publique reste exactement celle du contrat ; les fonctions `…Impl` sont internes.

Cycle d'une session côté application :

1. `planSession(type:slot:day:learner:now:seed:)` renvoie un `SessionPlan` (éléments : cartes de règle, cartes de mot, exercices).
2. `SessionRunner(plan:startedAt:)` propose les éléments un par un ; `submit` appelle `evaluate`, construit l'`AttemptRecord` ; l'application appelle `apply(attempt, to:&learner, now:)` ; `advance` passe à l'élément suivant (et insère éventuellement une remédiation).
3. À la fin, l'application appelle `registerCompletion(of:to:now:)` (ajout au contrat, voir §14) qui marque la leçon enseignée comme terminée et date l'évaluation périodique.

## 2. Normalisation

Toute comparaison de texte passe par `TextNormalizer` (public, réutilisable par l'app pour surligner des différences).

1. **Unicode** : NFC, minuscules (`lowercased()`, indépendant de la locale).
2. **Apostrophes** `’ ‘ ‛ ´` et accent grave → `'` ; guillemets `“ ” « » "` supprimés.
3. **Ponctuation** : `, ; :` et parenthèses → espace ; ponctuation finale `. ! ? …` supprimée ; espaces multiples réduits ; bords rognés.
4. **Contractions développées en variantes.** Chaque phrase est transformée en un **ensemble de formes canoniques** (plafonné à 32 variantes) : `he's` → `he is` **ou** `he has` ; `i'd` → `i would` **ou** `i had` ; `won't` → `will not` ; `can't`, `cannot` et `can not` → `can not` ; `don't` → `do not` ; `'ll` → `will` ; `i've` → `i have` ; `let's` → `let us`. Le génitif `'s` d'un nom n'est pas touché. Deux textes sont équivalents si **une** de leurs variantes canoniques est identique.
5. **Chiffres 0–20** → lettres (`3` = `three`).
6. **Orthographe britannique/américaine** : petite table (colour/color, favourite/favorite, centre/center, travelled/traveled, organise/organize, grey/gray, mum/mom…).
7. **Traits d'union** : comparaison secondaire sans trait d'union (`e-mail` = `email`).
8. **Niveau « indulgent »** (`lenient`) : variantes sans apostrophe (`dont` pour `don't`, `im` pour `i'm`), utilisé pour accepter l'oubli de l'apostrophe sans le signaler comme une faute grave.

Les **patterns d'erreur** (`equals`, `contains`) et les contraintes de `requirements` (`mustInclude`, `mustNotInclude`) passent par **la même** canonicalisation : un pattern `equals: "he don't"` reconnaît aussi `he do not`, et un `contains` est une **suite de mots entiers** (jamais une sous-chaîne). Une réponse correspond si une variante canonique de la réponse est égale à (ou contient) une variante canonique du pattern.

Réponses **en français** (traduction EN→FR) : mêmes étapes 1 à 3 ; `foldAccents` retire les diacritiques. Un écart d'accents seul donne `correctWithTypo` avec la remarque « Attention aux accents ».

## 3. Évaluation des réponses

### Niveau 1 — déterministe (toujours disponible, hors ligne)

`evaluate(_:submission:)` renvoie une `Evaluation` : `result` (`correct`, `correctWithTypo`, `partial`, `incorrect`, `pending`), `errorCategory`, `feedback` en français, `expectedAnswer`, `diff` par mots, `typoNote`, `wrongPairs`, `needsAIReview`.

- **QCM (`.choice`)** : égalité canonique avec `answer` ou une réponse acceptée → `correct`. Sinon `incorrect`, avec le feedback du pattern `equals` correspondant. Aucune tolérance de faute de frappe sur un choix.
- **Association (`.matches`)** : chaque paire est comparée ; toutes justes → `correct` ; au moins la moitié → `partial` ; sinon `incorrect` (catégorie vocabulaire, `wrongPairs` renseigné).
- **Remise en ordre (`.ordering`)** : les mots sont joints puis comparés aux réponses acceptées (autres ordres valides compris) → `correct` ; sinon `incorrect`, catégorie `wordOrder` et diff.
- **Texte** (phrase à compléter tapée, traduction, réponse libre), dans cet ordre :
  1. égalité canonique avec la réponse ou une réponse acceptée (un trou peut être rempli par le seul mot ou par la phrase entière) → `correct` ;
  2. pattern d'erreur (`equals` / `contains`) → `incorrect`, catégorie et feedback du pattern ;
  3. tolérance d'accents et d'apostrophes (niveau indulgent) → `correct` ou `correctWithTypo` ;
  4. `requirements` pour les réponses ouvertes (voir ci-dessous) ;
  5. mêmes mots dans un autre ordre → `incorrect`, `wordOrder` ;
  6. **alignement par mots** (programmation dynamique sur les tokens) avec la réponse acceptée la plus proche. Pour chaque mot substitué :
     - **variante grammaticale** : les deux mots sont des formes du même lemme (formes du dictionnaire ou suffixes `-s/-es/-ies/-ed/-d/-ing`) ou appartiennent à un même ensemble fermé (am/is/are/was/were/be/been ; do/does/did ; have/has/had ; a/an/the ; pronoms ; possessifs ; prépositions ; much/many ; some/any ; than/then ; this/that/these/those…). Catégorie : `conjugation` (base vs 3e personne, accord), `verbTense` (présent vs passé/participe), `preposition`, `grammar` (articles, pronoms, déterminants, quantifieurs). C'est une **erreur**, jamais une faute de frappe : *goes* au lieu de *go* → conjugaison ; *went* au lieu de *go* → temps du verbe ;
     - sinon **faute de frappe** si la distance de Damerau-Levenshtein (OSA) est ≤ 1 (mot de 5 lettres ou moins) ou ≤ 2 (mot plus long) **et** que le mot saisi est inconnu du lexique (un mot connu du lexique n'est jamais traité comme une faute de frappe) → acceptée, `correctWithTypo`, `typoNote` « Attention à l'orthographe : « recieve » → « receive ». » ;
     - sinon mot différent : `wordConfusion` si les deux mots sont au dictionnaire, `vocabulary` sinon ;
  7. mots manquants ou en trop → diff (`TokenDiff`) ; si au moins 60 % des mots attendus sont présents dans le bon ordre (plus longue sous-suite commune) et que le type est traduction ou réponse libre → `partial`, sinon `incorrect`.
- **Réponse ouverte (`requirements`)** : chaque groupe `mustInclude` doit être satisfait (un mot ou une expression entière, sur les formes canoniques), aucun `mustNotInclude`, et `minWords` doit être atteint. Alors `pending` + `needsAIReview` (l'IA vérifiera la grammaire). Sinon `incorrect`, catégorie `instruction`, avec un retour du type « Ta phrase doit contenir « went ». » ; si la réponse contient une forme proche d'un mot exigé (ex. *goes* pour *went*), le retour est un retour de grammaire ciblé.
- **Feedback générique** en français quand aucun pattern ne s'applique : « Le mot « goes » ne convient pas ici : on attend « go ». », « Il manque « to ». », « L'ordre des mots n'est pas correct. ». Les mots manquants ou en trop sont marqués `clear: false` dans le diff : ils ne suffisent pas à affirmer que la réponse est fausse (voir niveau 2).

### Niveau 2 — avis de l'IA (réseau requis, côté application)

Pour une traduction ou une réponse libre sans pattern reconnu, si l'écart n'est pas une variante grammaticale unique et clairement identifiée et que la réponse compte au moins 2 mots, le moteur ne tranche pas : `result = .pending`, `needsAIReview = true`. La réponse est peut-être une formulation correcte non listée. L'application envoie alors la phrase à l'IA ; le verdict revient dans le moteur par `resolvePendingAttempt(id:result:errorCategory:…)` qui note rétroactivement la tentative (daté à l'heure de la réponse, sauf si une autre révision a eu lieu depuis).

### Niveau 3 — repli hors ligne

Sans réseau, la tentative reste `pending` : elle est **ignorée par le planificateur de mémoire** (ni succès ni échec, aucune note FSRS) et signalée à l'écran comme « réponse à vérifier ». Elle sera notée plus tard dès que l'IA répond. Une session n'est jamais bloquée par une réponse `pending`, et aucune remédiation n'est déclenchée pour elle. L'utilisateur peut aussi corriger le verdict affiché (`SessionRunner.overrideLastEvaluation`).

### Mesure sur le contenu réel

`RealContentTests` évalue avec le moteur chacune des 2 273 réponses modèles / acceptées des 680 exercices et chacun des 784 patterns `equals` du bundle `Content/build/en.json` : toutes les réponses sont acceptées, aucun pattern d'erreur n'est accepté, toutes les références se résolvent, et les exercices à réponse ouverte refusent une phrase hors sujet. Aucune incohérence bloquante (voir `docs/reports/content-engine-consistency.md`).

## 4. Répétition espacée : FSRS-4.5 et adaptations

### Formules (implémentées dans `FSRS.swift`, validées contre des valeurs Python)

Constantes : `DECAY = -0,5`, `FACTOR = 19/81`, poids `w[0…16]` de `EngineConfiguration.fsrsWeights` (poids par défaut de FSRS-4.5).

- Rétention : `R(t, S) = (1 + FACTOR · t / S)^DECAY` (t en jours, fractionnaire).
- Intervalle : `I(S) = S / FACTOR · (r^(1/DECAY) − 1)` avec `r = desiredRetention` (0,9, donc `I = S`), borné à `[intervalle minimal, maximumIntervalDays]`.
- Première exposition : `S0(G) = w[G−1]` ; `D0(G) = w4 − (G − 3)·w5`, borné à [1, 10]. Valeurs par défaut : S0 = [0,4872 ; 1,4003 ; 3,7145 ; 13,8206], D0 = [7,6214 ; 6,3916 ; 5,1618 ; 3,932].
- Difficulté : `D' = w7·D0(3) + (1 − w7)·(D − w6·(G − 3))`, bornée à [1, 10].
- Succès : `S' = S · (e^{w8} · (11 − D) · S^{−w9} · (e^{w10·(1 − R)} − 1) · (Hard ? w15 : 1) · (Easy ? w16 : 1) + 1)`. Exemple vérifié : Good, D = 5,1618, S = 3,7145, R = 0,9 → S' = 14,0949854 ; Hard 6,0729463 ; Easy 33,5635858.
- Échec : `S'f = min(S, w11 · D^{−w12} · ((S + 1)^{w13} − 1) · e^{w14·(1 − R)})` (1,4185248 pour les valeurs ci-dessus).

### Adaptations

| Adaptation | Règle |
|---|---|
| **Note d'une tentative** | `pending` ignorée ; `incorrect` → Again ; `partial` ou indice utilisé → Hard ; `correctWithTypo` → Good (Hard avec indice) ; `correct` → Good, ou **Easy** pour une production sans indice sur une unité déjà vue un jour précédent. |
| **Remédiation** | La note d'une tentative de remédiation est plafonnée à Hard. |
| **Poids de compétence** | `S_new = S + (S'_FSRS − S) · poids` avec reconnaissance 0,5, rappel 0,8, production 1,0. Un QCM réussi espace donc moins qu'une traduction réussie. À la première exposition : `S0` interpolé entre `S0(Again)` et `S0(note)` avec le même poids. |
| **Unités secondaires** (`unitIds[1…]`) | Mises à jour seulement en cas de succès, note plafonnée à Good, et seulement si l'unité est déjà suivie ou introduite par la leçon de l'exercice (un échec ne pénalise que l'unité principale). |
| **Répétitions rapprochées** | Si la révision précédente date de moins de 10 minutes, un succès met à jour les compteurs mais pas la stabilité ; un échec s'applique normalement. |
| **Révisions anticipées** (ajout) | Un succès avant l'échéance (`now < nextReviewAt`) ne modifie que les compteurs : ni stabilité, ni difficulté, ni échéance, ni `lastReviewAt`. La stabilité grandit aux révisions **dues** (effet d'espacement). Un échec s'applique toujours. |
| **Succès différé** | `delayedSuccessCount` n'est crédité que pour un succès à une révision due, au moins `delayedSuccessHours` (20 h) après la révision précédente. Pratiquer chaque jour une unité qui n'est pas due ne « fabrique » donc pas de succès différés. |
| **Plafond de stabilité** | `S ≤ maximumIntervalDays` (180 j) : sans plafond la stabilité diverge et le score de maîtrise perd son sens. |
| **Intervalle minimal** | 4 h après un échec (revient dans une session suivante) ; 12 h après un succès. |
| **Compteurs** | `reviewCount`, `successCount`, `failureCount`, `lapseCount` (échec après au moins un succès), `noHintSuccessCount`, `delayedSuccessCount`, `productionSuccessCount`, `successfulExerciseTypes`, `recentResults` (borné à `recentResultsLimit`), `updatedAt`. |
| **Création d'un état** | À la première tentative en tant que nouvelle notion, par le placement du diagnostic (stabilité 2 j, difficulté 5, aucun succès), ou par « Apprendre ce mot » (stabilité 0,5 j, première révision dans ~4 h). |

Pourquoi les révisions anticipées ne font pas grandir la stabilité : la simulation initiale montrait qu'un apprenant qui pratique la même notion dans trois sessions par jour gardait `R ≈ 1` et une stabilité d'environ 1,9 j (les formules FSRS ne donnent presque aucun gain à `R ≈ 1`), tout en cumulant des « succès différés » faussement crédités. Limiter la croissance et le crédit différé aux révisions dues rend la maîtrise fidèle à la mémoire réelle.

## 5. Maîtrise

Score d'une unité (0…1) :

```
score = 0,35 · min(1, S / 21)            stabilité (21 jours = pleinement stable)
      + 0,20 · précision récente         part de succès parmi les `recentResults` (10 derniers)
      + 0,15 · [≥ 1 succès en production]
      + 0,15 · min(1, succès différés / 2)
      + 0,10 · min(1, types d'exercices réussis / 3)
      + 0,05 · min(1, succès sans indice / 3)
```

Niveaux (`MasteryLevel`) :

- **mastered** : `score ≥ masteredThreshold` (0,8) **et** au moins un succès en production **et** au moins un succès différé **et** `R ≥ 0,8` ;
- **fragile** : `score ≥ fragileThreshold` (0,45), ou unité éligible dont `R < 0,8` (maîtrise qui s'efface) ;
- **learning** : sinon ; **notStarted** : aucun état.

Conséquences vérifiées par les tests : un QCM réussi seul ne donne jamais « maîtrisé » (pas de production, pas de succès différé) ; une production réussie, un succès différé à une révision due, un score ≥ 0,8 et `R ≥ 0,8` suffisent ; une unité maîtrisée dont la rétention tombe sous 0,8 redevient fragile.

## 6. Pourcentages de progression

Méthode documentée (aucun chiffre n'est inventé : tout est dérivé des états de mémoire) :

- **Par catégorie** (`ProgressCategory` : vocabulaire, verbes, grammaire, construction de phrases) : `unitsTotal` = unités de la catégorie dans le contenu (hors dépréciées) ; `unitsStudied` = unités ayant un état de mémoire ; `unitsMastered` = unités au niveau `mastered` ; **`averageMastery` = moyenne des scores de maîtrise des unités étudiées** (0 si aucune). La barre « Maîtrise moyenne » d'une catégorie affiche `averageMastery` ; le compteur « étudiées / total » affiche `unitsStudied / unitsTotal`.
- **Par module** (`moduleProgress`) : `fraction` = **somme des scores de maîtrise des unités du module divisée par le nombre total d'unités du module** (une unité non commencée compte 0). Le pourcentage d'un module reflète donc à la fois la couverture et la qualité ; il ne monte à 100 % que lorsque toutes ses unités sont maîtrisées.
- **Global** (`overallProgress`) : même formule sur l'ensemble des unités du contenu, bornée à 1.
- **Mots étudiés / maîtrisés** : unités `vocabulary` suivies / au niveau `mastered`. **Règles** : unités `grammar`.
- **Taux de réussite** : succès (`correct`, `correctWithTypo`) / tentatives notées (hors `pending`), sur l'historique conservé (`attemptHistoryLimit` = 500).
- **Révisions effectuées** : tentatives sur une unité vue un jour précédent. **Révisions dues** : états dont `nextReviewAt ≤ maintenant`.
- **Leçons** : terminées + placées par le diagnostic, sur le total.
- **Lacunes** : taux d'erreur par `ErrorCategory` sur les 100 dernières tentatives notées.
- **Série (`streak`)** : jours consécutifs avec au moins une session terminée, jusqu'à aujourd'hui, ou jusqu'à hier si aujourd'hui n'a encore aucune session.

Ordre de grandeur mesuré (§12) : au bout de 30 jours à 3 sessions par jour, un apprenant moyen a étudié 110 à 140 mots dont 46 à 69 sont maîtrisés, et 16 à 20 règles dont 0 à 6 maîtrisées : la maîtrise des règles est lente par construction (production + succès différé + stabilité).

## 7. Choix de la leçon et prérequis

`nextLesson` : première leçon (ordre `sequence`) ni terminée ni placée dont les prérequis sont satisfaits. Les prérequis sont ceux de la notion de la leçon (et la notion elle-même pour une leçon de pratique) : chacun doit avoir une maîtrise ≥ `prerequisiteMasteryThreshold` (0,5) **ou** être étudié depuis au moins `prerequisiteBypassDays` (5) jours (anti-blocage).

Si le prérequis le plus faible bloque, le planificateur insère une **session de remédiation** à la place d'une nouveauté : carte de règle de rappel + exercices de l'unité en retard (type `learning`, `lessonId` nul). La remédiation ne remplace que la **première** session de la journée ; les suivantes pratiquent normalement.

Aucune nouvelle leçon n'est introduite quand les révisions en retard (échues depuis plus de 12 h) dépassent `overdueThresholdToPauseNewMaterial` (15) : le moteur ne propose que des révisions (jusqu'à 50 % d'anciennes) jusqu'à résorption.

## 8. Planification des sessions

Une session compte **8 à 12 exercices** (`minInteractions`…`maxInteractions`), plus des cartes. Le nombre d'exercices vise `targetSessionSeconds` (300 s) d'après `estimatedSeconds` (QCM 15 s, association 25 s, trou 20 s, remise en ordre 25 s, traduction 35 s, réponse libre 40 s, carte de règle 45 s, carte de mot 12 s) ; on dépasse plutôt que de descendre sous 8.

### Type effectif

La première session terminée de la journée enseigne la leçon du jour, quel que soit le créneau : si le matin est manqué, l'après-midi enseigne. Sinon le créneau impose : matin = apprentissage, après-midi = application, soir = consolidation. `extra` (révision libre) ne contient jamais de nouveauté ; `diagnostic` et `assessment` ont leurs propres planificateurs.

### Contenu de chaque type

- **Apprentissage** : échauffement (1–2 révisions anciennes dues, `R` la plus basse) → carte de règle (si la leçon introduit une notion, ou rappel si la notion est faible) → cartes de mots (nouveau vocabulaire) → exercices de la leçon du plus guidé (association, QCM) au plus exigeant (traduction, réponse libre), les premiers marqués `newMaterial` → 1–2 rappels actifs (production sur une notion antérieure).
- **Application** : notions vues aujourd'hui (sinon les plus récentes) dans des **types d'exercices pas encore utilisés aujourd'hui** (rappel, production), plus révisions récentes (3 derniers jours) et anciennes.
- **Consolidation** : notions du jour **sans indice** (`hintAllowed = false`, saisie libre), révisions anciennes dues, notions fragiles. Le soir exclut les exercices que l'après-midi proposerait à partir du même instant, pour que les deux sessions soient indépendantes et différentes.
- **Évaluation périodique** : tous les `assessmentIntervalDays` (14) jours ; `assessmentQuestionCount` (12) questions tirées du pool `assessment` des modules étudiés puis d'exercices de leçon jamais vus des unités étudiées (production de préférence), sans indice, rôle `assessment`, sans remédiation.
- **Pratique ciblée** (`planFocusedPractice`) : carte de règle + 6 à 8 exercices d'une unité, du plus guidé au plus exigeant.

### Répartition (sur N exercices)

| Groupe | Application | Consolidation | Libre |
|---|---|---|---|
| Pratique du jour | 40 % | 40 % | 30 % |
| Révisions récentes | 20 % | 0 % (remplacé par les fragiles) | 20 % |
| Révisions anciennes | 20 % | 20 % | 50 % |
| Notions fragiles | — | 20 % | — |
| Rappel actif (production) | 20 % | 20 % | — |

Les sessions d'apprentissage suivent la répartition du contrat (20 % révisions anciennes, 20 % notions récentes, 40 % pratique, 20 % rappel actif) avec la structure décrite plus haut ; le tableau donne les pondérations de `planDaily`. En cas d'inondation de retards, les révisions anciennes montent à 50 % et les autres parts sont réduites proportionnellement. Les parts sont converties en effectifs par la méthode du plus grand reste ; un groupe vide est complété par les autres, d'abord avec des exercices jamais faits aujourd'hui, puis, **en dernier recours**, avec un exercice déjà fait.

### Choix d'un exercice (`pickExercise`)

Pour chaque unité, parmi les exercices des leçons terminées, un score départage : proximité de la compétence visée, exercice dont l'unité principale est celle visée, **alternance des types** (pénalité si même type que le précédent ou déjà utilisé aujourd'hui pour cette unité, cf. QCM → trou → traduction → production), pénalité pour les exercices vus dans les 3 derniers jours, bonus si l'exercice travaille aussi d'autres unités dues, écart de difficulté à la cible `1 + 3 · maîtrise`, pénalité si l'unité principale revient déjà dans la session, puis un bruit de 0,3 tiré du générateur seedé.

### Règles de variété

Jamais deux fois le même exercice dans une session ; jamais deux fois le même exercice dans la journée tant qu'une alternative existe ; éviter les exercices vus dans les 3 derniers jours s'il existe une alternative ; alterner les types pour une même unité.

## 9. Adaptation

- **Présentation par unité** (maîtrise adaptée) : < 0,3 → `choices` (banque de mots) et indice permis ; 0,3–0,6 → `typed` avec indice ; > 0,6 → `typed` sans indice, production privilégiée.
- **Réussite récente** (30 dernières tentatives notées, au moins 8) : > 85 % → types et difficultés plus élevés, davantage de production ; < 60 % → exercices plus guidés et moins de nouveaux mots.
- **Lacunes** : taux d'erreur par catégorie sur les 100 dernières tentatives ; une catégorie est faible à partir de 3 erreurs et 10 % des tentatives ; les unités liées à une catégorie faible deviennent prioritaires dans les révisions.
- **Remédiation en séance** : après une réponse `incorrect` ou `partial` (hors évaluation et diagnostic, jamais pour `pending`), `SessionRunner.advance` ajoute en fin de session un exercice **similaire** (même unité principale, autre exercice, plus guidé, indice permis) ; à défaut, le même exercice est reproposé une fois. Au plus `maxRemediationsPerSession` (3) remédiations par session. Une erreur ne bloque jamais la fin d'une session (100 % de réussite non exigé).
- **Reprise sur incident** : une session interrompue se sérialise (`SessionRunner` est `Codable`) et reprend au même élément.

## 10. Diagnostic et placement

**Départ** selon l'auto-évaluation : `beginner` → niveau 0, `someBasics` → 1, `understandsSentences` → 2, `intermediate` → 3.

**Escalier** : deux bonnes réponses consécutives à un niveau → niveau + 1 ; une erreur → niveau − 1 (bornes 0…4). Les questions sont variées par `topic` et ne se répètent pas. Arrêt à `diagnosticMaxQuestions` (20), ou dès `diagnosticMinQuestions` (15) si le niveau est stable (les 4 dernières réponses posées à au plus un niveau d'écart) ou si la banque est épuisée. **Niveau estimé** : plus haut niveau ayant au moins 60 % de réussite sur au moins 2 questions posées à ce niveau.

**Placement** : niveau 0 → début `en.l01` ; 1 → `en.l10` (module 1 placé) ; 2 → `en.l18` (modules 1–2) ; 3 → `en.l27` (1–3) ; 4 → `en.l35` (1–4) (`startLesson(forLevel:)` : première leçon du module `niveau + 1`). Les leçons précédentes sont « placées » ; leurs unités reçoivent un état `source = .diagnostic` (stabilité 2 j, difficulté 5, aucun succès, donc jamais « maîtrisées ») avec des `nextReviewAt` **étalés** : au plus 15 vérifications par jour (`placementChecksPerDay`), les unités les plus avancées d'abord. Ainsi un utilisateur placé haut n'est pas submergé de révisions le lendemain. Libellés (jamais de niveau CECRL certifié) : 0 « Débutant », 1 « Premières bases », 2 « Bases acquises », 3 « Élémentaire », 4 « Pré-intermédiaire ».

Mesuré sur la banque réelle (40 questions : niveaux 0×5, 1×10, 2×5, 3×10, 4×10) avec des apprenants virtuels de capacité 0 à 4 et chacune des quatre auto-évaluations de départ : le test dure toujours 15 à 20 questions, sans jamais poser deux fois la même, le niveau estimé est à au plus un niveau de la capacité réelle, et il est exact quand l'auto-évaluation de départ correspond. Au niveau 4, le placement concerne 34 leçons et plus de 150 unités, vérifiées à raison d'au plus 15 par jour.

## 11. Dictionnaire

- `lookup` : mot normalisé → entrée directe, formes fléchies (`forms` : 3e personne, passé, participe, -ing, pluriel, comparatif, superlatif), contraction (`doesn't` a sa propre fiche), génitif `'s` retiré, puis lemmatisation heuristique (`-s`, `-es`, `-ies → y`, `-ed`, `-d`, `-ing` avec doublement de consonne et `e` muet).
- `searchDictionary` : préfixe du mot, puis contenu, puis traduction française (sans accents).
- `trackWord` (« Apprendre ce mot ») : crée l'état (source `.dictionary`, stabilité 0,5 j, révision dans ~4 h) sans jamais le considérer maîtrisé.

## 12. Calibrage et résultats

### Simulation sur 30 jours (contenu réel)

Trois apprenants virtuels à 3 sessions par jour. Leur connaissance latente de chaque unité croît avec la pratique et s'efface avec le temps (constante d'oubli 20 j) ; la probabilité de réussite est `base + gain · connaissance` (plafonnée à 0,97). Résultats avec la configuration par défaut :

| Apprenant (base / gain / graine) | Leçons terminées en 30 j | Séances de remédiation | Plus longue pause sans nouvelle leçon | Répétitions planifiées le même jour (après j5) | Réussite finale |
|---|---|---|---|---|---|
| bon (0,70 / 0,30 / 3) | 27 | 10 | 1 jour | 0 | 0,89 |
| moyen (0,55 / 0,42 / 7) | 23 | 14 | 2 jours | 2 | 0,87 |
| faible (0,45 / 0,40 / 11) | 21 | 15 | 3 jours | 18 | 0,76 |
| très en difficulté (0,08 / 0 / 21) | 12 | 23 | 4 jours | 42 | 0,10 |

Toutes les sessions comptent 8 à 12 exercices ; chaque jour comporte des révisions dès le jour 3 (5 à 23 exercices de révision par jour) ; 2 évaluations de consolidation ont lieu ; pour les trois apprenants, les révisions dues ne dépassent jamais 20 et les retards 13 ; un apprenant parfait progresse d'une leçon par jour.

Décisions de calibrage :

- `prerequisiteMasteryThreshold` **reste à 0,5** : avec la formule du contrat, la maîtrise d'une notion récente plafonne vers 0,5–0,6 ; une pause de 3 à 4 jours (remédiation puis levée du verrou à 5 jours) est le coût mesuré d'un prérequis non atteint. Un seuil plus bas supprimerait la remédiation sans gain pédagogique.
- Les assertions des tests de simulation sont calées sur ces mesures avec une marge : au moins 15 leçons en 30 jours, pas plus de 4 jours sans nouvelle leçon (8 pour l'apprenant en grande difficulté), au plus 25 répétitions planifiées le même jour après le jour 5, au plus 40 révisions dues, 150 exercices de révision sur la période.
- Une **séance de remédiation** n'enseigne pas de leçon : si le prérequis est ensuite satisfait, la séance suivante de la journée enseigne la leçon ; sinon la remédiation ne remplace que la première séance du jour et les suivantes pratiquent normalement.

### Constat sur le contenu

Avec 10 exercices par leçon, trois sessions de 8 à 12 exercices par jour (environ 33 exercices) épuisent le pool disponible les premiers jours, et plus longtemps pour un apprenant en difficulté (la remédiation consomme des exercices) : le moteur répète alors, en dernier recours, un exercice déjà fait. Recommandation : 20 à 30 exercices par leçon, ou davantage de variantes par notion (voir le rapport de cohérence).

## 13. Paramètres de réglage

### `EngineConfiguration` (public, valeurs par défaut)

| Paramètre | Défaut | Effet |
|---|---|---|
| `fsrsWeights` | 17 poids FSRS-4.5 | formules FSRS |
| `desiredRetention` | 0,9 | probabilité de rappel visée à l'échéance |
| `maximumIntervalDays` | 180 | plafond d'intervalle et de stabilité |
| `minInteractions` / `maxInteractions` | 8 / 12 | taille d'une session |
| `targetSessionSeconds` | 300 | durée visée |
| `estimatedSeconds` | voir §8 | durée estimée par type d'élément |
| `overdueThresholdToPauseNewMaterial` | 15 | au-dessus : aucune nouvelle leçon |
| `maxRemediationsPerSession` | 3 | plafond des remédiations en séance |
| `prerequisiteMasteryThreshold` | 0,5 | maîtrise exigée d'un prérequis |
| `prerequisiteBypassDays` | 5 | anti-blocage |
| `masteredThreshold` / `fragileThreshold` | 0,8 / 0,45 | seuils de niveau |
| `delayedSuccessHours` | 20 | écart minimal pour un succès différé |
| `recentResultsLimit` | 10 | fenêtre de la précision récente |
| `attemptHistoryLimit` | 500 | historique de tentatives conservé |
| `assessmentIntervalDays` / `assessmentQuestionCount` | 14 / 12 | évaluation périodique |
| `diagnosticMinQuestions` / `diagnosticMaxQuestions` | 15 / 20 | longueur du diagnostic |

### `EngineTuning` (constantes internes, `Support/SplitMix64.swift`)

| Constante | Valeur | Rôle |
|---|---|---|
| `performanceWindow` / `performanceMinimumAttempts` | 30 / 8 | fenêtre de réussite récente |
| `highPerformance` / `lowPerformance` | 0,85 / 0,60 | seuils d'adaptation |
| `errorWindow` | 100 | fenêtre des catégories d'erreur |
| `weakCategoryRate` / `weakCategoryMinimumErrors` | 0,10 / 3 | catégorie faible |
| `recognitionWeight` / `recallWeight` / `productionWeight` | 0,5 / 0,8 / 1,0 | poids de compétence |
| `rapidRepetitionMinutes` | 10 | répétition rapprochée |
| `minIntervalAfterFailureHours` / `…AfterSuccessHours` | 4 / 12 | intervalle minimal |
| `overdueGraceHours` | 12 | un retard compte après ce délai |
| `recentDays` | 3 | « révisions récentes » et variété |
| `retrievabilityForMastered` | 0,8 | rétention exigée pour « maîtrisé » |
| `placementStability` / `placementDifficulty` | 2 / 5 | états créés par le diagnostic |
| `placementChecksPerDay` | 15 | étalement des vérifications |
| `dictionaryStability` / `dictionaryFirstReviewHours` | 0,5 / 4 | mots appris depuis le dictionnaire |

## 14. Écarts et ajouts par rapport au contrat

Aucune déclaration publique existante n'a été renommée, retirée ou modifiée. Ajouts :

- `LearningEngine.registerCompletion(of:to:now:)` : l'application l'appelle à la fin d'une session pour marquer la leçon terminée (`completedLessonIds`) et dater l'évaluation (`lastAssessmentAt`). Sans cet appel, la leçon suivante n'est jamais proposée.
- `LearningEngine.moduleProgress` / `overallProgress` et le type `ModuleProgress` (pourcentages de progression, §6) ; `TextNormalizer` public.
- `DiagnosticSession` possède des propriétés stockées supplémentaires (`minQuestions`, `seed`, `bankExhausted`) ; son `init` public existant est inchangé.
- Comportement : révisions anticipées sans croissance de stabilité et succès différé réservé aux révisions dues (§4), plafond de stabilité à `maximumIntervalDays`.

## 15. Limites

- **Évaluation par mots, pas de compréhension.** Le niveau 1 ne comprend pas le sens : une reformulation correcte absente de `acceptedAnswers` est envoyée à l'IA (niveau 2) ou reste `pending` hors ligne. Les mots hors lexique du contenu sont traités comme des fautes de frappe ou du vocabulaire inconnu selon leur distance.
- **Anglais seulement.** Contractions, orthographe britannique/américaine et ensembles de mots fermés sont spécifiques à l'anglais ; une autre langue nécessite ses tables.
- **Les variantes de contraction sont plafonnées à 32** par phrase (suffisant pour le contenu mesuré).
- **Pool d'exercices fini.** Sans assez d'exercices, des répétitions le même jour sont possibles (dernier recours).
- **Maîtrise des règles lente.** Elle demande production, succès différé et stabilité : c'est voulu, mais les règles grammaticales n'atteignent « maîtrisé » qu'après plusieurs semaines.
- **FSRS par unité, pas par exercice.** Plusieurs exercices d'une même unité partagent un état ; les poids sont ceux par défaut de FSRS-4.5, non réentraînés sur les données de l'utilisateur.
- **Horloge.** Le moteur reçoit `now` en paramètre et utilise le calendrier courant pour la notion de « jour » ; les changements de fuseau ou d'heure d'été ne sont pas modélisés finement.
- **Pas de détection de triche** sur les indices ou les échecs répétés au-delà de la remédiation.

## 16. Lancer les tests

```bash
source /opt/swiftlang/env.sh          # chaîne Swift 6 sous Linux ; sous macOS, Xcode 16 suffit
cd Packages/LearningCore
swift build
swift test                             # 78 tests, environ 15 s

swift test --filter EvaluatorTests            # une suite
swift test --filter SimulationTests           # simulation de 30 jours
QUINZE_PRINT_SIM=1 swift test --filter SimulationTests    # affiche les courbes de la simulation
QUINZE_WRITE_REPORT=1 swift test --filter RealContentTests  # régénère docs/reports/content-engine-consistency.md
```

Suites : `NormalizerTests` (normalisation, contractions, chiffres, SplitMix64), `EvaluatorTests` (fautes de frappe vs grammaire, ordre, partiel, patterns, accents, réponses ouvertes), `SchedulingTests` (valeurs FSRS vs Python, maîtrise, unités secondaires), `PlannerTests` (8–12 exercices, carte de règle, prérequis et contournement, inondation de retards, 3 créneaux indépendants, déterminisme, pas de doublon), `SessionRunnerTests` (remédiation et plafond, complétion, aller-retour Codable, correction manuelle), `DiagnosticTests`, `DictionaryTests`, `RealContentTests` (bundle réel : réponses, patterns, références, réponses ouvertes), `SimulationTests` (30 jours).

Les tests utilisent un jeu de contenu écrit à la main (`Tests/LearningCoreTests/Fixtures/fixture-bundle.json` : 3 leçons, 6 types d'exercices, patterns, `requirements`, dictionnaire avec formes, 20 questions de diagnostic de niveaux 0 à 4, questions d'évaluation) chargé par `Bundle.module`, et, quand `Content/build/en.json` existe, le contenu réel (les tests concernés sont ignorés sinon).
