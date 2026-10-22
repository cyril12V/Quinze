# Quinze v2 : anglais, arabe et culture G

Ce document décrit le fonctionnement de la version 2 pour l'utilisateur, et où se trouve chaque morceau dans le code.

## Une journée type

- **Trois créneaux par jour** (matin, après-midi, soir), aux heures choisies dans Réglages > Horaires.
- Chaque créneau enchaîne les matières actives dans l'ordre **anglais → arabe → culture G**, 5 minutes chacune par défaut, réglables de 2 à 20 minutes dans Réglages > Mes matières.
- À la fin d'une matière, l'écran propose « Continuer : Arabe · 5 min » ou « Plus tard ».
- Le créneau est terminé quand toutes les matières sont faites. Les apps bloquées sont alors libérées.
- Si tu vas plus vite que prévu, la session continue avec des révisions jusqu'au temps choisi.
- **Pratique libre** (carte en bas de l'accueil) : une 4e séance quand tu veux. S'il n'y a rien à réviser, elle t'apprend la leçon suivante.
- **Ma journée** (bouton calendrier de l'accueil) : chaque créneau avec son heure, ses matières et leurs minutes, et l'heure à laquelle les apps seront bloquées si la leçon n'est pas faite.

Chaque matière a son propre moteur (répétition espacée FSRS, maîtrise, parcours). Une leçon peut donc mêler révisions et nouveautés indépendamment pour chaque matière. Jusqu'à 3 nouvelles leçons par jour et par matière.

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
| Arabe | m01–m04 : 32 leçons, 689 exercices, 283 fiches | m01 lettres et 4 formes · m02 voyelles et signes (harakat) · m03 lire vite · m04 mots de l'Église copte ; égyptien prévu ensuite |
| Culture G | m01–m05 : 40 leçons, 852 exercices, 397 fiches | m01 histoire · m02 géographie · m03 sciences · m04 économie et politique · m05 arts, littérature, philosophie |

Le workflow `engine-tests.yml` vérifie à chaque changement que les contenus embarqués fonctionnent avec le moteur :

- toutes les références se résolvent ;
- chaque bonne réponse est acceptée et chaque erreur prévue est refusée ;
- deux semaines de trois séances par jour progressent sans séance vide.

Les sources sont dans `Content/<matière>/source/mNN/`. Les règles d'écriture des nouveaux modules sont dans `Content/BRIEF-V2.md`. Pour valider un module, puis reconstruire le fichier lu par l'app :

```bash
python3 tools/build_content.py --lang ar --module m02   # un module
python3 tools/build_content.py --lang ar                # tout : écrit App/Resources/Content/ar.json
```

Conventions arabes :

- Mots toujours vocalisés.
- Formes des lettres montrées avec le tatweel ـ.
- Translittération : â/î/û pour les voyelles longues, 7 = ح, 3 = ع, kh, gh, ch = ش, dj = ج, S/D/T/Z pour les emphatiques, ' pour la hamza.
- La correction ignore harakat et tatweel, et accepte les variantes de alif, de ya et de ta marbouta.

## Dans le code

| Fichier | Rôle |
|---|---|
| `App/Sources/Core/Subject.swift` | Les trois matières (préfixes d'identifiants `en.`, `ar.`, `cg.`) |
| `App/Sources/Core/StudyCoordinator.swift` | Enchaînement des matières dans un créneau, levée des restrictions, rappels |
| `App/Sources/Services/ContentService.swift` | Un moteur `LearningCore` par matière |
| `App/Sources/Services/ClaudeDirectClient.swift`, `KeychainStore.swift` | Appels directs à Claude avec la clé du trousseau |
| `App/Sources/Features/Settings/StudySettingsSections.swift`, `AISettingsSection.swift` | Réglages v2 |
| `App/Sources/Features/Dictionary/` | Dictionnaire, séries de mots et jeux |
