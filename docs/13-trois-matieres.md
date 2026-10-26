# Quinze : anglais, arabe et culture G (v3)

Ce document décrit le fonctionnement de l'app pour l'utilisateur, et où se trouve chaque morceau dans le code. La v3 suit les retours de l'utilisateur : trois matières vraiment séparées, apprendre avant d'être interrogé, ne pas avancer sans avoir consolidé. Ses mots d'ordre : **ludique, compréhension, logique**.

## Trois matières séparées

- **Accueil :** pour le créneau en cours (matin, après-midi, soir), un bloc par matière, 🇬🇧 Anglais · 🇪🇬 Arabe · 🌍 Culture G, avec son état (à faire, en cours, fait), ses minutes et la prochaine leçon. On touche un bloc, on fait la séance, on revient à l'accueil, puis on touche le bloc suivant.
- **Apps bloquées :** elles se débloquent quand les trois blocs du créneau sont faits.
- **Un onglet par matière** (Anglais, Arabe, Culture G), chacun avec son Parcours, ses Mots & jeux et ses Progrès. Rien d'une matière n'apparaît dans une autre.
- **Entraînement libre :** en bas de l'accueil, une séance de plus dans la matière de son choix, quand on veut.
- **Ma journée** (bouton calendrier de l'accueil) : chaque créneau avec son heure, ses matières et l'heure à laquelle les apps seront bloquées.

## Apprendre vraiment

- **D'abord le cours, ensuite les questions.** En arabe et en culture G, chaque leçon commence par des cartes (récit, pourquoi, « À retenir »). Les questions ne portent que sur ce qui a été appris. Le validateur de contenu le vérifie pour chaque réponse.
- **Une erreur, puis la question revient.** Après l'explication, la même question revient deux questions plus loin, puis une question semblable, jusqu'à 2 essais de plus.
- **Une leçon est validée avec 80 % de bonnes réponses du premier coup.** Sinon on la reprend à la séance suivante, avec le cours, et on ne passe pas à la suite.
- **Contrôle de fin de module (80 %).** Il ouvre le module suivant. S'il est raté, la séance suivante est une révision ciblée du module, puis on le repasse. En arabe, on ne passe donc pas aux mots tant que les lettres ne sont pas consolidées.
- **Les séances de la journée sont différentes :**

  | Séance | Contenu |
  |---|---|
  | Matin | Rappel de mémoire de la veille, puis une nouvelle leçon |
  | Après-midi | Rappel de mémoire de la leçon du matin, puis une nouvelle leçon |
  | Soir | Bilan du jour et révisions espacées. Nouvelle leçon seulement si rien n'a été appris dans la journée. |

  Au plus 2 nouvelles leçons par jour et par matière. Le haut de l'écran indique la partie en cours : Cours, Rappel, Nouvelle leçon, Révision, On réessaie, Contrôle du module, Bilan du jour.
- **Répétition espacée (FSRS) :** chaque notion revient au moment où elle risque d'être oubliée, à peu près 1 jour, 3 jours, 1 semaine, 1 mois après.
- **Durée :** chaque séance vise les minutes réglées (5 par défaut). Elle peut durer plus longtemps si des questions reviennent.

## Arabe

Le chemin est fait pour un Égyptien qui lit encore lentement :

| Module | Contenu |
|---|---|
| m01 | Les lettres en vitesse (4 leçons) : on voit la lettre (seule, au début, au milieu, à la fin) et on choisit son son ; on la repère dans de vrais mots ; des mots à lire |
| m02 | Lire des mots : repérer chaque lettre dans le mot, lire des mots égyptiens et d'église et de petites lignes, sans voyelles |
| m03 | Les harakat |
| m04 | Lire petit à petit, dont les réponses de la liturgie |
| m05 | L'égyptien de tous les jours |

Règles du contenu arabe :

- Pas de translittération : on lit l'arabe, avec l'audio.
- Pas de harakat avant le module qui les enseigne.
- On ne tape jamais d'arabe : on choisit ou on associe.
- Les mots du quotidien sont égyptiens (عيش, مية, عايز…), pas littéraires.

## Culture G

Un format à part :

- un vrai cours en cartes, puis des questions sur ce cours ;
- tout en français, réponses comprises ;
- aucun bouton audio.

## Réglages ajoutés

| Section | Ce qu'elle règle |
|---|---|
| Mes matières | Activer ou couper une matière, minutes par matière, durée totale d'un créneau |
| Apparence | Clair (par défaut), sombre ou automatique |
| Voix | Voix par langue (anglais, arabe, français), aperçu, vitesse de lecture |
| Professeur IA | Ta clé API Claude : enregistrer, tester, remplacer, supprimer |

### Voix

iOS fournit des voix « Premium » ou « Améliorées » nettement plus naturelles. Elles ne sont pas installées par défaut :

1. Va dans Réglages iPhone > Accessibilité > Contenu énoncé > Voix.
2. Télécharge-les par langue : anglais, arabe, français.
3. Choisis-les dans Quinze > Réglages > Voix.

Sans choix de ta part, Quinze prend la meilleure voix installée.

### Professeur IA : ta clé Claude

Le professeur sert à trois choses : « Explique-moi », les explications de mots et la correction des réponses libres. Il appelle Claude directement depuis l'iPhone avec ta clé, sans serveur.

1. Crée une clé sur [console.anthropic.com](https://console.anthropic.com) > API Keys. Il faut un peu de crédit sur le compte.
2. Colle-la dans Réglages > Professeur IA, puis appuie sur Tester.

Ce qu'il faut savoir :

- La clé est gardée dans le trousseau de l'iPhone. Elle n'est **jamais** dans le dépôt GitHub (public) ni dans l'app compilée.
- Modèle utilisé : `claude-haiku-5-5`. Le coût est de quelques centimes par jour.
- Sans clé, le professeur répond avec les explications intégrées. Tu corriges alors toi-même les réponses libres.

## Contenu

| Matière | Dans l'app | Programme |
|---|---|---|
| Anglais | m01–m12 : 92 leçons, 1 280 exercices, 698 fiches | A1 → B2 : bases, temps, récits (m09), conditions (m10), passif et discours rapporté (m11), anglais pro et nuances (m12) |
| Arabe | m01–m05 : 36 leçons avec cours, 831 exercices, 335 fiches | m01 lettres seules · m02 lettres dans le mot · m03 harakat · m04 lire petit à petit · m05 égyptien de tous les jours |
| Culture G | m01–m05 : 40 leçons avec cours, 852 exercices, 397 fiches | m01 histoire · m02 géographie · m03 sciences · m04 économie et politique · m05 arts, littérature, philosophie |

Le workflow `engine-tests.yml` vérifie à chaque changement que les contenus embarqués fonctionnent avec le moteur :

- toutes les références se résolvent ;
- chaque bonne réponse est acceptée et chaque erreur prévue est refusée ;
- deux semaines de trois séances par jour progressent sans séance vide.

Les sources sont dans `Content/<matière>/source/mNN/`. Les règles d'écriture des modules sont dans `Content/BRIEF-V2.md` et `Content/BRIEF-V3.md` (cours, arabe égyptien, culture G). Pour valider un module, puis reconstruire le fichier lu par l'app :

```bash
python3 tools/build_content.py --lang ar --module m02   # un module
python3 tools/build_content.py --lang ar                # tout : écrit App/Resources/Content/ar.json
```

Conventions arabes :

- Pas de translittération, pas de harakat avant le module 3 (refusé par le validateur).
- Formes des lettres montrées avec le tatweel ـ.
- La correction des réponses tapées ignore harakat et tatweel, et accepte les variantes de alif, de ya et de ta marbouta.
- Une option touchée est comparée à la lettre près.

## Dans le code

| Fichier | Rôle |
|---|---|
| `App/Sources/Core/Subject.swift` | Les trois matières (préfixes d'identifiants `en.`, `ar.`, `cg.`) |
| `App/Sources/Core/StudyCoordinator.swift` | Séance d'une matière pour un créneau, levée des restrictions quand les trois sont faites, rappels |
| `App/Sources/Features/Home/`, `App/Sources/Features/Path/SubjectSpaceView.swift` | Accueil à trois blocs, onglet de chaque matière |
| `App/Sources/Features/Lesson/LessonCourseCardView.swift` | Cartes de cours |
| `Packages/LearningCore/Sources/LearningCore/Planning/SessionPlanner.swift` | Séances du jour, cours, contrôles de module ; `registerCompletion(of:attempts:…)` décide si une leçon est validée |
| `App/Sources/Services/ContentService.swift` | Un moteur `LearningCore` par matière |
| `App/Sources/Services/ClaudeDirectClient.swift`, `KeychainStore.swift` | Appels directs à Claude avec la clé du trousseau |
| `App/Sources/Features/Settings/StudySettingsSections.swift`, `AISettingsSection.swift` | Réglages v2 |
| `App/Sources/Features/Dictionary/` | Dictionnaire, séries de mots et jeux |
