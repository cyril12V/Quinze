# L'espace Église copte

Une app dans l'app. On l'ouvre depuis l'accueil de Quinze (carte « ⛪ Espace Église ») et on revient à Quinze par le bouton maison en haut à droite. L'espace est à part :
- il n'est pas lié aux créneaux ;
- il ne joue aucun rôle dans le blocage des apps ;
- il ne mélange rien avec l'anglais, l'arabe et la culture G.

Le but est d'apprendre un peu chaque jour pour avoir, dans un an, de vraies bases sur l'Église copte orthodoxe. Les mots d'ordre restent **ludique, compréhension, logique**.

## Ce qu'on y trouve

- **Accueil**
  - **Aujourd'hui dans l'Église**, en trois lignes :
    - la date copte, avec le nom arabe du mois ;
    - le jour Adam (dimanche à mardi) ou Watos (mercredi à samedi) ;
    - le jeûne en cours, ou « Pas de jeûne aujourd'hui ».
  - À partir de 18 h, une ligne de plus rappelle que l'Église entre déjà dans le lendemain : on prie la théotokie du lendemain (le samedi soir, celle du dimanche, sur l'air Adam).
  - **Séance du jour** : « Commencer » ou « Reprendre », et « Réviser encore » pour une séance de plus.
  - Le nombre de leçons validées et de révisions à faire.
- **Parcours, Lexique, Progrès** : les mêmes écrans que les matières de Quinze, réservés à l'Église.
- Une séance dure environ 8 minutes. Elle suit les mêmes règles que les autres matières :
  1. le cours d'abord, puis les questions ;
  2. une erreur revient jusqu'à être juste ;
  3. une leçon est validée à 80 % ;
  4. chaque module se termine par un contrôle (80 %) ;
  5. la répétition espacée fait revenir les notions la veille, une semaine après, etc.
- Tout est en français, sans voix.

## Le calendrier (code : `Packages/LearningCore/Sources/LearningCore/Calendar/CopticCalendar.swift`)

- **Date copte**
  - Elle est calculée par le jour julien (époque copte : JJ 1825030).
  - L'année commence le 1er Tout, c'est-à-dire le 11 septembre, ou le 12 l'année qui précède une année bissextile.
  - Le 13e mois, Nasie, a 5 ou 6 jours.
- **Pâques** : comput alexandrin (date julienne), par exemple 12 avril 2026 et 2 mai 2027.
- **Jeûnes**, par ordre de priorité :
  1. Les cinquante jours après Pâques : pas de jeûne.
  2. La semaine sainte.
  3. Le Grand Carême (55 jours avant Pâques).
  4. Ninive (69 à 67 jours avant Pâques).
  5. Les Apôtres (du lendemain de la Pentecôte au 4 Abib).
  6. La Vierge (1er au 15 Misra).
  7. La Nativité (25 novembre au 6 janvier).
  8. Le mercredi et le vendredi, sauf le 7 et le 19 janvier.
- Les tests sont dans `CopticCalendarTests.swift`.

## Le programme

Les sources sont :
- les six documents de cours de l'utilisateur (histoire des cinq premiers siècles et groupes récents) ;
- des faits bien établis (st-takla.org, copticchurch.net, suscopts.org, tasbeha.org).

Les consignes de rédaction sont dans `Content/eg/BRIEF-EGLISE.md`, les notes vérifiées sur la prière dans `Content/eg/NOTES-PRIERE.md`.

| Module | Leçons | Contenu |
|---|---|---|
| m01 | 1–8 | Le premier siècle : Pentecôte, Paul, concile de Jérusalem, persécutions, apôtres, saint Marc et Alexandrie |
| m02 | 9–16 | Le deuxième siècle : sièges apostoliques, Pères apostoliques, apologistes, gnosticisme, Marcion, Montan, canon |
| m03 | 17–24 | Le troisième siècle : persécutions (Dèce, Dioclétien, ère des martyrs), premiers ermites, Paul de Samosate, Sabellius, Novatien, Mani |
| m04 | 25–32 | Le quatrième siècle : Constantin, Arius, Nicée, saint Athanase, monachisme, Constantinople |
| m05 | 33–44 | Le cinquième siècle : Nestorius, saint Cyrille, Éphèse, Eutychès, Chalcédoine, saint Dioscore, miaphysisme |
| m06 | 45–52 | Conciles et hérésies : la synthèse |
| m07 | 53–60 | Ce qui nous sépare : orthodoxes chalcédoniens, catholiques, protestants, groupes récents |
| m08 | 61–68 | Le Credo, article par article |
| m09 | 69–76 | Les sept sacrements |
| m10 | 77–82 | L'église et le clergé |
| m11 | 83–88 | L'Agpeya et la prière (le sens des heures, prier vers l'est) |
| m12 | 89–94 | La tasbeha (hoos, psalis, théotokies, Adam et Watos) |
| m13 | 95–98 | Les mois coptes (prévu) |
| m14 | 99–110 | Les saints : qui a fait quoi (prévu) |
| m15 | 111– | La langue copte : règles et sens des mots (prévu) |

Pour construire le contenu :
- vérifier un module : `python3 tools/build_content.py --lang eg --module m05` ;
- tout construire : `python3 tools/build_content.py --lang eg`, qui écrit `App/Resources/Content/eg.json` et `supabase/seed/content_eg.sql`.

Pas de chants ni de textes liturgiques à apprendre. Le Credo est la seule exception, à la demande de l'utilisateur.

## Les lettres coptes

Les polices Plus Jakarta Sans de l'app contiennent aussi les lettres coptes de Noto Sans Coptic, fusionnées avec fontTools (licence OFL, voir `App/Resources/Fonts/NotoSansCoptic-OFL.txt`). Le copte (ⲁ ⲃ ⲅ… ϣ ϥ ϧ ϩ ϫ ϭ ϯ, jinkim, surlignes) s'affiche donc partout, dans la police de l'app, sans code particulier.
