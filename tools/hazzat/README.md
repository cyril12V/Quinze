# Liste des chants de Hazzat

- `liste.txt` : la liste actuelle (v3). `# Période`, `@group Messe` (période rangée sous une carte « Messe »),
  `@was Ancien nom`, `## Partie`, puis les chants :
  - `- Chant` : chant de la v2, retrouvé par son nom dans la même période ;
  - `- Nouveau nom <= Ancien nom` : chant renommé ;
  - `- Chant @ Autre période` : chant qui vient d'une autre période (ex. les cantiques franco de Kiahk) ;
  - `+ Chant` : chant ajouté (sans feuille).
- `liste-v2.txt`, `seed-v2.json` : la liste v2 telle qu'installée sur les téléphones (référence de la migration).
- `liste-v1.txt` : la toute première liste.

Régénérer `Hazzat/Resources/seed.json` (vérifie qu'aucun chant de la v2 n'est perdu) :

    python3 -I tools/hazzat/build_seed_v3.py tools/hazzat/liste-v2.txt tools/hazzat/liste.txt tools/hazzat/seed-v2.json Hazzat/Resources/seed.json

Vérifier la mise à jour d'une bibliothèque existante (même logique que `Library.migrated`) :

    python3 -I tools/hazzat/sim_migration.py tools/hazzat/seed-v2.json Hazzat/Resources/seed.json

Ordre des offices suivi : tasbeha.org (Hymn Library) — encens (versets des cymbales → doxologies → évangile →
répons), liturgie du Verbe (Hiten → Pavlos + répons → Katholikon + répons → Praxis + répons → Agios → psaume →
évangile), liturgie des croyants (aspasmos → anaphore → confession), distribution (psaume 150, hymnes).
