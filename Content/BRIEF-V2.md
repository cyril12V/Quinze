# Rédiger un module « format 2 » (anglais avancé, arabe, culture G)

Lis d'abord `Content/SCHEMA.md` : le format des fichiers (`units.json`, `dictionary.json`, `lessons/lNN.json`) et les champs des exercices restent les mêmes. Ce document décrit seulement ce qui change pour les nouveaux modules, et les conventions de chaque matière.

L'apprenant est un adulte francophone motivé qui veut progresser vite (« devenir un monstre »). Il fait trois sessions par jour de 5 minutes par matière, et le moteur fait revenir chaque notion et chaque mot en révision espacée. Tout est en français (consignes, explications), avec le tutoiement.

## 1. Fichiers d'un module

```
Content/<lang>/source/mNN/
  outline.json        # plan du module : notions, leçons, vocabulaire (nouveau)
  units.json          # une règle (« fiche ») par notion du module, format SCHEMA.md
  dictionary.json     # une fiche par mot de vocabulaire du module
  lessons/lSEQ.json   # SEQ = numéro de séquence de la leçon sur 2 chiffres minimum (l61.json, l105.json)
```

`diagnostic.json` et `assessment.json` sont facultatifs : ne les crée pas.

### outline.json

```json
{
  "module": {"id": 9, "title": "Titre court", "description": "Une phrase : ce que le module apprend."},
  "grammarUnits": [
    {"id": "en.g42.present_perfect_continuous", "category": "verbs", "title": "Titre de la notion",
     "difficulty": 3, "prerequisites": ["en.g40.present_perfect"], "functionWords": []}
  ],
  "lessons": [
    {"id": "en.l61", "sequence": 61, "title": "Titre accrocheur", "description": "Ce que la leçon apprend.",
     "difficulty": 3, "grammarUnitId": "en.g42.present_perfect_continuous", "introducesGrammar": true,
     "reviews": ["en.g40.present_perfect"],
     "vocabulary": [
       {"word": "lately", "slug": "lately", "translation": "ces derniers temps", "partOfSpeech": "adverb"}
     ]}
  ]
}
```

- **Une notion (`grammarUnits`) par leçon**, introduite par cette leçon (`introducesGrammar: true`). Pour la culture G, une « notion » est le sujet de la leçon (ex. « La Révolution française ») ; pour l'arabe, un groupe de lettres, un signe ou une règle de lecture.
- `category` : `grammar`, `verbs`, `sentence_building` ou `vocabulary` pour l'anglais ; `reading` (lettres, signes, lecture) ou `grammar` pour l'arabe ; `knowledge` pour la culture G.
- `prerequisites` : notions déjà vues (de ce module ou des précédents) indispensables pour aborder celle-ci. Reste raisonnable (0 à 2).
- `reviews` : notions ou mots d'avant que la leçon fait réutiliser (facultatif).
- `vocabulary` : **6 à 10 mots par leçon**. Le `slug` (ASCII minuscule, `_`) forme les identifiants `<lang>.v.<slug>` et `<lang>.d.<slug>`. Il est obligatoire pour l'arabe (translittération sans accents : `kitab`, `kanisa`). Un mot n'est introduit qu'une seule fois dans tout le module (et pas s'il existe déjà dans un module précédent : réutilise-le alors par son identifiant dans `unitIds` des exercices).
- `partOfSpeech` : valeurs de SCHEMA.md, plus `letter` et `particle` (arabe), et `concept`, `person`, `place`, `event`, `work`, `date`, `organization` (culture G).

## 2. Leçons « format 2 »

- **18 à 24 exercices par leçon (vise 20)**, ids `<lessonId>.e01` à `.eNN`.
- Répartition par type, selon la matière :

| Type | Anglais | Arabe | Culture G |
|---|---|---|---|
| `mcq` | 3–6 | 5–10 | 6–10 |
| `fill_blank` | 3–6 | 2–5 | 3–5 |
| `translation` | 3–5 | 1–4 | 0 |
| `reorder` | 2–3 | 1–4 | 0–2 |
| `match` | 2–3 | 3–5 | 2–4 |
| `free_answer` | 2–4 | 1–3 | 2–4 |

- La notion de la leçon est l'unité principale (premier `unitIds`) d'**au moins un tiers** des exercices. Chaque mot de vocabulaire de la leçon apparaît dans au moins un exercice.
- **Progression dans la leçon** : les premiers exercices font reconnaître (QCM, association), les suivants font retrouver puis produire. Difficulté croissante (`difficulty` 1 à 5).
- **Révision intégrée** : 3 à 5 exercices par leçon réutilisent des notions ou des mots des leçons précédentes (mets alors leur identifiant en premier dans `unitIds`). C'est ce qui fait « rentrer » les choses.
- Jamais deux fois la même question. Les distracteurs des QCM sont plausibles (vraies confusions), jamais absurdes.
- `explanation` (1 à 3 phrases) dit **pourquoi**, `tip` donne un moyen de retenir, `extraExample` montre la même chose dans un autre contexte. Ajoute des `errorPatterns` pour les erreurs prévisibles (au moins un exercice sur deux).

