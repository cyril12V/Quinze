# Format du contenu pédagogique (v1)

Le contenu d'une langue vit dans `Content/<code>/` :

```
Content/en/
  curriculum.json            # plan : modules, notions, leçons, vocabulaire (généré par tools/curriculum_source.py)
  source/
    m01/ … m08/
      units.json             # règles détaillées des notions de grammaire du module
      dictionary.json        # fiches dictionnaire (vocabulaire + mots-outils du module)
      lessons/l01.json …     # exercices d'une leçon
      diagnostic.json        # questions du test de positionnement
      assessment.json        # questions réservées aux évaluations périodiques (jamais en leçon)
```

`tools/build_content.py` fusionne tout en un seul fichier `Content/build/en.json` (format `ContentBundle`, lu par le moteur Swift), le copie dans l'app et génère le seed SQL Supabase. Toute la validation est faite par ce script : un contenu invalide ne part pas en production.

Conventions générales :
- JSON UTF-8, clés en camelCase.
- Apostrophe droite `'` partout (le moteur normalise de toute façon `’` → `'`).
- Les explications sont **en français**, simples, courtes, sans jargon inutile, tutoiement.
- Les phrases d'exemple utilisent surtout le vocabulaire déjà introduit (voir `curriculum.json`), des prénoms simples (Tom, Anna, Sam, Lucy, Ben, Emma) et des lieux connus (London, Paris).
- Champ `text` = langue étudiée, `translation` = français.

## Identifiants

| Objet | Format | Exemple |
|---|---|---|
| Notion de grammaire | `en.gNN.slug` | `en.g15.present_simple_negative` |
| Mot / expression | `en.v.slug` | `en.v.take_a_shower` |
| Fiche dictionnaire | `en.d.slug` | `en.d.take_a_shower`, `en.d.doesnt` |
| Leçon | `en.lNN` | `en.l20` |
| Exercice de leçon | `en.lNN.eKK` | `en.l20.e07` |
| Diagnostic | `en.diag.mNN.KK` | `en.diag.m03.02` |
| Évaluation | `en.assess.mNN.KK` | `en.assess.m03.05` |

`slug` = minuscules, apostrophes supprimées, tout caractère non alphanumérique remplacé par `_` (`can't` → `cant`, `I` → `i`, `living room` → `living_room`).

Les identifiants sont **stables** : une fois publiés, on ne les renomme pas (la progression des utilisateurs y est rattachée). Un contenu retiré est marqué `"deprecated": true`.

## units.json

Tableau d'objets complétant les notions de grammaire du module déclarées dans `curriculum.json` :

```json
[{
  "id": "en.g15.present_simple_negative",
  "rule": {
    "summary": "Pour dire qu'on ne fait pas quelque chose au présent simple, on utilise don't ou doesn't + verbe de base.",
    "explanation": "2 à 6 phrases simples qui expliquent la règle.",
    "pattern": "Sujet + don't / doesn't + verbe de base",
    "examples": [{"text": "I don't eat meat.", "translation": "Je ne mange pas de viande."}],
    "commonErrors": [{"wrong": "She doesn't eats meat.", "right": "She doesn't eat meat.", "why": "Le -s est déjà dans does."}],
    "tip": "Une astuce courte pour retenir."
  }
}]
```
- `examples` : 3 à 4. `commonErrors` : 2 à 3.

## dictionary.json

Une fiche par mot de vocabulaire du module **et** par mot-outil (`functionWords`) des notions du module.

```json
{
  "id": "en.d.drink",
  "word": "drink",
  "translation": "boire",
  "otherTranslations": ["une boisson (nom)"],
  "partOfSpeech": "verb",
  "ipa": "/drɪŋk/",
  "explanation": "Une phrase simple sur le sens et l'usage.",
  "examples": [{"text": "I drink water every day.", "translation": "Je bois de l'eau tous les jours."}],
  "confusions": [{"word": "drunk", "note": "participe passé de drink (bu) ; aussi « ivre »."}],
  "forms": {"thirdPerson": "drinks", "past": "drank", "pastParticiple": "drunk", "ing": "drinking"},
  "unitId": "en.v.drink"
}
```
- `partOfSpeech` ∈ `noun, verb, phrasal_verb, adjective, adverb, pronoun, article, determiner, preposition, conjunction, auxiliary, modal, interjection, expression, number`.
- `ipa` : prononciation britannique standard entre `/ /`.
- `examples` : 2 (contextes différents). `confusions` : 0 à 3, seulement si utiles.
- `forms` : verbes → `thirdPerson`, `past`, `pastParticiple`, `ing` ; noms → `plural` ; adjectifs courts → `comparative`, `superlative`. Sert aussi à retrouver la fiche quand on touche une forme fléchie (`went` → `go`).
- `unitId` : l'unité de vocabulaire (`en.v.…`) ; `null` pour un mot-outil.

## lessons/lNN.json

```json
{
  "lessonId": "en.l20",
  "exercises": [ { …exercice… } ]
}
```

**Exactement 10 exercices par leçon**, répartis ainsi : 2 `mcq`, 2 `fill_blank`, 2 `translation`, 1 `reorder`, 1 `match`, 2 `free_answer`. Chaque mot de vocabulaire de la leçon apparaît dans au moins un exercice ; la notion de grammaire de la leçon est l'unité principale d'au moins 6 exercices. Varier les contextes : jamais deux fois la même phrase.

### Champs communs

