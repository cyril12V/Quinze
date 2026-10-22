# Contenus v3 : apprendre d'abord, l'arabe égyptien, la culture G en cours

Ce brief complète `Content/BRIEF-V2.md` (format des modules, outline, units, dictionary, lessons) et `Content/SCHEMA.md` (champs des exercices). Ce qui change en v3 est décrit ici. En cas de conflit avec BRIEF-V2, ce document gagne.

L'apprenant a donné trois principes : **ludique, compréhension, logique**.

## 1. Le cours : on apprend avant d'être interrogé

Chaque leçon d'arabe et de culture G a un **cours**. Ce sont des cartes que l'apprenant lit avant les questions, dans `Content/<lang>/source/mNN/course/lSEQ.json` :

```json
{
  "lessonId": "cg.l04",
  "cards": [
    {"emoji": "🥖", "title": "1789 : le peuple a faim",
     "text": "En 1789, le pain coûte très cher et l'État est ruiné. Le roi Louis XVI convoque les états généraux pour trouver de l'argent.",
     "keyFact": "1789 : début de la Révolution française."},
    {"emoji": "🏰", "title": "Le 14 juillet 1789", "text": "...", "keyFact": "..."}
  ]
}
```

### Champs d'une carte

| Champ | Obligatoire | Contenu |
|---|---|---|
| `title` | oui | 70 caractères max |
| `text` | oui | 480 caractères max : une idée par carte, expliquée simplement, avec le **pourquoi** (logique) |
| `keyFact` | non | « À retenir », une phrase courte (180 caractères max) |
| `emoji` | non | un emoji pour rendre la carte vivante |
| `example` | non | `{"text", "translation"}` |
| `arabic` | non | pour l'arabe : la lettre ou le mot montré en grand sur la carte |

### Règles du cours

- **3 à 10 cartes par leçon** (vise 5 à 8), dans un ordre logique : on part de ce qu'on sait, on raconte, on relie les faits.
- **Tout ce qui est demandé dans les exercises est d'abord enseigné.** Le validateur le vérifie :
  - mcq et fill_blank : la réponse attendue doit apparaître mot pour mot (accents et harakat ignorés) dans les cartes ou le vocabulaire de cette leçon ou d'une leçon précédente ;
  - free_answer : au moins une réponse acceptée doit y apparaître ;
  - match : au moins un côté de chaque paire doit y apparaître.

  Si une réponse n'est pas enseignée, **ajoute-la au cours** (de préférence) ou change la question.
- Pas de question piège sur un détail jamais vu. Les distracteurs (mauvaises options) peuvent, eux, ne pas être dans le cours.
- Les explications des exercises (`explanation`, feedback) rappellent la carte correspondante.

## 2. Culture G

- Le cours est le cœur de la leçon : il raconte, explique les causes et les conséquences, et donne des repères mémorables (dates, noms, chiffres arrondis). Les questions vérifient ensuite ce qui vient d'être lu.
- Tout est en français : consignes, réponses, feedback. Il n'y a pas d'audio.
- Les exercises existants restent. Le travail consiste à écrire le cours de chaque leçon pour qu'il couvre **toutes** les réponses. Si un exercise demande un fait trop pointu pour être enseigné en une carte, remplace-le par une question sur un fait du cours.

## 3. Arabe : de la lettre à l'égyptien de tous les jours

L'apprenant est égyptien, copte orthodoxe. Il parle égyptien mais lit lentement : il doit encore réfléchir à chaque lettre.

### Règles absolues

1. **Mots égyptiens**, ceux qu'on dit vraiment au Caire, écrits comme les Égyptiens les écrivent : عيش (pain), مية (eau), عايز, إزيك, كويس, النهارده, بكرة, فين, إيه, ليه, ماشي, أوضة, ترابيزة. **Pas d'arabe littéraire** pour la vie courante : pas خبز, ماء, أريد, كيف حالك, غرفة, طاولة.
2. **Mots d'église mélangés tôt**, dès que les lettres le permettent : كنيسة, صليب, قداس, أبونا, إنجيل, صلاة, يسوع, المسيح, العدرا, شماس, قربان, تسبحة, نبوات, أجبية, مزمور, آمين, يا رب ارحم. Ce sont les mots de la liturgie copte : orthographe usuelle des livres coptes arabes.
3. **Aucune translittération** : jamais de mots arabes écrits en lettres latines. Pas de champ `transliteration` : le validateur le refuse. Pour enseigner le son d'une lettre, décris-le en français (« ب se lit comme le b de bateau ; ج se dit g en Égypte, comme dans gâteau »).
4. **Pas de harakat avant le module 3**, qui les enseigne. Dans les modules 1 et 2, aucun signe ـَ ـِ ـُ ـْ ـّ ـً ـٍ ـٌ, nulle part (cours, prompts, options, dictionnaire) : le validateur le refuse. On écrit sans voyelles, comme les Égyptiens au quotidien.
5. **L'apprenant ne tape jamais d'arabe.** Les réponses en arabe se choisissent :
   - mcq ;
   - match ;
   - fill_blank avec options ;
   - reorder de lettres, à éviter : préfère mcq et match.

   Les réponses tapées sont en français (translation ar→fr : « Que veut dire عيش ? » → « pain »).