## 3. Conventions par matière

### Anglais (`en`, modules 9 et plus)
- Niveau B1 à C1 : phrases naturelles d'adultes (travail, voyages, actualité, relations), pas de phrases d'enfants.
- `promptLanguage` : `en` ou `fr`. Au plus 2 traductions anglais → français par leçon.
- Dictionnaire : `ipa` britannique entre `/ /`, `forms` comme dans SCHEMA.md (verbes : `thirdPerson`, `past`, `pastParticiple`, `ing`).

### Arabe (`ar`)
- Objectif n°1 de l'apprenant : **lire vite**. Il connaît plus ou moins les lettres mais doit encore réfléchir à chaque forme (isolée, début, milieu, fin). Ensuite : signes (harakat), règles de lecture, vocabulaire de l'Église copte orthodoxe, puis arabe égyptien du quotidien.
- Arabe standard **entièrement vocalisé** (avec harakat) dans les premiers modules, sauf quand l'exercice porte justement sur la lecture sans voyelles.
- Formes des lettres : utilise le tatweel `ـ` pour montrer une forme attachée : début `بـ`, milieu `ـبـ`, fin `ـب`, isolée `ب`.
- **Translittération** (champ `transliteration` des fiches et des exemples, et réponses des exercices de lecture) : système simple pour francophone :
  - voyelles brèves `a i u`, longues `â î û` ;
  - `th` ث, `dj` ج (arabe standard), `7` ح, `kh` خ, `dh` ذ, `ch` ش, `S` ص, `D` ض, `T` ط, `Z` ظ, `3` ع, `gh` غ, `q` ق, `'` hamza ;
  - `ou` n'est jamais utilisé : `u`.
  Dans les exercices de lecture où l'apprenant tape une translittération, liste les variantes raisonnables dans `acceptedAnswers` (ex. `kitâb`, `kitab`, `kitaab`).
- **L'apprenant tape mal l'arabe sur iPhone** : privilégie les QCM, associations, remises en ordre et textes à trou avec `options`. Les réponses tapées sont en français (sens d'un mot : `translation` avec `promptLanguage: "ar"`) ou en translittération (`free_answer`).
- `promptLanguage` : `ar` quand le `prompt` est en arabe, sinon `fr`.
- `examples`, `extraExample` : `{text (arabe), translation (français), transliteration}`.
- Dictionnaire : `word` en arabe vocalisé, `transliteration` obligatoire, `forms` libres et utiles : pour une lettre `{"isolated": "ب", "initial": "بـ", "medial": "ـبـ", "final": "ـب"}`, pour un nom `{"plural": "…"}`. Pas de champ `ipa`.
- Textes religieux : mots isolés et formules courtes (réponses de la liturgie, versets très courts de la Bible Van Dyck), jamais de longs passages recopiés d'un site.

### Culture G (`cg`)
- Tout est en français (`promptLanguage: "fr"`), aucune traduction.
- **Exactitude absolue** : seulement des faits établis et vérifiables. Pas de chiffres qui changent vite (population exacte, dirigeants actuels, records) ; s'il le faut, ordre de grandeur (« environ 68 millions d'habitants en 2024 »). Dans le doute, n'écris pas la question.
- Une leçon = un sujet raconté comme une histoire : la fiche (`units.json`) résume l'essentiel en 4 à 6 phrases claires ; `pattern` donne le repère à retenir (« 1789 : début de la Révolution »), `examples` = 3 à 4 faits clés `{text: fait, translation: pourquoi c'est important}`, `commonErrors` = idées reçues ou confusions fréquentes.
- Vocabulaire = notions, personnages, lieux, dates, œuvres, organisations clés de la leçon. Fiche dictionnaire : `word` = le terme, `translation` = définition en quelques mots, `explanation` = 1 à 2 phrases, `examples` = 2 faits.
- `reorder` : remettre en ordre les mots d'une phrase-repère (« La Révolution française commence en 1789 »).
- `free_answer` : réponse courte et sans ambiguïté (« Quelle est la capitale du Canada ? » → `Ottawa`), avec les variantes acceptées (avec ou sans article, orthographes courantes).

## 4. Valider

```bash
python3 tools/build_content.py --lang <lang> --module mNN
```

Le module doit afficher `Module OK.` sans aucune erreur. Corrige toutes les erreurs et regarde les avertissements. Ne modifie rien en dehors de ton dossier de module, ne lance pas la construction complète et ne fais pas de commit.
