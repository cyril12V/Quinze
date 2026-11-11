# Brief v4 : les leçons guidées de l'app Nofri (Église copte)

## Pourquoi on réécrit tout

L'apprenant a utilisé la première version (dossier `Content/eg/v1/`) et l'a rejetée :

- « trop à lire d'un coup » : 7 à 9 cartes de cours à la suite, puis 20 questions ;
- « questions trop dures » : on lui demandait des détails (dates, noms) qu'il venait à peine de lire ;
- « trop sec, pas de jeu » : ça ressemblait à un contrôle ;
- « on m'envoie au charbon direct ».

Ce qu'il veut : « comme Duolingo, j'avance petit à petit », « je dois devenir un monstre dans l'Église ». Il est copte orthodoxe, francophone, pratiquant, adulte. Mots d'ordre : **ludique, compréhension, logique**.

Les faits de la v1 ont été vérifiés et corrigés : **garde les mêmes faits, les mêmes dates, les mêmes réserves** (« selon la tradition copte »). Ce qui change, c'est la façon d'enseigner. Tu n'ajoutes un fait nouveau que s'il est solidement établi.

## Le principe d'une leçon guidée

Une leçon dure 3 à 5 minutes et suit toujours ce déroulement :

1. **Une petite carte** : une seule idée, ou une scène d'un récit. 2 à 4 phrases courtes.
2. **Tout de suite, 1 ou 2 questions faciles sur cette carte** : la réponse est écrite sur la carte qu'il vient de lire. Il gagne, il prend confiance.
3. Carte suivante, et ainsi de suite : **3 à 6 cartes**.
4. **L'entraînement** : 4 à 8 questions qui mélangent toute la leçon, de la plus guidée à la plus exigeante, et qui font des liens avec les leçons précédentes.

Le moteur ajoute lui-même deux rappels des jours précédents au début, fait revenir chaque erreur, et exige 90 % pour valider. Ton travail est que la leçon soit **claire, vivante et progressive**.

L'exemple complet et validé à imiter est dans `Content/eg/EXEMPLE/` (leçon `eg.l101`, « Le feu de la Pentecôte »). Lis-le en entier avant d'écrire.

## Deux styles de cartes

Chaque carte porte un champ `kind`.

- **`"story"` : une scène.** Pour l'histoire et les saints. Au présent, avec un lieu, un personnage, une action, un enjeu. On raconte comme à un ami : « Alexandrie, vers 318. Un prêtre très apprécié, Arius, se lève et dit une phrase qui va mettre le feu à l'Empire… ». Une leçon d'histoire est un épisode : elle a un début, une tension, une chute. La dernière carte peut être une carte `"idea"` qui dit ce qu'il faut en retenir.
- **`"idea"` : une notion.** Pour le Credo, les sacrements, la prière, le bâtiment, le copte, et les bilans. Une idée, son pourquoi, une image concrète ou une comparaison.

Dans les deux cas :

- `title` : court et accrocheur (pas « Introduction », pas « Le contexte ») ;
- `text` : **320 caractères au plus**, phrases courtes, tutoiement possible, pas de liste, pas de jargon non expliqué ;
- `keyFact` : la phrase « À retenir », **130 caractères au plus** ; c'est elle qui apparaîtra sur le widget de l'écran verrouillé, donc elle doit se comprendre toute seule ;
- `emoji` : un seul, qui aide à se souvenir.

## Les questions

### Questions d'étape (champ `step`)

`"step": 2` veut dire « cette question suit immédiatement la carte 2 ».

- Chaque carte a **1 ou 2** questions d'étape.
- Type : `mcq`, ou `fill_blank` **avec** `options`. On touche, on ne tape pas.
- `difficulty` 1 ou 2.
- **La réponse est écrite mot pour mot sur la carte** (le validateur le vérifie). « Vrai » / « Faux » sont aussi permis (mcq à deux options).
- Les mauvaises options sont clairement fausses pour quelqu'un qui a lu la carte, mais pas absurdes. Une option drôle par leçon au plus.
- Elles portent sur **l'idée de la carte**, pas sur un détail perdu dans la phrase.