6. **Consolidation avant d'avancer.** Le moteur fait passer un contrôle à la fin de chaque module : il faut 80 % pour passer au module suivant. Les leçons doivent donc préparer ce contrôle, avec beaucoup de révisions des leçons précédentes (au moins 4 exercises de révision par leçon dans les modules 1 et 2).

### Programme (40 leçons)

| Module | Leçons | Contenu |
|---|---|---|
| m01 Les lettres, une par une | 1–8 | Lettres seules (forme isolée), leur son, leur nom, les points qui les distinguent. Pas encore de mots. |
| m02 Les lettres dans le mot | 9–16 | Formes début / milieu / fin, lettres qui ne s'attachent pas, lire des mots courts égyptiens et d'église, sans voyelles. |
| m03 Les harakat | 17–24 | Fatha, kasra, damma, sukun, voyelles longues, shadda, tanwin, hamza et madda, ال (lettres solaires et lunaires), ة et ى. Mots vocalisés comme on les prononce en égyptien. |
| m04 Lire petit à petit | 25–32 | Syllabes, mots longs, petites phrases égyptiennes, réponses de la liturgie, lire sans voyelles en s'aidant du sens, mots fréquents (ده, دي, في, على, مش). |
| m05 L'égyptien de tous les jours | 33–40 | Salutations et politesse, famille, maison, nourriture, au café et au marché, chiffres et prix, le temps (النهارده, بكرة, امبارح), à l'église. |

Dans m01 et m02, chaque leçon a 3 à 5 lettres nouvelles :

| Leçon | Lettres |
|---|---|
| 1 | ا ب ت ث |
| 2 | ن ي, et les points pour distinguer ب ت ث ن ي |
| 3 | ج ح خ |
| 4 | د ذ ر ز |
| 5 | س ش ص ض |
| 6 | ط ظ ع غ |
| 7 | ف ق ك ل |
| 8 | م ه و, plus ء ة ى, puis le bilan de l'alphabet |

m02 reprend les mêmes familles de lettres, cette fois dans des mots.

### Vocabulaire et identifiants

- **m01 :** le vocabulaire d'une leçon, ce sont ses lettres (`partOfSpeech: "letter"`, slug ASCII : alif, ba, ta, tha…). L'entrée du dictionnaire a pour `word` la lettre, et pour `translation` son nom et son son en français (« bâ — son b »).
- **À partir de m02 :** 6 à 10 mots par leçon (`noun`, `verb`, `expression`…), avec un slug ASCII interne (`eish`, `kanisa`) jamais montré à l'apprenant.
- **Dictionnaire :** `examples` en arabe égyptien, avec la traduction française. Dans m01, les exemples peuvent montrer la lettre dans un mot connu, sans harakat.

### Exercises d'arabe (sans translittération)

- « Quelle lettre fait le son b, comme dans bateau ? » → options ب ت ث ن.
- « Combien de points a ث ? » ; « Quelle lettre a un point dessous ? ».
- Match lettre ↔ nom ou son ; lettre isolée ↔ forme du début (m02).
- « Lis ce mot : عيش » → options en français : pain / thé / maison / eau.
- « Quel mot veut dire « église » ? » → options en arabe.
- fill_blank avec options : « بـ_ت (maison) » → ي.
- translation ar→fr tapée en français : « Que veut dire كنيسة ? » → église.

Répartition par leçon d'arabe :

| Type | Nombre |
|---|---|
| mcq | 6–12 |
| match | 3–6 |
| fill_blank | 0–6 |
| translation | 0–4 |
| reorder | 0–4 |
| free_answer | 0–3 |

Total : 18 à 24 exercises.

## 4. Les identifiants changent

Le contenu arabe v3 repart de zéro (`Content/ar/curriculum.json` en version 3.0.0) : les anciens modules sont supprimés. La progression arabe et culture G de l'apprenant est remise à zéro dans l'app.
