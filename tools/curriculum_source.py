"""Source of truth for the English V1 curriculum outline.

Run `python3 tools/curriculum_source.py` to regenerate Content/en/curriculum.json.
The outline fixes: modules, grammar notions (with prerequisites), the 60 lessons
and the vocabulary each lesson introduces. Detailed content (rules, exercises,
dictionary entries) lives in Content/en/source/ and is merged by build_content.py.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

MODULES = [
    (1, "Fondations", "Pronoms, articles, to be, to have, possessifs, pluriel, nombres."),
    (2, "Verbes essentiels", "Do, go, get, make, take, give, know, think, want, need, can, must, impératif."),
    (3, "Présent", "Présent simple (3e personne, do/does, don't/doesn't), adverbes de fréquence, présent continu."),
    (4, "Passé", "Was/were, verbes réguliers et irréguliers, did/didn't."),
    (5, "Futur", "Will, going to, intentions, prédictions, projets."),
    (6, "Vocabulaire courant", "Maison, restaurant, achats, transport, voyage, heure et nombres."),
    (7, "Construction de phrases", "Ordre des mots, prépositions, questions, connecteurs, comparatifs, modaux."),
    (8, "Consolidation", "Present perfect, expressions courantes, choix des temps, compréhension et production."),
]

# id, slug, title, category, difficulty, prerequisites (ids), module, functionWords
G = {}
def g(num, slug, title, category, difficulty, prereq, module, fw=()):
    gid = f"en.g{num:02d}.{slug}"
    G[num] = dict(id=gid, kind="grammar", category=category, title=title,
                  difficulty=difficulty, prerequisites=[G[p]["id"] for p in prereq],
                  module=module, functionWords=list(fw))

g(1, "subject_pronouns", "Les pronoms personnels sujets", "grammar", 1, [], 1, ["I", "you", "he", "she", "it", "we", "they"])
g(2, "articles", "Les articles : a, an, the", "grammar", 1, [], 1, ["a", "an", "the"])
g(3, "be_affirmative", "Le verbe to be : forme affirmative", "verbs", 1, [1], 1, ["be", "am", "is", "are"])
g(4, "be_negative_questions", "To be : négation et questions", "verbs", 1, [3], 1, ["not", "isn't", "aren't"])
g(5, "have_has", "Le verbe to have : have / has", "verbs", 1, [1], 1, ["have", "has"])
g(6, "possessive_adjectives", "Les adjectifs possessifs", "grammar", 1, [1], 1, ["my", "your", "his", "her", "its", "our", "their"])
g(7, "plural_nouns", "Le pluriel des noms", "grammar", 1, [2], 1, [])
g(8, "verbs_base_form", "Les verbes essentiels avec I, you, we, they", "verbs", 1, [1], 2, [])
g(9, "do_vs_make", "Do ou make ?", "verbs", 2, [8], 2, [])
g(10, "want_need_to", "Want / need + to + verbe", "verbs", 2, [8], 2, ["to"])
g(11, "can", "Can / can't : capacité et permission", "verbs", 1, [8], 2, ["can", "can't", "cannot"])
g(12, "must", "Must / mustn't : obligation et interdiction", "verbs", 2, [11], 2, ["must", "mustn't"])
g(13, "imperative", "L'impératif : Go! / Don't go!", "verbs", 1, [8], 2, ["let's"])
g(14, "present_simple_third_person", "Présent simple : la 3e personne (-s)", "verbs", 2, [8, 1], 3, [])
g(15, "present_simple_negative", "Présent simple : don't / doesn't", "verbs", 2, [14], 3, ["does", "don't", "doesn't"])
g(16, "present_simple_questions", "Présent simple : questions avec do / does", "verbs", 2, [15], 3, [])
g(17, "frequency_adverbs", "Les adverbes de fréquence", "grammar", 2, [14], 3, ["always", "usually", "often", "sometimes", "rarely", "never"])
g(18, "present_continuous", "Le présent continu (be + -ing)", "verbs", 2, [3], 3, [])
g(19, "simple_vs_continuous", "Présent simple ou présent continu ?", "verbs", 3, [16, 18], 3, [])
g(20, "was_were", "Le passé de to be : was / were", "verbs", 2, [4], 4, ["was", "were", "wasn't", "weren't"])
g(21, "past_simple_regular", "Passé simple : verbes réguliers (-ed)", "verbs", 2, [14], 4, [])
g(22, "irregular_verbs", "Passé simple : verbes irréguliers fréquents", "verbs", 3, [21], 4, [])
g(23, "past_simple_negative_questions", "Passé simple : did / didn't", "verbs", 3, [22, 16], 4, ["did", "didn't"])
g(24, "will_future", "Le futur avec will", "verbs", 2, [8], 5, ["will", "won't"])
g(25, "going_to", "Le futur avec going to", "verbs", 2, [18], 5, ["going to"])
g(26, "will_vs_going_to", "Will ou going to ?", "verbs", 3, [24, 25], 5, [])
g(27, "present_continuous_future", "Le présent continu pour les projets fixés", "verbs", 3, [25], 5, [])
g(28, "there_is_are", "There is / there are", "grammar", 2, [7, 4], 6, ["there"])
g(29, "some_any", "Some / any", "grammar", 2, [28], 6, ["some", "any"])
g(30, "how_much_many", "How much / how many", "grammar", 2, [29], 6, ["much", "many", "a lot of"])
g(31, "time_and_dates", "Dire l'heure et la date", "grammar", 2, [4], 6, ["o'clock", "quarter"])
g(32, "word_order", "L'ordre des mots dans la phrase", "sentence_building", 2, [14], 7, [])
g(33, "prepositions_place", "Les prépositions de lieu", "sentence_building", 2, [28], 7, ["in", "on", "at", "under", "next to", "between", "behind", "in front of"])
g(34, "prepositions_time", "Les prépositions de temps : in, on, at", "sentence_building", 2, [31], 7, ["before", "after", "during"])
g(35, "question_words", "Les mots interrogatifs", "sentence_building", 2, [16, 23], 7, ["what", "where", "when", "who", "why", "how", "which"])
g(36, "connectors", "Les connecteurs : and, but, because, so…", "sentence_building", 2, [14], 7, ["and", "but", "or", "because", "so", "then"])
g(37, "comparatives_superlatives", "Comparatifs et superlatifs", "grammar", 3, [4], 7, ["than", "more", "most"])
g(38, "should_could", "Should / could : conseils et demandes polies", "verbs", 3, [11], 7, ["should", "could", "would"])
g(39, "present_perfect_intro", "Le present perfect : introduction", "verbs", 4, [22], 8, ["been"])
g(40, "short_answers", "Réponses courtes et reprises (Yes, I do / Me too)", "sentence_building", 3, [16, 23], 8, ["too", "either"])
g(41, "tense_contrast", "Choisir le bon temps", "verbs", 4, [19, 23, 26, 39], 8, [])

# Lessons: (seq, module, title, description, grammar_num, introduces_grammar, vocab[(en, fr, pos)])
L = [
 (1, 1, "Je, tu, il, elle…", "Les pronoms sujets et les premiers mots de politesse.", 1, True,
  [("hello", "bonjour", "interjection"), ("goodbye", "au revoir", "interjection"), ("thank you", "merci", "expression"), ("please", "s'il te plaît / s'il vous plaît", "adverb"), ("sorry", "désolé", "adjective")]),
 (2, 1, "Un, une, le, la", "Les articles a, an et the.", 2, True,
  [("man", "homme", "noun"), ("woman", "femme", "noun"), ("child", "enfant", "noun"), ("friend", "ami / amie", "noun"), ("name", "nom, prénom", "noun")]),
 (3, 1, "Être : I am, you are", "Le verbe to be à la forme affirmative.", 3, True,
  [("happy", "heureux, content", "adjective"), ("tired", "fatigué", "adjective"), ("ready", "prêt", "adjective"), ("student", "étudiant, élève", "noun"), ("teacher", "professeur, enseignant", "noun")]),
 (4, 1, "Ma famille", "Pratique de to be avec le vocabulaire de la famille.", 3, False,
  [("mother", "mère", "noun"), ("father", "père", "noun"), ("brother", "frère", "noun"), ("sister", "sœur", "noun"), ("family", "famille", "noun")]),
 (5, 1, "Je ne suis pas… Es-tu… ?", "To be à la forme négative et interrogative.", 4, True,
  [("late", "en retard", "adjective"), ("busy", "occupé", "adjective"), ("hungry", "qui a faim", "adjective"), ("cold", "froid", "adjective"), ("right", "juste, correct (avoir raison)", "adjective")]),
 (6, 1, "Avoir : have / has", "Le verbe to have et la possession.", 5, True,
  [("car", "voiture", "noun"), ("house", "maison (le bâtiment)", "noun"), ("home", "chez soi, foyer", "noun"), ("dog", "chien", "noun"), ("phone", "téléphone", "noun")]),
 (7, 1, "Mon, ton, son…", "Les adjectifs possessifs.", 6, True,
  [("son", "fils", "noun"), ("daughter", "fille (enfant)", "noun"), ("husband", "mari", "noun"), ("wife", "femme, épouse", "noun"), ("parents", "parents (père et mère)", "noun")]),
 (8, 1, "Un livre, des livres", "Le pluriel des noms, réguliers et irréguliers.", 7, True,
  [("book", "livre", "noun"), ("bag", "sac", "noun"), ("key", "clé", "noun"), ("school", "école", "noun"), ("people", "gens, personnes", "noun")]),
 (9, 1, "Révision des fondations et nombres", "Révision de to be, have, possessifs et pluriel ; les nombres de 1 à 10.", 7, False,
  [("one", "un", "number"), ("two", "deux", "number"), ("three", "trois", "number"), ("four", "quatre", "number"), ("five", "cinq", "number"),
   ("six", "six", "number"), ("seven", "sept", "number"), ("eight", "huit", "number"), ("nine", "neuf", "number"), ("ten", "dix", "number")]),
 (10, 2, "Les verbes essentiels", "Go, do, make, take, give avec I, you, we, they.", 8, True,
  [("go", "aller", "verb"), ("do", "faire", "verb"), ("make", "faire, fabriquer", "verb"), ("take", "prendre", "verb"), ("give", "donner", "verb")]),
 (11, 2, "Do ou make ?", "Choisir entre do et make.", 9, True,
  [("homework", "devoirs", "noun"), ("mistake", "erreur", "noun"), ("dinner", "dîner", "noun"), ("decision", "décision", "noun"), ("coffee", "café", "noun")]),
 (12, 2, "Vouloir et avoir besoin", "Want / need + to + verbe ; get, know, think.", 10, True,
  [("get", "obtenir, recevoir, devenir", "verb"), ("know", "savoir, connaître", "verb"), ("think", "penser, croire", "verb"), ("want", "vouloir", "verb"), ("need", "avoir besoin de", "verb")]),
 (13, 2, "Je peux, je sais faire", "Can / can't pour la capacité.", 11, True,
  [("swim", "nager", "verb"), ("drive", "conduire", "verb"), ("speak", "parler (une langue)", "verb"), ("English", "anglais (langue)", "noun"), ("French", "français (langue)", "noun")]),
 (14, 2, "Peux-tu m'aider ?", "Can pour demander et donner une permission.", 11, False,
  [("help", "aider", "verb"), ("read", "lire", "verb"), ("write", "écrire", "verb"), ("door", "porte", "noun"), ("window", "fenêtre", "noun")]),
 (15, 2, "Il faut, il ne faut pas", "Must / mustn't pour l'obligation et l'interdiction.", 12, True,
  [("stop", "arrêter, s'arrêter", "verb"), ("wait", "attendre", "verb"), ("open", "ouvrir", "verb"), ("close", "fermer", "verb"), ("careful", "prudent, attentif", "adjective")]),
 (16, 2, "Donner des consignes", "L'impératif affirmatif et négatif.", 13, True,
  [("come", "venir", "verb"), ("look", "regarder", "verb"), ("listen", "écouter", "verb"), ("sit down", "s'asseoir", "phrasal_verb"), ("stand up", "se lever (debout)", "phrasal_verb")]),
 (17, 2, "Révision des verbes", "Révision des verbes essentiels avec I, you, we, they.", 8, False,
  [("work", "travailler", "verb"), ("live", "habiter, vivre", "verb"), ("like", "aimer (bien)", "verb"), ("love", "aimer, adorer", "verb"), ("eat", "manger", "verb")]),
 (18, 3, "Il travaille, elle joue", "Présent simple : le -s de la 3e personne.", 14, True,
  [("drink", "boire", "verb"), ("play", "jouer", "verb"), ("watch", "regarder (un écran, un match)", "verb"), ("sleep", "dormir", "verb"), ("cook", "cuisiner", "verb")]),
 (19, 3, "Watches, studies, has", "Orthographe de la 3e personne : -es, -ies et formes irrégulières.", 14, False,
  [("study", "étudier", "verb"), ("finish", "finir, terminer", "verb"), ("teach", "enseigner", "verb"), ("carry", "porter (transporter)", "verb"), ("fix", "réparer", "verb")]),
 (20, 3, "Je ne mange pas de viande", "Présent simple négatif : don't / doesn't.", 15, True,
  [("food", "nourriture", "noun"), ("meat", "viande", "noun"), ("fish", "poisson", "noun"), ("milk", "lait", "noun"), ("water", "eau", "noun")]),
 (21, 3, "Est-ce que tu… ?", "Présent simple : questions avec do / does et réponses courtes.", 16, True,
  [("breakfast", "petit-déjeuner", "noun"), ("lunch", "déjeuner", "noun"), ("morning", "matin", "noun"), ("evening", "soir, soirée", "noun"), ("night", "nuit", "noun")]),
 (22, 3, "Toujours, souvent, jamais", "Les adverbes de fréquence et leur place.", 17, True,
  [("day", "jour, journée", "noun"), ("weekend", "week-end", "noun"), ("early", "tôt", "adverb"), ("music", "musique", "noun"), ("gym", "salle de sport", "noun")]),
 (23, 3, "Ma journée", "La routine quotidienne au présent simple.", 17, False,
  [("wake up", "se réveiller", "phrasal_verb"), ("get up", "se lever (du lit)", "phrasal_verb"), ("go to bed", "aller se coucher", "expression"), ("take a shower", "prendre une douche", "expression"), ("have breakfast", "prendre le petit-déjeuner", "expression")]),
 (24, 3, "En ce moment", "Le présent continu : be + verbe en -ing.", 18, True,
  [("now", "maintenant", "adverb"), ("rain", "pleuvoir ; pluie", "verb"), ("wear", "porter (un vêtement)", "verb"), ("talk", "parler, discuter", "verb"), ("laugh", "rire", "verb")]),
 (25, 3, "Qu'est-ce que tu fais ?", "Présent continu : négation et questions.", 18, False,
  [("call", "appeler", "verb"), ("use", "utiliser", "verb"), ("sing", "chanter", "verb"), ("dance", "danser", "verb"), ("laptop", "ordinateur portable", "noun")]),
 (26, 3, "Habitude ou moment présent ?", "Choisir entre présent simple et présent continu.", 19, True,
  [("today", "aujourd'hui", "adverb"), ("tonight", "ce soir", "adverb"), ("at the moment", "en ce moment", "expression"), ("office", "bureau (lieu de travail)", "noun"), ("colleague", "collègue", "noun")]),
 (27, 4, "J'étais, nous étions", "Le passé de to be : was / were.", 20, True,
  [("yesterday", "hier", "adverb"), ("last", "dernier (last week = la semaine dernière)", "adjective"), ("ago", "il y a (two days ago)", "adverb"), ("born", "né (to be born)", "adjective"), ("week", "semaine", "noun")]),
 (28, 4, "J'ai marché, j'ai visité", "Passé simple des verbes réguliers en -ed.", 21, True,
  [("walk", "marcher", "verb"), ("visit", "visiter, rendre visite", "verb"), ("stay", "rester, séjourner", "verb"), ("start", "commencer", "verb"), ("travel", "voyager", "verb")]),
 (29, 4, "Les verbes en -ed", "Orthographe et prononciation des verbes réguliers au passé.", 21, False,
  [("arrive", "arriver", "verb"), ("decide", "décider", "verb"), ("ask", "demander", "verb"), ("answer", "répondre", "verb"), ("clean", "nettoyer", "verb")]),
 (30, 4, "Went, saw, said", "Les verbes irréguliers les plus fréquents.", 22, True,
  [("see", "voir", "verb"), ("say", "dire", "verb"), ("tell", "dire (à quelqu'un), raconter", "verb"), ("find", "trouver", "verb"), ("put", "mettre, poser", "verb")]),
 (31, 4, "Bought, left, met", "D'autres verbes irréguliers fréquents.", 22, False,
  [("buy", "acheter", "verb"), ("leave", "partir, quitter", "verb"), ("meet", "rencontrer, retrouver", "verb"), ("forget", "oublier", "verb"), ("begin", "commencer", "verb")]),
 (32, 4, "Tu es allé où ?", "Passé simple : did / didn't, questions et négations.", 23, True,
  [("holiday", "vacances", "noun"), ("beach", "plage", "noun"), ("hotel", "hôtel", "noun"), ("trip", "voyage, excursion", "noun"), ("weather", "temps (météo)", "noun")]),
 (33, 4, "La fête d'hier", "Raconter un événement passé.", 23, False,
  [("party", "fête", "noun"), ("birthday", "anniversaire", "noun"), ("present", "cadeau", "noun"), ("cake", "gâteau", "noun"), ("invite", "inviter", "verb")]),
 (34, 4, "Raconter une histoire", "Révision du passé : was/were, réguliers, irréguliers, did.", 23, False,
  [("story", "histoire (récit)", "noun"), ("happen", "se passer, arriver", "verb"), ("lose", "perdre", "verb"), ("win", "gagner", "verb"), ("feel", "se sentir, ressentir", "verb")]),
 (35, 5, "Demain, je…", "Le futur avec will : prédictions et décisions.", 24, True,
  [("tomorrow", "demain", "adverb"), ("next", "prochain (next week = la semaine prochaine)", "adjective"), ("soon", "bientôt", "adverb"), ("later", "plus tard", "adverb"), ("maybe", "peut-être", "adverb")]),
 (36, 5, "Je te promets", "Will pour les promesses et les propositions.", 24, False,
  [("promise", "promettre", "verb"), ("bring", "apporter", "verb"), ("send", "envoyer", "verb"), ("lend", "prêter", "verb"), ("borrow", "emprunter", "verb")]),
 (37, 5, "J'ai l'intention de…", "Going to pour les intentions.", 25, True,
  [("plan", "prévoir ; projet", "verb"), ("move", "déménager, bouger", "verb"), ("learn", "apprendre", "verb"), ("save", "économiser, sauvegarder", "verb"), ("change", "changer", "verb")]),
 (38, 5, "Mes projets", "Going to pour parler de projets de vie.", 25, False,
  [("year", "année, an", "noun"), ("job", "emploi, travail", "noun"), ("apartment", "appartement", "noun"), ("city", "ville", "noun"), ("country", "pays", "noun")]),
 (39, 5, "Will ou going to ?", "Choisir entre will et going to.", 26, True,
  [("probably", "probablement", "adverb"), ("hope", "espérer", "verb"), ("guess", "deviner, supposer", "verb"), ("idea", "idée", "noun"), ("problem", "problème", "noun")]),
 (40, 5, "Mon agenda", "Le présent continu pour les rendez-vous fixés.", 27, True,
  [("appointment", "rendez-vous (médical, administratif)", "noun"), ("meeting", "réunion", "noun"), ("dentist", "dentiste", "noun"), ("doctor", "médecin", "noun"), ("flight", "vol (avion)", "noun")]),
 (41, 6, "La maison", "There is / there are pour décrire un lieu.", 28, True,
  [("kitchen", "cuisine (pièce)", "noun"), ("bedroom", "chambre", "noun"), ("bathroom", "salle de bain", "noun"), ("living room", "salon", "noun"), ("garden", "jardin", "noun")]),
 (42, 6, "Les objets de la maison", "Décrire une pièce avec there is / there are.", 28, False,
  [("table", "table", "noun"), ("chair", "chaise", "noun"), ("sofa", "canapé", "noun"), ("fridge", "réfrigérateur, frigo", "noun"), ("lamp", "lampe", "noun")]),
 (43, 6, "Au restaurant", "Some / any pour commander et demander.", 29, True,
  [("menu", "menu, carte", "noun"), ("bill", "addition", "noun"), ("waiter", "serveur", "noun"), ("bread", "pain", "noun"), ("order", "commander", "verb")]),
 (44, 6, "Faire des achats", "How much / how many pour les prix et les quantités.", 30, True,
  [("price", "prix", "noun"), ("cheap", "bon marché, pas cher", "adjective"), ("expensive", "cher", "adjective"), ("shop", "magasin, boutique", "noun"), ("money", "argent", "noun")]),
 (45, 6, "Transport et voyage", "Révision de there is, some/any, how much/many en voyage.", 30, False,
  [("ticket", "billet, ticket", "noun"), ("station", "gare, station", "noun"), ("airport", "aéroport", "noun"), ("passport", "passeport", "noun"), ("luggage", "bagages", "noun")]),
 (46, 6, "L'heure et les nombres", "Dire l'heure, la date et les grands nombres.", 31, True,
  [("twenty", "vingt", "number"), ("hundred", "cent", "number"), ("hour", "heure (durée)", "noun"), ("minute", "minute", "noun"), ("half", "demi, moitié", "noun")]),
 (47, 7, "Un grand appartement neuf", "L'ordre des mots : adjectifs, adverbes, sujet-verbe-complément.", 32, True,
  [("big", "grand, gros", "adjective"), ("small", "petit", "adjective"), ("new", "nouveau, neuf", "adjective"), ("old", "vieux, ancien", "adjective"), ("beautiful", "beau, belle", "adjective")]),
 (48, 7, "Où est-ce ?", "Les prépositions de lieu.", 33, True,
  [("street", "rue", "noun"), ("park", "parc", "noun"), ("building", "bâtiment, immeuble", "noun"), ("floor", "étage ; sol", "noun"), ("corner", "coin", "noun")]),
 (49, 7, "In, on, at pour le temps", "Les prépositions de temps avec les jours, mois et saisons.", 34, True,
  [("Monday", "lundi", "noun"), ("Sunday", "dimanche", "noun"), ("January", "janvier", "noun"), ("summer", "été", "noun"), ("winter", "hiver", "noun")]),
 (50, 7, "Qui, quoi, où, pourquoi ?", "Les mots interrogatifs.", 35, True,
  [("time", "temps ; heure", "noun"), ("place", "endroit, lieu", "noun"), ("reason", "raison", "noun"), ("address", "adresse", "noun"), ("age", "âge", "noun")]),
 (51, 7, "Mais, parce que, donc", "Relier les idées avec des connecteurs.", 36, True,
  [("sun", "soleil", "noun"), ("hot", "chaud (très)", "adjective"), ("warm", "doux, chaud (agréablement)", "adjective"), ("wind", "vent", "noun"), ("snow", "neige ; neiger", "noun")]),
 (52, 7, "Plus rapide, le plus facile", "Comparatifs et superlatifs.", 37, True,
  [("fast", "rapide, vite", "adjective"), ("slow", "lent", "adjective"), ("tall", "grand (taille)", "adjective"), ("short", "court, petit (taille)", "adjective"), ("easy", "facile", "adjective")]),
 (53, 7, "Tu devrais…", "Should pour les conseils, could pour les possibilités.", 38, True,
  [("advice", "conseil(s)", "noun"), ("rest", "se reposer ; repos", "verb"), ("ill", "malade", "adjective"), ("medicine", "médicament", "noun"), ("exercise", "faire de l'exercice ; exercice", "verb")]),
 (54, 7, "Pourriez-vous… ?", "Demandes polies avec could et would like.", 38, False,
  [("would like", "voudrais, aimerais", "expression"), ("glass", "verre", "noun"), ("cup", "tasse", "noun"), ("dessert", "dessert", "noun"), ("salad", "salade", "noun")]),
 (55, 8, "As-tu déjà… ?", "Le present perfect pour parler d'expériences.", 39, True,
  [("abroad", "à l'étranger", "adverb"), ("museum", "musée", "noun"), ("film", "film", "noun"), ("ever", "déjà (dans une question), jamais", "adverb"), ("try", "essayer, goûter", "verb")]),
 (56, 8, "Je viens de finir", "Present perfect avec just, already et yet.", 39, False,
  [("already", "déjà", "adverb"), ("yet", "déjà (question), encore (négation)", "adverb"), ("just", "venir de (avec le present perfect)", "adverb"), ("email", "e-mail, courriel", "noun"), ("report", "rapport", "noun")]),
 (57, 8, "Oui, moi aussi", "Réponses courtes et expressions de politesse.", 40, True,
  [("nice to meet you", "enchanté(e)", "expression"), ("how are you", "comment ça va ?", "expression"), ("excuse me", "excusez-moi, pardon", "expression"), ("of course", "bien sûr", "expression"), ("no problem", "pas de problème", "expression")]),
 (58, 8, "Expressions du quotidien", "Expressions courantes pour comprendre et réagir.", 40, False,
  [("I understand", "je comprends, j'ai compris", "expression"), ("I don't know", "je ne sais pas", "expression"), ("never mind", "ce n'est pas grave, laisse tomber", "expression"), ("see you later", "à plus tard", "expression"), ("good luck", "bonne chance", "expression")]),
 (59, 8, "Choisir le bon temps", "Présent, passé, futur, present perfect : choisir selon le contexte.", 41, True,
  [("experience", "expérience", "noun"), ("life", "vie", "noun"), ("memory", "souvenir, mémoire", "noun"), ("moment", "moment", "noun"), ("chance", "occasion, chance", "noun")]),
 (60, 8, "Comprendre et s'exprimer", "Compréhension de textes courts et production de phrases autonomes.", 41, False,
  [("describe", "décrire", "verb"), ("explain", "expliquer", "verb"), ("believe", "croire", "verb"), ("agree", "être d'accord", "verb"), ("opinion", "avis, opinion", "noun")]),
]

MODULE_DIFFICULTY = {1: 1, 2: 1, 3: 2, 4: 2, 5: 3, 6: 2, 7: 3, 8: 4}
VERB_POS = {"verb", "phrasal_verb"}


def slug(text: str) -> str:
    s = text.lower().replace("'", "").replace("’", "")
    s = re.sub(r"[^a-z0-9]+", "_", s).strip("_")
    return s


def build():
    units = [G[n] for n in sorted(G)]
    lessons = []
    vocab_units = []
    seen = {}
    for seq, module, title, desc, gnum, intro_g, vocab in L:
        lid = f"en.l{seq:02d}"
        diff = MODULE_DIFFICULTY[module]
        vids = []
        for en, fr, pos in vocab:
            s = slug(en)
            if s in seen:
                sys.exit(f"duplicate vocab '{en}' in {lid} and {seen[s]}")
            seen[s] = lid
            uid = f"en.v.{s}"
            vids.append(uid)
            vocab_units.append(dict(
                id=uid, kind="vocabulary", category="verbs" if pos in VERB_POS else "vocabulary",
                title=en, translation=fr, partOfSpeech=pos, difficulty=diff, prerequisites=[],
                module=module, lessonId=lid, dictionaryItemId=f"en.d.{s}"))
        gid = G[gnum]["id"]
        lessons.append(dict(
            id=lid, module=module, sequence=seq, title=title, description=desc, difficulty=diff,
            grammarUnitId=gid, introducesGrammar=intro_g,
            introduces=([gid] if intro_g else []) + vids,
            reviews=[] if intro_g else [gid]))
    # sanity: each grammar unit introduced exactly once, before any lesson reviewing it
    intro_at = {}
    for les in lessons:
        if les["introducesGrammar"]:
            if les["grammarUnitId"] in intro_at:
                sys.exit(f"grammar {les['grammarUnitId']} introduced twice")
            intro_at[les["grammarUnitId"]] = les["sequence"]
    for u in units:
        if u["id"] not in intro_at:
            sys.exit(f"grammar {u['id']} never introduced")
        for p in u["prerequisites"]:
            if intro_at[p] >= intro_at[u["id"]]:
                sys.exit(f"prerequisite {p} introduced after {u['id']}")
    for les in lessons:
        if not les["introducesGrammar"] and intro_at[les["grammarUnitId"]] > les["sequence"]:
            sys.exit(f"{les['id']} reviews grammar not yet introduced")
    out = dict(
        language=dict(code="en", name="Anglais", nativeName="English", writingDirection="ltr", ttsLocale="en-GB"),
        contentVersion="2.0.0",
        modules=[dict(id=m, title=t, description=d) for m, t, d in MODULES],
        grammarUnits=units, vocabularyUnits=vocab_units, lessons=lessons)
    path = ROOT / "Content" / "en" / "curriculum.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(out, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"{len(lessons)} lessons, {len(units)} grammar units, {len(vocab_units)} vocabulary units -> {path}")


if __name__ == "__main__":
    build()