### Questions d'entraînement (sans `step`)

Après les cartes : **au moins 4**, de la plus facile à la plus exigeante.

- Varie les types : `match` (relier), `reorder` (remettre dans l'ordre : une chronologie, une cause puis sa conséquence, une phrase-repère), `fill_blank`, `mcq`.
- Au moins une question de **compréhension** (`difficulty` 3 ou plus) : « Pourquoi… ? », « Qu'est-ce qui se serait passé si… ? », « Quelle phrase Arius n'aurait jamais dite ? ». Là, la réponse est un raisonnement, pas une citation.
- À partir de la deuxième leçon d'un chapitre, au moins **2 questions font un lien avec une leçon précédente** (du chapitre ou d'un chapitre précédent) : comparer, replacer dans l'ordre, ne pas confondre. Mets alors l'unité ancienne dans `unitIds`.
- Au plus **1** `free_answer` et au plus **2** réponses tapées par leçon. Une réponse tapée est un seul mot simple, jamais une date, jamais du copte ni de l'arabe.

### Qualité d'une question

- Une seule bonne réponse, sans discussion possible.
- Les options ont à peu près la même longueur. **La bonne réponse n'est pas la plus longue.** Sa position change d'une question à l'autre.
- Pas de « toutes ces réponses », pas de double négation, pas de piège de formulation.
- Deux questions d'une même leçon n'ont jamais le même énoncé. Dans tout le cours non plus : évite les énoncés passe-partout comme « Qui est qui ? » (précise : « Les trois Pères d'Alexandrie : qui a fait quoi ? »).
- `explanation` : 1 ou 2 phrases chaleureuses qui donnent le **pourquoi** ou un moyen de s'en souvenir. Jamais « La bonne réponse est X ».
- `hint` (facultatif) : un coup de pouce qui ne donne pas la réponse.

### Les dates

Peu de dates : celles qui comptent vraiment (33, 49, 284, 313, 325, 381, 431, 451…). Jamais une date à taper.

1. Première rencontre : sur une carte, avec une image pour la retenir.
2. Question d'étape : la reconnaître parmi des dates très éloignées (325, 33, 1054).
3. Entraînement et leçons suivantes : parmi des dates plus proches (325, 381, 431), ou dans un `reorder` chronologique.

## Les fiches de collection (vocabulaire)

Chaque leçon introduit **2 à 4 fiches** (`vocabulary` dans `outline.json`, détail dans `dictionary.json`) : un saint, un concile, une hérésie, un lieu, une notion, un objet… L'apprenant les **collectionne** : elles se débloquent quand il fait la leçon. Choisis donc des fiches qu'on a envie d'avoir.

- `word` : le nom de la fiche ; `translation` : une définition en une ligne (80 caractères au plus).
- `explanation` : 2 ou 3 phrases : qui ou quoi, ce qu'il a fait, pourquoi il compte pour l'Église copte.
- `examples` : au moins 1 (`text` = une phrase qui l'emploie, `translation` = ce qu'il faut comprendre).
- `collection` (obligatoire), une valeur parmi :

  | Valeur | Pour |
  |---|---|
  | `saint` | saints et martyrs |
  | `pere` | Pères et docteurs (Athanase, Cyrille, Origène…) |
  | `pape` | papes d'Alexandrie et autres patriarches |
  | `concile` | conciles et synodes |
  | `heresie` | hérésies et hérésiarques |
  | `lieu` | villes, monastères, lieux |
  | `eglise` | Églises et confessions |
  | `notion` | idées, mots de théologie, institutions |
  | `priere` | prières, heures, pièces de la louange |
  | `objet` | objets, parties du bâtiment, vêtements |
  | `livre` | livres et écrits |
  | `date` | événements et dates |
  | `copte` | mots et règles de la langue copte |

- **Un mot n'est introduit qu'une seule fois dans tout le cours.** Le chapitre de numéro le plus bas le garde ; les autres le réutilisent par son identifiant `eg.v.slug` dans `unitIds`. Pour ne pas se marcher dessus, chaque chapitre **préfixe ses slugs** d'un code de deux lettres donné dans ta consigne (ex. chapitre 4 : `q4_arius`), sauf consigne contraire.
- Chaque fiche doit être utilisée dans au moins un exercice de sa leçon (dans `unitIds`).

## Fichiers et identifiants

Tout va dans `Content/eg/source/mNN/` (NN = numéro du chapitre). Le dossier `Content/eg/EXEMPLE/` montre chaque fichier.

| Fichier | Contenu |
|---|---|
| `outline.json` | le chapitre (`"format": 3`), ses notions (`grammarUnits`), ses leçons et leurs fiches |
| `units.json` | une notion par leçon : `summary`, `explanation`, `pattern`, 1 à 4 `examples`, 0 à 3 `commonErrors`, `tip` |
| `dictionary.json` | les fiches |
| `course/lSEQ.json` | les cartes d'une leçon |
| `lessons/lSEQ.json` | les questions d'une leçon |

- **Numéros de leçon : `chapitre × 100 + rang`.** Chapitre 4 : `eg.l401`, `eg.l402`… avec `"sequence": 401`, 402… Fichiers `course/l401.json`, `lessons/l401.json`.
- Notion d'une leçon : `eg.g401.slug` (une par leçon, `"introducesGrammar": true`, catégorie `knowledge`).
- Exercices : `eg.l401.e01`, `e02`… numérotés dans l'ordre où tu les écris (étapes d'abord, puis entraînement).
- Chaque exercice : `id`, `unitIds` (la notion de la leçon en premier, sauf pour une question de lien), `type`, `difficulty` (1 à 5), `instruction`, `prompt`, `promptLanguage` (`"fr"`), `answer`, `acceptedAnswers` (contient `answer` ; vide pour un `match`), `explanation`, et selon le type `options`, `tokens`, `pairs`, `step`.
- Au moins un tiers des exercices d'une leçon ont la notion de la leçon en premier dans `unitIds`.
- `reorder` : `tokens` = les morceaux dans le désordre (au moins 3), `answer` = les morceaux dans l'ordre séparés par une espace. Chaque morceau est **un seul mot sans espace** (utilise un trait d'union si besoin : `Saint-Esprit`).
- `match` : 3 à 5 `pairs` `{left, right}`, toutes différentes des deux côtés ; au moins un côté de chaque paire est écrit dans le cours.
- `mcq` : 2 à 4 `options`, dont `answer` à l'identique.
- `fill_blank` : exactement un `___` dans `prompt`.

