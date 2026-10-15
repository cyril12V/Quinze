# Brief de rédaction du corpus anglais (V1)

Tu rédiges le contenu pédagogique d'**un module** de l'application « Quinze » : apprentissage de l'anglais pour des **francophones** débutants à pré-intermédiaires (A1–A2), en 3 sessions de 5 minutes par jour. La qualité pédagogique est le cœur du produit : un contenu faux, ambigu ou une bonne réponse refusée est un bug grave.

À lire avant d'écrire :
1. `Content/SCHEMA.md` — format exact des fichiers (obligatoire).
2. `Content/en/curriculum.json` — modules, notions (avec `functionWords`), leçons et vocabulaire de **chaque** leçon. Ne modifie pas ce fichier.
3. Cahier des charges : `/mnt/user-data/uploads/attachment.txt`, sections 7 à 12 (programme, types d'exercices, correction, professeur, dictionnaire, répétition espacée).

## Ce que tu produis

Dans `Content/en/source/mNN/` (NN = ton module) :
- `units.json` : la règle complète de chaque notion de grammaire **de ton module**.
- `dictionary.json` : une fiche pour **chaque mot de vocabulaire** de tes leçons **et chaque mot-outil** (`functionWords`) de tes notions.
- `lessons/lXX.json` : un fichier par leçon de ton module, **10 exercices** chacun.
- `diagnostic.json` : 5 questions de positionnement.
- `assessment.json` : 5 questions d'évaluation périodique (inédites).

Puis lance `python3 tools/build_content.py --lang en --module mNN` depuis `/home/claude/quinze` et corrige jusqu'à obtenir `Module OK.` Les avertissements (`WARN`) doivent être examinés et corrigés quand ils sont justifiés.

## Exigences pédagogiques

**Progression.** Une leçon n'utilise que la grammaire déjà introduite (leçons précédentes + la sienne) et surtout le vocabulaire déjà introduit. Quelques mots très courants hors liste sont tolérés quand c'est naturel (prénoms Tom, Anna, Sam, Lucy, Ben, Emma ; London, Paris ; mots transparents). Le vocabulaire de la leçon apparaît dans des phrases utiles et naturelles. Réutilise volontairement des mots des leçons précédentes (le vocabulaire doit vivre dans les leçons de grammaire, §7.2).

**Variété.** 10 exercices par leçon avec la répartition imposée (2 QCM, 2 phrases à compléter, 2 traductions, 1 remise en ordre, 1 association, 2 réponses libres). Jamais deux fois la même phrase ; contextes variés (maison, travail, amis, voyage…). Difficulté progressive dans la leçon (reconnaissance → rappel → production). Les leçons « de pratique » (`introducesGrammar: false`) reprennent la notion avec de nouveaux contextes et le nouveau vocabulaire.

**Explications (français, tutoiement, simples).** Pour chaque exercice :
- `explanation` : *pourquoi* la bonne réponse est correcte et quelle règle s'applique (1 à 3 phrases, sans jargon inutile ; si un terme technique est nécessaire, l'expliquer).
- `tip` : comment éviter l'erreur, en une phrase mémorisable.
- `extraExample` : la même règle dans un autre contexte, avec sa traduction.
- `hint` (facultatif) : un coup de pouce qui ne donne pas la réponse.
- `errorPatterns` : 1 à 3 erreurs prévisibles avec un retour ciblé (mauvaises options de QCM, pièges des francophones : « I am agree », « She don't », « I have 20 years », « He go », « the life is beautiful », confusion make/do, since/for, etc.). Le retour dit *ce qui ne va pas* et *quoi faire*.

Modèle à suivre (§9.2) — `She doesn't ___ to school.` réponse `go` ; pattern `{"equals": "goes", "category": "conjugation", "feedback": "Après doesn't, le verbe reste à sa forme de base : le -s est déjà dans does."}` ; explanation « Après doesn't, le verbe reste à sa forme de base. On utilise donc go et non goes. » ; tip « Le -s est déjà présent dans does : on ne l'ajoute pas une seconde fois au verbe. » ; extraExample « He doesn't work today. / Il ne travaille pas aujourd'hui. »

**Une seule bonne réponse, ou toutes acceptées.** Principe non négociable (§27-8) : une réponse correcte ne doit jamais être refusée.
- QCM : une seule option correcte, sans ambiguïté ; les distracteurs sont plausibles (erreurs typiques).
- Phrase à compléter : le contexte doit imposer la réponse (ex. « Yesterday, I ___ to school. » avec `went`). Si plusieurs mots conviennent, liste-les tous dans `acceptedAnswers`.
- Traductions et réponses libres : liste **toutes** les traductions correctes raisonnables (synonymes, ordre des adverbes, présent simple / continu quand le français est ambigu, « at home » / « home », « mum » / « mom »…). Le moteur gère déjà majuscules, ponctuation, contractions (doesn't = does not, I'm = I am…), chiffres 0–20 : inutile de dupliquer ces variantes.
- Évite les phrases françaises ambiguës : « Je mange » peut être *I eat* ou *I'm eating* → ajoute un marqueur (« tous les jours », « en ce moment ») ou accepte les deux. Pour « tu/vous », les deux donnent *you*. Précise le genre si nécessaire (« Il… », « Elle… »).
- Remise en ordre : phrases sans ponctuation interne (pas de virgule), `tokens` = les mots exacts, et liste les autres ordres corrects.
- Anglais britannique par défaut ; accepte la variante américaine quand elle existe.

**Dictionnaire.** Prononciation API britannique standard entre `/ /`, explication d'une phrase, 2 exemples de contextes différents, confusions utiles seulement (through/though/thought, make/do, house/home, look/see/watch, say/tell, borrow/lend…), formes fléchies (verbes : thirdPerson, past, pastParticiple, ing ; noms irréguliers : plural ; adjectifs courts : comparative/superlative). Pour un mot-outil (`unitId: null`), l'explication décrit son usage grammatical.

**Règles (`units.json`).** `summary` en une phrase ; `explanation` en 2 à 6 phrases claires ; `pattern` (structure) ; 3–4 exemples traduits ; 2–3 erreurs courantes `{wrong, right, why}` ; une astuce. Exactitude grammaticale stricte.

**Diagnostic.** Questions rapides (10–20 s), une seule bonne réponse évidente pour qui maîtrise la notion, représentatives des notions du module. Niveau (`level`) imposé par module (voir SCHEMA). `topic` parmi la liste autorisée.

**Évaluation périodique.** Phrases et contextes **inédits** (ne pas réutiliser les phrases des leçons), majoritairement en rappel/production sans propositions.

## Relecture obligatoire avant de terminer

Relis chaque fichier en te posant ces questions : l'anglais est-il correct et naturel ? La traduction française est-elle juste ? Chaque QCM a-t-il exactement une bonne réponse ? Chaque trou est-il non ambigu ? Ai-je listé toutes les traductions correctes ? L'explication est-elle vraie, simple et utile ? Le niveau est-il adapté au module ? Corrige tout ce qui ne va pas, relance le validateur.

Ne modifie que les fichiers de ton module. Termine par un court compte rendu (comptes, choix notables, points de vigilance) sans recopier le contenu.
