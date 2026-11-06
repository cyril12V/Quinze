# Église copte : brief du contenu

L'espace « Église » de Quinze est une app dans l'app, à part des créneaux et du blocage. On y apprend un peu tous les jours, pour avoir dans un an de vraies bases sur l'Église copte orthodoxe. Code de la matière : `eg`, identifiants `eg.…`.

## L'apprenant

Copte orthodoxe égyptien, francophone, adulte, pratiquant : il connaît déjà la messe et les fêtes.

- Il veut comprendre son Église dans sa globalité : histoire, conciles, hérésies, foi, sacrements, Agpeya, tasbeha, saints, copte.
- Il ne veut ni chants ni textes de la liturgie à apprendre.
- Ses mots d'ordre : **ludique, compréhension, logique**. On raconte, on explique le pourquoi, on relie les faits.

## Format

C'est le même format que la culture G :

- `Content/BRIEF-V2.md` pour les fichiers et les exercises ;
- `Content/BRIEF-V3.md` §1 pour le cours ;
- `Content/SCHEMA.md` pour les champs.

Ce qui est propre à l'Église :

- **Langue et identifiants :** tout en français, avec « tu ». `promptLanguage: "fr"` (ou `"cop"` pour un mot copte à traduire, modules de copte uniquement). Identifiants `eg.lNN`, `eg.gNN.slug`, `eg.v.slug`, `eg.d.slug`.
- **Le cours d'abord :** chaque leçon commence par 5 à 9 cartes (`course/lSEQ.json`). Les questions ne portent que sur ce que le cours enseigne, et le validateur le vérifie.
- **Taille des leçons :** 18 à 24 exercises par leçon.

  | Type | Nombre par leçon |
  |---|---|
  | mcq | 6–12 |
  | fill_blank | 2–6 |
  | match | 2–5 |
  | reorder | 0–3 |
  | free_answer | 1–4 |
  | translation | 0–4 (copte → français) |

- **Vocabulaire :** les personnes, conciles, hérésies, lieux, notions et dates de la leçon. `partOfSpeech` vaut `person`, `event`, `concept`, `place`, `date`, `work` ou `organization`. Un slug n'est introduit qu'une fois dans toute la matière.
- **Révisions :** 3 à 5 exercises de révision par leçon, sur les leçons précédentes.
- **Contrôle de fin de module :** il est automatique (80 % pour passer au module suivant). Les leçons doivent le préparer.

## Point de vue et exactitude

- **Le point de vue de l'Église copte orthodoxe :**
  - l'Église d'Alexandrie fondée par saint Marc ;
  - la christologie miaphysite de saint Cyrille (« une seule nature du Verbe incarné »), qu'on ne confond pas avec le monophysisme d'Eutychès, que l'Église copte condamne aussi ;
  - Chalcédoine (451) rejeté ;
  - saint Dioscore vénéré comme confesseur.
- **Les autres Églises et groupes sont décrits avec respect et exactitude**, sans polémique : ce qu'ils croient, ce qui nous sépare, pourquoi.
- **Seulement les dates qui comptent** (conciles, grands Pères, persécutions, schismes), arrondies si la date exacte est discutée (« vers 250 »).
- **Sources :**
  - les documents de cours de l'apprenant, dont le texte extrait est dans `/tmp/claude-0/-home-claude/3cfe2213-1053-5f48-a6b0-3f9850e7973e/scratchpad/eglise_pdfs/` (les PDF sont dans `/mnt/user-data/attachments/3cfe2213-1053-5f48-a6b0-3f9850e7973e/`) ;
  - pour compléter, des faits bien établis, vérifiables sur st-takla.org, copticchurch.net ou suscopts.org.

  Si un document affirme quelque chose de douteux, ne pose pas de question dessus et signale-le dans ton rapport.
- **Pas de copie :** on reformule les documents en cartes claires, sans recopier de longs passages. Une citation biblique courte est permise.

## Programme

| Module | Leçons | Contenu |
|---|---|---|
| m01 | 1–8 | Le premier siècle (et pourquoi étudier l'histoire de l'Église) |
| m02 | 9–16 | Le deuxième siècle : Pères apostoliques, apologistes, premières hérésies |
| m03 | 17–24 | Le troisième siècle : École d'Alexandrie, persécutions, martyrs |
| m04 | 25–32 | Le quatrième siècle : Constantin, Arius, Nicée, saint Athanase, monachisme, Constantinople |
| m05 | 33–44 | Le cinquième siècle : Nestorius, Éphèse, Eutychès, Chalcédoine, l'orthodoxie copte |
| m06 | 45–52 | Conciles et hérésies : la synthèse |
| m07 | 53–60 | Orthodoxes, catholiques, protestants et groupes récents : ce qui nous sépare |

Modules suivants :

| Module | Leçons | Contenu |
|---|---|---|
| m08 | 61–68 | Le Credo, article par article : ce qu'on dit, pourquoi, contre quelle erreur |
| m09 | 69–76 | Les 7 sacrements |
| m10 | 77–82 | L'église (le bâtiment et ses symboles) et le clergé |
| m11 | 83–88 | L'Agpeya et la prière : le sens des heures, les gestes, prier vers l'est |
| m12 | 89–94 | La tasbeha : hoos, psalis, théotokies, jours Adam et Watos, le soir = le lendemain |
| m13 | 95–98 | Les mois coptes et le calendrier (pas les fêtes) |
| m14 | 99–110 | Les saints : qui a fait quoi |
| m15 | 111– | La langue copte : règles et sens des mots (police copte à embarquer) |

Pour m11 et m12, les faits vérifiés sont dans `Content/eg/NOTES-PRIERE.md`.
