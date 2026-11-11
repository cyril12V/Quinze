# Nofri : l'app Église copte, séparée de Quinze

Nofri (« bon », un salut en copte) est une deuxième app, installée à côté de Quinze. Elle n'enseigne qu'une chose : l'Église copte orthodoxe. L'Église n'est plus dans Quinze.

Elle a été refaite après les retours de l'utilisateur sur la première version (« trop à lire d'un coup », « questions trop dures », « trop sec », « on m'envoie au charbon direct »). Son but : « comme Duolingo, j'avance petit à petit », « devenir un monstre dans l'Église ».

## Ce que vit l'utilisateur

- **Une leçon guidée dure 3 à 5 minutes.**
  1. Deux rappels des jours précédents.
  2. Une petite carte (une scène d'histoire ou une idée), puis tout de suite une ou deux questions faciles dont la réponse est sur la carte.
  3. Carte suivante, et ainsi de suite (3 à 6 cartes).
  4. Un entraînement qui mélange la leçon et fait des liens avec les précédentes.
- **Exigeant.**
  - Il faut 90 % de bonnes réponses du premier coup pour valider une leçon.
  - Une erreur revient dans la séance jusqu'à être juste.
  - Chaque chapitre se termine par un examen de 20 questions, à réussir à 90 % pour ouvrir le chapitre suivant.
- **Blocage du téléphone**, comme Quinze : trois créneaux par jour, les apps choisies sont bloquées jusqu'à la leçon du créneau.
- **Hors créneau** : « Continuer le chemin » (jusqu'à 4 nouvelles leçons par jour) et le « Défi du jour » (un mélange de tout ce qui a été appris).
- **Points et titres** : 10 points par bonne réponse, 40 par leçon validée, 30 pour un sans-faute, 200 par examen réussi, 50 par défi du jour.

  | Titre | Points |
  |---|---|
  | Catéchumène | 0 |
  | Fidèle | 400 |
  | Psalte | 1 200 |
  | Lecteur | 2 500 |
  | Sous-diacre | 5 000 |
  | Diacre | 9 000 |
  | Archidiacre | 15 000 |
  | Catéchiste | 24 000 |
  | Théologien | 36 000 |
  | Colonne de la foi | 50 000 |

- **Collection** : chaque leçon validée débloque 2 à 4 fiches (saints, Pères, papes, conciles, hérésies, lieux, notions, prières, objets, livres, événements, mots coptes).
- **Série de jours**, et « Aujourd'hui dans l'Église » sur l'accueil (date copte, jour Adam ou Watos, jeûne).

## Les widgets de l'écran verrouillé

Sur l'iPhone : appui long sur l'écran verrouillé > Personnaliser > Écran verrouillé > ajouter un widget > Nofri.

| Widget | Format | Ce qu'il montre |
|---|---|---|
| Aujourd'hui dans l'Église | rectangle, ou ligne au-dessus de l'heure | date copte, jour Adam ou Watos, jeûne ; à partir de 18 h, la théotokie du lendemain |
| À retenir | rectangle | une phrase « À retenir » d'une leçon déjà validée, qui change toutes les heures |
| Série | rond | les jours d'affilée, avec une coche quand la leçon du jour est faite |

L'app écrit ces données dans l'App Group (`NofriWidgetData`) à chaque retour sur l'accueil.

## Comment c'est fait

- **Même dépôt, même code que Quinze.** La cible `Nofri` de `project.yml` compile `App/Sources` avec la condition `NOFRI`, plus le dossier `Nofri/Sources`. Le moteur, les séances, le blocage et les réglages sont partagés.
- **Ce qui change avec `NOFRI` :**
  - une seule matière, `Subject.church` (`Subject.studyOrder`, `Subject.primary`) ;
  - les onglets (`NofriTabView`) : Accueil, Parcours, Collection, Progrès ;
  - l'accueil (`HomeView`) reçoit le titre et les points, « Aujourd'hui dans l'Église », « Continuer le chemin » et le « Défi du jour » ;
  - les réglages du moteur (`AppEnvironment.engineConfiguration`) : 90 %, 4 leçons par jour, examen de 20 questions ;
  - l'accueil de bienvenue passe directement aux horaires (pas de test de niveau).
- **Identifiants à part** : `<préfixe>.nofri`, `.nofri.monitor`, `.nofri.shieldconfig`, `.nofri.shieldaction`, `.nofri.widget`, et l'App Group `group.<préfixe>.nofri`. Les deux apps ne partagent aucune donnée.
- **Leçons guidées (format 3).**
  - Un exercice porte `step` = le numéro de la carte qu'il suit. Les exercices sans `step` forment l'entraînement.
  - `SessionPlanner.planGuided` construit la séance : rappels, puis carte et questions d'étape, puis entraînement.
  - L'examen de chapitre pioche dans les questions d'entraînement.
  - Le validateur (`tools/build_content.py`, modules `"format": 3`) vérifie que chaque carte a 1 ou 2 questions d'étape dont la réponse est écrite sur la carte.
- **Contenu** : `Content/eg/source/mNN/`, règles dans `Content/eg/BRIEF-V4.md`, leçon modèle dans `Content/eg/EXEMPLE/`. La première version est archivée dans `Content/eg/v1/`. Le fichier embarqué est `Nofri/Resources/Content/eg.json`.

```bash
python3 tools/build_content.py --lang eg --module m04   # vérifier un chapitre
python3 tools/build_content.py --lang eg                # tout construire
```

## Installer

1. **Une seule fois, sur developer.apple.com > Certificates, Identifiers & Profiles > Identifiers** (Apple ne permet pas de le faire automatiquement) :
   - crée l'App Group `group.<préfixe>.nofri` (menu en haut à droite : App Groups, puis « + ») ;
   - lance une première fois le workflow (étape 2) : il crée les cinq identifiants, puis échoue à la signature, c'est normal ;
   - ouvre chacun des cinq identifiants `…nofri`, `.nofri.monitor`, `.nofri.shieldconfig`, `.nofri.shieldaction`, `.nofri.widget` : coche **App Groups**, « Configure », choisis `group.<préfixe>.nofri` ; coche **Family Controls (Development)** sur les quatre premiers (pas le widget) ; « Save ».
2. Sur GitHub : Actions > « Installer sur mon iPhone » > Run workflow > app **Nofri**. Le lien Diawi s'affiche à la fin.
3. Ouvre le lien sur l'iPhone et installe. Quinze reste installée à côté, avec sa progression.