## Taille d'un chapitre

- **8 à 14 leçons** par chapitre (jusqu'à 18 pour les plus gros). Une leçon de la v1 donne en général une à deux leçons guidées : on découpe, on n'entasse pas.
- La **dernière leçon** est un **bilan** du chapitre : des cartes `idea` très courtes (la frise, les trois choses à ne jamais confondre, les liens), puis un entraînement plus long qui couvre tout le chapitre. Un examen automatique suit le chapitre ; il pioche dans tes questions d'entraînement.
- Total d'une leçon : **10 à 16 exercices**.

## Ton et point de vue

- Point de vue copte orthodoxe, sans polémique, respectueux des autres Églises.
- Tutoiement, phrases courtes, humour léger permis, jamais moqueur envers une personne ou une croyance.
- On explique chaque mot savant la première fois (« consubstantiel : de la même nature »).
- Pas de textes de chants ni de liturgie à apprendre (le Credo est la seule exception).
- Un fait de tradition se dit comme tel : « selon la tradition copte », « selon le Synaxaire ».

## Valider

```bash
cd /home/claude/quinze && python3 tools/build_content.py --lang eg --module mNN
```

Jusqu'à **0 erreur et 0 avertissement** pour ton chapitre. Ne lance pas le build complet, ne touche à aucun autre chapitre ni à `App/`. Une erreur de doublon avec un chapitre de numéro plus bas se corrige chez toi.

Avant de rendre ton travail, relis trois leçons au hasard en te mettant à la place de l'apprenant : est-ce que chaque carte se lit en dix secondes ? Est-ce que la question d'après est facile et utile ? Est-ce qu'il a appris quelque chose qu'il pourra raconter ce soir ?
