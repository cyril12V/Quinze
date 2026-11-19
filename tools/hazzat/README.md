# Liste des chants de Hazzat

- `liste.txt` : la liste actuelle (v2), dans l'ordre des offices. `# Période`, `## Partie` (`##` seul = sans partie),
  `- Chant`. Un chant renommé s'écrit `- Nouveau nom <= Ancien nom` pour que la mise à jour le retrouve sur le téléphone.
- `liste-v1.txt` : la première liste, telle qu'elle a été installée (avec les ✅, qui ne sont plus affichés).

Régénérer `Hazzat/Resources/seed.json` (vérifie qu'aucun chant n'est perdu) :

    python3 -I tools/hazzat/build_seed.py tools/hazzat/liste-v1.txt tools/hazzat/liste.txt <(git show 415d61f:Hazzat/Resources/seed.json) Hazzat/Resources/seed.json

Vérifier la mise à jour d'une bibliothèque existante (même logique que `Library.reordered`) :

    python3 -I tools/hazzat/sim_migration.py <(git show 415d61f:Hazzat/Resources/seed.json) Hazzat/Resources/seed.json

Pour une future liste v3 : partir de `liste.txt`, augmenter `Library.seedVersion`, et faire pointer `from` vers la v2.
