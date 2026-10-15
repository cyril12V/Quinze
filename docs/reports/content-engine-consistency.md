# Cohérence contenu / moteur

Rapport généré par `RealContentTests.testModelAnswersAndPatterns` (`QUINZE_WRITE_REPORT=1 swift test --filter RealContentTests`).

Le test évalue, avec le moteur, chaque réponse modèle / réponse acceptée (2273 réponses) de chacun des 680 exercices (leçons 600, diagnostic 40, évaluation 40) et chacun des 784 patterns d'erreur `equals`. Il vérifie aussi que toutes les références (`unitIds`, `lessonId`, prérequis, dictionnaire) se résolvent et que les exercices à réponse ouverte (`requirements`) refusent une phrase hors sujet.

## Incohérences bloquantes

Aucune : toutes les réponses modèles sont acceptées, aucun pattern d'erreur `equals` n'est accepté, toutes les références se résolvent.

## Observations (non bloquantes)

**Patterns d'erreur équivalents après normalisation (2)** : l'ordre de la liste décide du retour affiché.

- `en.l41.e05` : « aren't » et « are not » ont la même forme canonique mais des retours différents (le premier gagne)
- `en.l42.e05` : « isn't » et « is not » ont la même forme canonique mais des retours différents (le premier gagne)

**Pool d'exercices par leçon : 10 à 10.** Trois sessions de 8 à 12 exercices par jour consomment environ 33 exercices ; avec 10 exercices par leçon, les premiers jours (et, pour un apprenant en difficulté, les premières semaines) n'offrent pas assez d'exercices distincts : le moteur évite d'abord les exercices déjà faits aujourd'hui puis, en dernier recours seulement, en répète un. Mesure sur la simulation de 30 jours : 0 à 18 répétitions planifiées le même jour après le jour 5 selon le profil. Recommandation : viser 20 à 30 exercices par leçon (ou plus de variantes par notion) pour supprimer les répétitions.
