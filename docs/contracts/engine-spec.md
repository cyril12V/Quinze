# Spécification du moteur pédagogique (LearningCore)

Package Swift `Packages/LearningCore`, Foundation uniquement (compile sur iOS 17+, macOS 14+ et Linux). Indépendant de l'interface (§21). Le contrat public est **figé** dans :
- `Sources/LearningPrimitives/Primitives.swift` (types partagés avec les extensions),
- `Sources/LearningCore/Content/ContentModels.swift` (contenu),
- `Sources/LearningCore/Learner/LearnerModels.swift` (état de l'apprenant),
- `Sources/LearningCore/API/EngineAPI.swift` (façade : `ContentIndex`, `LearningEngine`, `SessionRunner`, `DiagnosticSession`).

On peut ajouter des types et fonctions internes, des fichiers, des membres publics supplémentaires, mais **pas renommer ni changer** une signature publique existante. Le format JSON du bundle est produit par `tools/build_content.py` (voir aussi `Content/SCHEMA.md`).

## 1. Normalisation et évaluation déterministe (niveau 1)

### Normalisation (anglais)
1. NFC, minuscules (indépendantes de la locale).
2. Apostrophes `’ ‘ ‛ ´ \`` → `'` ; guillemets `“ ” « » "` supprimés.
3. `, ; :` et parenthèses → espace ; ponctuation finale `. ! ? …` supprimée ; espaces multiples réduits ; trim.
4. Contractions développées **en variantes** (ensemble de formes canoniques) : `i'm→i am`, `you're/we're/they're→… are`, `he's/she's/it's/that's/what's/there's/here's/who's/where's/how's → … is` **ou** `… has`, `let's→let us`, `isn't, aren't, wasn't, weren't, don't, doesn't, didn't, haven't, hasn't, hadn't, wouldn't, couldn't, shouldn't, mustn't, needn't → … not`, `won't→will not`, `can't / cannot → can not`, `i've/you've/we've/they've → … have`, `'ll → will`, `i'd/you'd/he'd/she'd/we'd/they'd → … would` **ou** `… had`. Le génitif `'s` d'un nom n'est pas touché.
5. Nombres en chiffres 0–20 → en lettres.
6. Équivalences d'orthographe britannique/américaine (petite table : colour/color, favourite/favorite, centre/center, theatre/theater, travelled/traveled, travelling/traveling, organise/organize, realise/realize, grey/gray, mum/mom, cancelled/canceled…).
7. Comparaison secondaire sans traits d'union (`e-mail` = `email`).

Réponses en **français** (traduction EN→FR) : mêmes étapes 1–3 ; les écarts d'accents seuls donnent `correctWithTypo` avec la remarque « Attention aux accents ».

### Algorithme `evaluate(_:submission:)`
- **mcq / choix (`.choice`)** : égalité normalisée avec `answer` ou un `acceptedAnswers` → `correct`, sinon `incorrect` + feedback du pattern `equals` correspondant s'il existe.
- **match** : chaque paire comparée (normalisée) ; toutes justes → `correct` ; au moins la moitié → `partial` ; sinon `incorrect`. `wrongPairs` renseigné, catégorie `vocabulary`.
- **reorder** : tokens joints puis comparés aux réponses acceptées → `correct`, sinon `incorrect` catégorie `wordOrder` + diff.
- **Texte (fill_blank tapé, translation, free_answer)** :
  1. Égalité d'une forme canonique de la réponse avec une forme canonique d'une réponse acceptée → `correct`.
  2. Pattern d'erreur (`equals` sur la réponse normalisée, `contains` = suite de mots entiers) → `incorrect`, catégorie et feedback du pattern.
  3. Alignement par mots (distance d'édition sur les tokens) avec la réponse acceptée la plus proche. Pour chaque paire substituée :
     - **variante grammaticale** si les deux mots sont des formes du même lemme (via les `forms` du dictionnaire ou les suffixes `-s/-es/-ies/-ed/-d/-ing`), ou appartiennent à un même ensemble fermé (am/is/are/was/were/be/been ; do/does/did ; have/has/had ; a/an/the ; pronoms ; possessifs ; prépositions ; much/many ; some/any ; than/then ; this/that/these/those…) → erreur, catégorie : `conjugation` (base vs 3e personne, accord), `verbTense` (présent vs passé/participe), `preposition`, `grammar` (articles, pronoms, déterminants, quantifieurs) ;
     - sinon **faute de frappe** si distance de Damerau-Levenshtein ≤ 1 (mot ≤ 5 lettres) ou ≤ 2 (mot plus long) → acceptée ;
     - sinon mot différent : `wordConfusion` si les deux mots sont dans le dictionnaire, `vocabulary` sinon.
     Si toutes les différences sont des fautes de frappe → `correctWithTypo` (+ `typoNote` : « Attention à l'orthographe : « recieve » → « receive ». »).
  4. Mêmes mots dans un autre ordre → `incorrect`, `wordOrder`.
  5. Mots manquants / en trop / faux → diff (`TokenDiff`) ; si ≥ 60 % des mots attendus sont présents dans le bon ordre (LCS) et que le type est `translation`/`free_answer` → `partial`, sinon `incorrect`.
  6. **Incertitude** : pour `translation`/`free_answer` sans pattern reconnu, si l'erreur n'est pas une variante grammaticale unique clairement identifiée et que la réponse compte au moins 2 mots → `result = .pending`, `needsAIReview = true` (la réponse est peut-être une formulation correcte non listée). L'app demande alors l'avis de l'IA (niveau 2) ; hors ligne, la tentative reste `pending` et sera notée plus tard (niveau 3 : signalée comme incertaine à l'écran).
  7. **free_answer ouvert** (`requirements`) : si chaque groupe `mustInclude` est satisfait (mot ou expression entière, sur les formes canoniques), aucun `mustNotInclude`, et `minWords` atteint → `pending` + `needsAIReview` (l'IA vérifie la grammaire) ; sinon `incorrect` avec un feedback du type « Ta phrase doit contenir « went ». ».
- Feedback générique (en français) quand aucun pattern ne s'applique, construit à partir du diff et de la catégorie : « Le mot « goes » ne convient pas ici : on attend « go ». », « Il manque « to ». », « L'ordre des mots n'est pas correct. ».
- `expectedAnswer` = `answer` (ou la réponse acceptée la plus proche si elle est plus parlante).

## 2. Répétition espacée : FSRS-4.5 adapté

Constantes : `DECAY = -0.5`, `FACTOR = 19/81`, poids `w[0...16]` = `EngineConfiguration.fsrsWeights`.
- Rétention : `R(t, S) = (1 + FACTOR · t / S)^DECAY` (t en jours, fractionnaire).
- Intervalle : `I(S) = S / FACTOR · (r^(1/DECAY) − 1)` avec `r = desiredRetention` (= S quand r = 0,9), borné à `[minInterval, maximumIntervalDays]`.
- Première exposition : `S0(G) = w[G−1]`, `D0(G) = w4 − (G − 3)·w5`, borné à [1, 10].
- Difficulté : `D' = w7·D0(3) + (1 − w7)·(D − w6·(G − 3))`, borné à [1, 10].
- Succès : `S' = S · (e^{w8} · (11 − D) · S^{−w9} · (e^{w10·(1 − R)} − 1) · (G = 2 ? w15 : 1) · (G = 4 ? w16 : 1) + 1)`.
- Échec : `S'f = min(S, w11 · D^{−w12} · ((S + 1)^{w13} − 1) · e^{w14·(1 − R)})`.

Adaptations (à documenter dans `docs/05-moteur-pedagogique.md`) :
- **Note** d'une tentative : `pending` → ignorée ; `incorrect` → Again ; `partial` ou indice utilisé → Hard ; `correctWithTypo` → Good ; `correct` → Good, ou Easy pour une production sans indice sur une unité déjà vue un jour précédent. Une tentative de remédiation est plafonnée à Hard.
- **Poids de compétence** : l'augmentation de stabilité est pondérée par la compétence de l'exercice (reconnaissance 0,5 ; rappel 0,8 ; production 1,0) : `S_new = S + (S'_FSRS − S) · poids`. Un QCM réussi espace donc moins qu'une traduction réussie.
- **Répétitions rapprochées** : si la révision précédente date de moins de 10 minutes, un succès met à jour les compteurs mais pas la stabilité ; un échec s'applique normalement.
- **Intervalle minimal** : 4 h après un échec (révision dans une session suivante), 12 h sinon.
- **Unités secondaires** (`unitIds[1...]`) : mises à jour seulement en cas de succès (note plafonnée à Good) et seulement si l'unité est déjà suivie.
- Compteurs (§12.2) : `reviewCount`, `successCount`, `failureCount`, `lapseCount` (échec après au moins un succès), `noHintSuccessCount`, `delayedSuccessCount` (succès ≥ `delayedSuccessHours` après la révision précédente), `productionSuccessCount`, `successfulExerciseTypes`, `recentResults` (borné), `updatedAt`.
- Une unité devient suivie (état créé) à sa première tentative en tant que nouvelle notion, via le placement du diagnostic, ou via « Apprendre ce mot ».

## 3. Maîtrise (§12.5)

`score = 0,35·min(1, S/21) + 0,20·précision récente + 0,15·[≥ 1 succès en production] + 0,15·min(1, succès différés / 2) + 0,10·min(1, types d'exercices réussis / 3) + 0,05·min(1, succès sans indice / 3)`

- `mastered` : score ≥ `masteredThreshold` **et** au moins un succès en production **et** au moins un succès différé **et** R ≥ 0,8.
- `fragile` : score ≥ `fragileThreshold`, ou unité maîtrisée dont R < 0,8.
- `learning` : sinon ; `notStarted` : aucun état.
Un QCM réussi seul ne peut donc jamais donner « maîtrisé ». Calibre les seuils avec la simulation (§7) et documente les valeurs finales.

## 4. Choix de la leçon et prérequis (§7.2, §13.3)

`nextLesson` : première leçon (ordre `sequence`) ni terminée ni placée, dont les prérequis sont satisfaits : chaque prérequis de la notion de la leçon (et la notion elle-même pour une leçon de pratique) a une maîtrise ≥ `prerequisiteMasteryThreshold`, **ou** est étudiée depuis au moins `prerequisiteBypassDays` jours (anti-blocage). Si le prérequis le plus faible bloque, le planificateur insère sa remédiation (carte de règle de rappel + exercices) au lieu d'une nouveauté.

## 5. Planification des sessions (§5)

Session = 8 à 12 exercices (`minInteractions`…`maxInteractions`) + cartes ; durée estimée par `estimatedSeconds`, cible `targetSessionSeconds` (on dépasse plutôt que de descendre sous 8 exercices). Déterministe pour une graine (générateur SplitMix64).

**Type effectif.** La première session complétée d'une journée introduit la leçon du jour, quel que soit le créneau (si l'utilisateur a manqué le matin, l'après-midi enseigne). Sinon le créneau impose : matin = apprentissage, après-midi = application, soir = consolidation. `extra` = révisions et pratique, jamais de nouveauté.

**Apprentissage.** Échauffement (1–2 révisions anciennes dues, R la plus basse) → carte de règle (si la leçon introduit une notion, ou rappel si la notion est faible) → cartes mots (nouveau vocabulaire) → exercices de la leçon du plus guidé au plus exigeant → 1–2 rappels actifs (production sur une notion antérieure).
**Application.** Notions vues aujourd'hui (sinon les plus récentes) dans des **types d'exercices pas encore utilisés aujourd'hui** (rappel, production), + révisions récentes (3 derniers jours), + 2 anciennes.
**Consolidation.** Notions du jour **sans indice** (`hintAllowed = false`, saisie libre), + révisions anciennes dues, + notions fragiles.

**Répartition** (§5.2) sur N exercices : 20 % révisions anciennes, 20 % notions récentes, 40 % pratique, 20 % rappel actif ; un groupe vide est complété par les autres. Si les révisions en retard dépassent `overdueThresholdToPauseNewMaterial` : aucune nouveauté, jusqu'à 50 % de révisions anciennes.

**Adaptation** (§13) :
- présentation par unité : maîtrise < 0,3 → `choices` (banque de mots) et indice permis ; 0,3–0,6 → `typed` avec indice ; > 0,6 → `typed`, sans indice, production privilégiée ;
- réussite récente (30 dernières tentatives) > 85 % → types et difficultés plus élevés ; < 60 % → exercices plus guidés et moins de nouveaux mots ;
- **lacunes** : taux d'erreur par `ErrorCategory` sur les 100 dernières tentatives ; les unités liées aux catégories faibles sont prioritaires dans les révisions (§13.2).
**Variété** (§27-3) : jamais le même exercice deux fois dans une session ni dans la même journée ; éviter ceux vus dans les 3 derniers jours s'il existe une alternative ; pour une même unité, alterner les types (QCM → trou → traduction → production, cf. §12.4).

**Évaluation périodique** (§15.3) : `assessmentQuestionCount` questions, tirées du pool `assessment` des modules étudiés puis d'exercices de leçon jamais vus des unités étudiées (production de préférence), sans indice, rôle `assessment`, pas de remédiation. Due tous les `assessmentIntervalDays` jours.
**Pratique ciblée** (`planFocusedPractice`) : carte de règle + 6–8 exercices de l'unité, du plus guidé au plus exigeant.

## 6. SessionRunner

Voir le contrat. Après une réponse `incorrect` ou `partial` (hors évaluation/diagnostic), `advance` ajoute en fin de session un exercice **similaire** (même unité principale, autre exercice, présentation plus guidée, indice permis) — au plus `maxRemediationsPerSession` ; à défaut, le même exercice est reproposé une fois. La session est complète quand tous les éléments ont été traités : une erreur ne bloque pas la fin (§6.5, « 100 % de réussite non exigé »). `summary` : unités travaillées, nouveautés, révisions (rôles oldReview/recentReview), tentatives, réussites, erreurs importantes (≤ 5), durée, score (évaluation).

## 7. Diagnostic (§4 étape 5)

Départ : `beginner → 0`, `someBasics → 1`, `understandsSentences → 2`, `intermediate → 3`. Escalier : 2 bonnes réponses consécutives à un niveau → niveau + 1 ; une erreur → niveau − 1 (bornes 0…4). Arrêt à `diagnosticMaxQuestions`, ou dès `diagnosticMinQuestions` si le niveau est stable sur les 4 dernières réponses ou si la banque est épuisée. Questions variées par `topic`. Niveau estimé = plus haut niveau avec ≥ 60 % de réussite sur au moins 2 questions posées à ce niveau.

Placement : niveau 0 → début `en.l01` ; 1 → `en.l10` (module 1 placé) ; 2 → `en.l18` (modules 1–2) ; 3 → `en.l27` (1–3) ; 4 → `en.l35` (1–4). Les unités introduites par les leçons placées reçoivent un état `source = .diagnostic` (stabilité 2 j, difficulté 5, aucun succès) avec des `nextReviewAt` **étalés** pour ne pas dépasser ~15 vérifications par jour. Libellés (jamais de CECRL certifié) : 0 « Débutant », 1 « Premières bases », 2 « Bases acquises », 3 « Élémentaire », 4 « Pré-intermédiaire ».

## 8. Progression (§15)

- Mots étudiés / maîtrisés : unités `vocabulary` (+ verbes du vocabulaire) suivies / au niveau `mastered`. Règles : unités `grammar`.
- Taux de réussite : succès / tentatives notées (hors `pending`).
- Révisions effectuées : tentatives sur des unités vues un jour précédent.
- Par catégorie (`ProgressCategory`) : `averageMastery` = moyenne des scores de maîtrise des unités **étudiées** de la catégorie ; `unitsTotal` = toutes les unités de la catégorie dans le contenu.
- Série (`streak`) : jours consécutifs avec au moins une session terminée, jusqu'à aujourd'hui, ou jusqu'à hier si aujourd'hui n'a encore aucune session.

## 9. Dictionnaire

`lookup` : mot normalisé → entrée directe, formes fléchies (`dictionaryByForm`), contraction (`doesn't` a sa propre fiche), génitif `'s` retiré, puis heuristiques de lemmatisation (`-s`, `-es`, `-ies→y`, `-ed`, `-d`, `-ing` avec doublement de consonne et `e` muet). `searchDictionary` : préfixe sur le mot, puis contenu, puis traduction française (sans accents). `trackWord` : crée l'état (source `.dictionary`, stabilité 0,5 j, révision dans ~4 h) sans jamais le considérer maîtrisé.