| Champ | Requis | Description |
|---|---|---|
| `id` | oui | voir identifiants |
| `unitIds` | oui | unités travaillées ; **la première est l'unité principale** |
| `type` | oui | `mcq`, `fill_blank`, `translation`, `reorder`, `match`, `free_answer` |
| `difficulty` | oui | 1 à 5 |
| `instruction` | oui | consigne en français (« Choisis la bonne forme. ») |
| `prompt` | oui | la question affichée |
| `promptLanguage` | oui | `en` ou `fr` (langue du `prompt`) |
| `context` | non | court texte en anglais affiché au-dessus de la question (compréhension) |
| `answer` | oui | réponse de référence affichée en correction |
| `acceptedAnswers` | oui | toutes les réponses acceptées (inclut `answer`) |
| `hint` | non | indice affichable avant de répondre |
| `explanation` | oui | **pourquoi** la bonne réponse est correcte, quelle règle s'applique (1 à 3 phrases) |
| `tip` | oui | comment éviter l'erreur (1 phrase) |
| `extraExample` | oui* | `{text, translation}` : la règle dans un autre contexte (*facultatif pour `match`) |
| `errorPatterns` | non | erreurs prévisibles avec retour ciblé (voir plus bas) |

### Par type

- **mcq** : `options` (3 ou 4, dont la bonne). `answer` = texte exact de la bonne option. Le `prompt` peut contenir `___` ou être une question.
- **fill_blank** : le `prompt` contient **exactement un** `___`. `answer` = ce qui remplit le trou (un ou plusieurs mots). `options` (banque de mots, 3 ou 4 dont la bonne) **fortement recommandées** : le moteur les montre aux débutants et les retire quand la notion est mieux maîtrisée. `acceptedAnswers` = variantes du trou uniquement.
- **translation** : `promptLanguage: "fr"` → l'utilisateur écrit en anglais (cas normal). `promptLanguage: "en"` → il écrit en français (**au plus une fois par leçon**). Lister **toutes** les traductions correctes raisonnables.
- **reorder** : `tokens` = les mots de `answer`, sans ponctuation finale, majuscules conservées, dans un ordre mélangé. `answer` = la phrase correcte. `acceptedAnswers` = `answer` + les autres ordres corrects réalisables avec les mêmes tokens.
- **match** : `pairs` = 3 à 5 objets `{"left": "anglais", "right": "français"}`. `answer` = texte d'affichage (`"always = toujours ; never = jamais"`), `acceptedAnswers: []`.
- **free_answer** : réponse écrite sans aucune proposition. Deux modes :
  - *attendu* (par défaut) : `prompt` du type « Comment dit-on : « J'ai compris » ? », `acceptedAnswers` exhaustif ;
  - *ouvert* : production libre (« Écris une phrase au passé avec go. ») avec `requirements` : `{"mustInclude": [["went"]], "minWords": 3}` (chaque sous-liste = alternatives, toutes les sous-listes doivent être satisfaites). `answer` = un exemple de bonne réponse, `acceptedAnswers` = quelques exemples. **Au plus un free_answer ouvert par leçon, et seulement à partir du module 3.**

### Réponses acceptées : ce que le moteur gère déjà

Inutile de dupliquer ces variantes, le moteur les traite :
- majuscules, espaces multiples, ponctuation finale, virgules ;
- apostrophes `’` / `'` ;
- contractions ↔ formes longues (`doesn't` = `does not`, `I'm` = `I am`, `can't` = `cannot` = `can not`, `won't` = `will not`, `'ll`, `'ve`, `'re`, `'d`…) ;
- chiffres ↔ lettres de 0 à 20 ;
- fautes de frappe légères (signalées mais acceptées), distinguées des erreurs grammaticales.

À **lister explicitement** : synonymes, ordres de mots alternatifs, mots facultatifs (« I work every day » / « I work each day »), articles alternatifs, variantes britanniques/américaines (`colour`/`color`, `holiday`/`vacation`).

### errorPatterns

```json
"errorPatterns": [
  {"equals": "goes", "category": "conjugation", "feedback": "Après doesn't, le verbe reste à la forme de base : pas de -s."},
  {"contains": "doesn't goes", "category": "conjugation", "feedback": "…"}
]
```
- `equals` : la réponse normalisée complète est égale à cette valeur.
- `contains` : la réponse normalisée contient cette suite de mots.
- `category` ∈ `vocabulary`, `grammar`, `conjugation`, `verb_tense`, `word_order`, `spelling`, `preposition`, `word_confusion`, `instruction`.
- `feedback` : explication ciblée en français (1 à 2 phrases).

Prévoir 1 à 3 patterns pour les `mcq`, `fill_blank`, `translation` et `free_answer` : les mauvaises options d'un QCM, les confusions classiques des francophones.

## diagnostic.json

5 questions par module, au format exercice, avec en plus :
- `level` : niveau de difficulté du diagnostic (M1 → 0 ; M2, M6 → 1 ; M3 → 2 ; M4, M5 → 3 ; M7, M8 → 4) ;
- `topic` ∈ `vocabulary, pronouns, verbs, present, past, future, comprehension, construction`.

Types autorisés : `mcq`, `fill_blank` (avec `options`), `reorder` ; au plus une `translation` par module. Les questions doivent être rapides (10 à 20 s).

## assessment.json

5 questions par module réservées aux évaluations périodiques (tous les 14 jours). Mêmes champs qu'un exercice, sans `lessonId`. Elles doivent être **différentes** des exercices de leçon (phrases et contextes inédits) et privilégier le rappel : au moins 3 `translation` / `free_answer` / `fill_blank` sans `options`.
