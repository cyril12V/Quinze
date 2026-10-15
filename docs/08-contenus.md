# Contenus pédagogiques

## Ce qui est livré (anglais, version 1.0.0)

| Élément | Nombre | Cible du cahier des charges |
|---|---|---|
| Modules | 8 | 8 |
| Notions de grammaire, avec prérequis | 41 | 30 |
| Mots et expressions | 305 | 300 |
| Leçons | 60 | 60 |
| Exercices de leçon | 600 | au moins 600 |
| Fiches de dictionnaire (vocabulaire et mots-outils) | 397 | — |
| Questions de diagnostic | 40 (5 par module, niveaux 0 à 4) | test de 15 à 20 questions |
| Questions d'évaluation périodique (jamais vues en leçon) | 40 | test tous les 14 jours |
| Réponses acceptées | 1 426 | — |
| Erreurs anticipées avec retour ciblé | 1 283 | — |

Chaque leçon contient 10 exercices : 2 QCM, 2 phrases à compléter, 2 traductions, 1 remise en ordre, 1 association et 2 réponses libres. Chaque exercice comporte une explication (pourquoi la réponse est correcte), une astuce, un exemple dans un autre contexte et, le plus souvent, des erreurs anticipées avec un retour précis.

Les exemples du cahier des charges sont présents :
- « She doesn't ___ to school » en L20 ;
- « What is the past tense of go? », « Yesterday, I ___ to school », « Je suis allé au travail » et « Écris une phrase au passé avec go » en L30 ;
- « J'ai compris » en L58 ;
- « through / though / thought / tough » dans le dictionnaire.

## Organisation

```
Content/
  SCHEMA.md                    format détaillé de chaque fichier
  en/curriculum.json           plan : modules, notions et prérequis, leçons, vocabulaire (généré)
  en/briefs/mNN.md             résumé par module (pour les rédacteurs)
  en/source/mNN/               le contenu rédigé, un dossier par module
    units.json                 règles de grammaire
    dictionary.json            fiches du dictionnaire
    lessons/lNN.json           exercices de chaque leçon
    diagnostic.json            questions du test de positionnement
    assessment.json            questions des évaluations périodiques
  build/en.json                bundle compilé (lu par l'app et le moteur)
tools/
  curriculum_source.py         source du plan → curriculum.json
  build_content.py             validation + bundle + seed SQL
  make_briefs.py               briefs par module
```

## Modifier le contenu

1. Modifie les fichiers JSON de `Content/en/source/`. Le format est décrit dans `Content/SCHEMA.md`.
2. Valide le module : `python3 tools/build_content.py --lang en --module m03`. Toute erreur bloque.
3. Reconstruis tout : `python3 tools/build_content.py --lang en`. Le script écrit :
   - `Content/build/en.json` ;
   - la copie embarquée dans l'app `App/Resources/Content/en.json` ;
   - `supabase/seed/content_en.sql`.
4. Vérifie la cohérence avec le moteur : `cd Packages/LearningCore && swift test`. Le test `RealContentTests` évalue chaque réponse acceptée et chaque erreur anticipée avec le vrai moteur.

Règles importantes :
- **Ne renomme jamais un identifiant publié** (`en.l20.e03`, `en.g15.…`, `en.v.…`), car la progression des utilisateurs y est rattachée. Pour retirer un contenu, ajoute `"deprecated": true`.
- **Augmente `contentVersion`** dans `tools/curriculum_source.py` à chaque publication.
- Le moteur gère déjà les majuscules, la ponctuation, les contractions, les chiffres de 0 à 20 et les fautes de frappe légères. En revanche, il faut lister les synonymes, les autres ordres de mots corrects et les variantes britanniques ou américaines.

## Publier une mise à jour sans nouvelle version de l'app

1. Reconstruis le bundle.
2. Charge `supabase/seed/content_en.sql` dans la base. Le script met aussi à jour `content_versions`.
3. Dépose `Content/build/en.json` dans le bucket Storage `content` sous `en/<version>.json`.

Au démarrage suivant, l'app voit la nouvelle version via `content_manifest`, télécharge le bundle, vérifie son empreinte SHA-256 et l'utilise au lancement d'après. La progression est conservée, puisque les identifiants sont stables.

## Relecture humaine (obligatoire avant publication)

Le corpus a été rédigé par IA, puis validé automatiquement : structure, répartition, réponses acceptées et erreurs anticipées passées au vrai moteur, références. Les rédacteurs ont aussi fait une relecture linguistique, module par module. Ton cahier des charges exige une **vérification linguistique avant publication** (§7.3) : prévois la relecture d'un professeur d'anglais francophone. En priorité :
1. les explications de grammaire (`units.json`) ;
2. les traductions acceptées des exercices de traduction et de réponse libre (une bonne réponse refusée est le défaut le plus pénalisant) ;
3. les fiches du dictionnaire.

## Recommandation pour la suite

Avec 10 exercices par leçon, trois sessions par jour consomment plus d'exercices que ce que les premières leçons proposent : le moteur doit parfois répéter un exercice dans la journée (voir [11-limites-connues.md](11-limites-connues.md)). Passer à **20 à 30 exercices par leçon** (V1.1) supprimerait ces répétitions. Les scripts et le validateur sont prêts pour cela.
